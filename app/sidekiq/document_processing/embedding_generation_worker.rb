# frozen_string_literal: true

module DocumentProcessing
  # EmbeddingGenerationWorker - Generates embeddings and indexes to Qdrant
  #
  # Uses Haystack (Python) for embedding generation and Qdrant (Rust) for storage.
  # This is the primary worker for processing new documents.
  #
  class EmbeddingGenerationWorker < ActiveJob::Base
    queue_as :embedding_generation

    # Custom error class for embedding generation failures
    class EmbeddingGenerationError < StandardError; end

    # Retry configuration: exponential backoff for transient failures
    retry_on EmbeddingGenerationError,
             wait: :polynomially_longer,
             attempts: 5

    # Don't retry on permanent failures
    discard_on ActiveRecord::RecordNotFound

    # For backwards compatibility with existing code
    def self.perform_async(document_id, model_name = 'small')
      perform_later(document_id, model_name)
    end

    # Process all pending documents
    def self.process_all_pending
      Document.embedding_pending.where(status: 'processed').find_each do |document|
        perform_later(document.id)
      end
    end

    def perform(document_id, model_name = 'small')
      document = Document.find_by(id: document_id)
      return unless document

      Rails.logger.info("Generating embeddings for document #{document_id} with model: #{model_name}")

      # Validate model name
      unless VectorEmbedding::SUPPORTED_MODELS.key?(model_name)
        Rails.logger.error("Unsupported model name: #{model_name}")
        return
      end

      # Get dimension for model
      dimension = VectorEmbedding::SUPPORTED_MODELS[model_name]

      begin
        # Set initial document embedding status
        if document.embedding_status == 'pending'
          document.mark_embedding_as_processing!
        end

        # Ensure document has content
        if document.content.blank?
          document.mark_embedding_as_error!("No content available for embedding generation")
          Rails.logger.error("Document #{document_id} has no content for embedding generation")
          return
        end

        # Check if embedding already exists and is processed
        existing = document.vector_embeddings.find_by(embedding_model: model_name)
        if existing&.processed?
          Rails.logger.info("Embedding for model #{model_name} already exists for document #{document_id}")
          # Still ensure it's indexed in Qdrant
          ensure_indexed_in_qdrant(document)
          return
        end

        # Create or update embedding record
        embedding_record = existing || document.vector_embeddings.new(
          embedding_model: model_name,
          dimension: dimension
        )
        embedding_record.mark_as_processing!

        # Generate embeddings using HaystackClient
        # CRITICAL: Real embeddings only - no mocks allowed
        embedding_vector = generate_embedding(document, model_name, dimension)

        # Validate embedding vector
        validate_embedding!(embedding_vector, dimension, document_id)

        # Store in vector_embeddings table
        embedding_record.update!(
          embedding_data: embedding_vector,
          status: VectorEmbedding::STATUS_PROCESSED
        )

        # For backward compatibility, also store in document.embedding
        if document.primary_embedding_type == model_name || document.primary_embedding_type.nil?
          document.update(
            embedding: embedding_vector,
            embedding_status: 'processed',
            vector_dimension: dimension,
            primary_embedding_type: model_name
          )
        end

        # Set as primary if first embedding
        if document.primary_embedding_type.nil? || document.vector_embeddings.processed.count == 1
          document.set_primary_embedding_type(model_name)
        end

        # Update document embedding status
        if document.embedding_status != 'processed' && document.vector_embeddings.processed.any?
          document.mark_embedding_as_processed!
        end

        # Index in Qdrant (replaces old HNSW dual-write)
        index_in_qdrant(document, embedding_vector, embedding_record)

        Rails.logger.info("Successfully completed embedding process for document #{document_id}")
      rescue EmbeddingGenerationError
        # Re-raise to trigger retry
        raise
      rescue => e
        handle_error(e, document, document_id, binding.local_variable_get(:embedding_record))
      end
    end

    private

    def generate_embedding(document, model_name, dimension)
      client = HaystackClient.new
      embedding_vector = client.generate_embeddings(
        document.content,
        model_name: model_name,
        dimension: dimension,
        organization_id: document.organization_id,
        use_cache: true
      )

      Rails.logger.info("Generated embeddings for document #{document.id} with model #{model_name}")
      embedding_vector
    rescue => e
      Rails.logger.error("Haystack service error: #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      nil
    end

    def validate_embedding!(embedding_vector, dimension, document_id)
      if embedding_vector.nil? || embedding_vector.empty?
        error_msg = "Embedding generation returned empty result"
        Rails.logger.error(
          "CRITICAL: Cannot generate embeddings for document #{document_id}. " \
          "Refusing to use mock embeddings. Error: #{error_msg}"
        )
        raise EmbeddingGenerationError, error_msg
      end

      unless embedding_vector.is_a?(Array) && embedding_vector.size == dimension
        error_msg = "Invalid embedding: expected array of size #{dimension}, got #{embedding_vector.class} of size #{embedding_vector&.size}"
        Rails.logger.error("Embedding validation failed for document #{document_id}: #{error_msg}")
        raise EmbeddingGenerationError, error_msg
      end
    end

    def index_in_qdrant(document, embedding_vector, embedding_record)
      search_service = Search::UnifiedSearchService.new

      # Check if Qdrant is healthy
      unless search_service.healthy?
        Rails.logger.warn("Qdrant not healthy, skipping indexing for document #{document.id}")
        mark_for_later_indexing(document, embedding_record, "Qdrant cluster unavailable")
        return
      end

      begin
        result = search_service.index_document(document)

        if result[:success]
          # Mark as indexed (using indexed_in_hnsw for backward compatibility)
          embedding_record.update(
            indexed_in_hnsw: true,
            hnsw_index_reference: "qdrant:#{document.organization_id}:#{document.id}"
          ) if embedding_record.respond_to?(:indexed_in_hnsw)

          if document.primary_embedding_type == embedding_record.embedding_model
            document.update(
              indexed_in_hnsw: true,
              hnsw_index_reference: "qdrant:#{document.organization_id}:#{document.id}"
            )
          end

          Rails.logger.info("Successfully indexed document #{document.id} in Qdrant")
        else
          raise "Qdrant upsert failed: #{result[:error]}"
        end
      rescue => e
        Rails.logger.error("Failed to index document #{document.id} in Qdrant: #{e.message}")
        mark_for_later_indexing(document, embedding_record, e.message)
      end
    end

    def ensure_indexed_in_qdrant(document)
      return if document.indexed_in_hnsw

      search_service = Search::UnifiedSearchService.new
      return unless search_service.healthy?

      begin
        search_service.index_document(document)
        document.update(indexed_in_hnsw: true)
      rescue => e
        Rails.logger.warn("Could not ensure document #{document.id} indexed in Qdrant: #{e.message}")
      end
    end

    def mark_for_later_indexing(document, embedding_record, error_message)
      embedding_record.update(
        indexed_in_hnsw: false,
        error_message: error_message
      ) if embedding_record.respond_to?(:indexed_in_hnsw)

      if document.primary_embedding_type == embedding_record.embedding_model
        document.update(
          migration_priority: 10,
          migration_error: error_message
        )
      end
    end

    def handle_error(error, document, document_id, embedding_record)
      Rails.logger.error("Embedding generation failed for document #{document_id}: #{error.message}")
      Rails.logger.error(error.backtrace.join("\n"))

      embedding_record&.mark_as_error!(error.message) if embedding_record

      if document.vector_embeddings.processed.none?
        document.mark_embedding_as_error!(error.message)
      end
    end
  end
end
