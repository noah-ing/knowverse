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

    # Chunking configuration aligned with blueprint (400-512 tokens, 10-20% overlap)
    CHUNK_SIZE = 450
    CHUNK_OVERLAP = 50
    CHUNKING_STRATEGY = 'semantic'

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

        # STEP 1: Chunk the document content
        chunks = chunk_document(document)
        Rails.logger.info("Document #{document_id} split into #{chunks.size} chunks")

        # STEP 2: Generate embeddings for each chunk
        chunk_embeddings = generate_chunk_embeddings(chunks, model_name, dimension, document_id)

        # STEP 3: Store primary embedding (first chunk or average)
        primary_embedding = chunk_embeddings.first
        validate_embedding!(primary_embedding, dimension, document_id)

        embedding_record.update!(
          embedding_data: primary_embedding,
          status: VectorEmbedding::STATUS_PROCESSED,
          chunk_count: chunks.size
        )

        # For backward compatibility, also store in document.embedding
        if document.primary_embedding_type == model_name || document.primary_embedding_type.nil?
          document.update(
            embedding: primary_embedding,
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

        # STEP 4: Index ALL chunks in Qdrant (chunk-level indexing)
        index_chunks_in_qdrant(document, chunks, chunk_embeddings, embedding_record)

        Rails.logger.info("Successfully completed embedding process for document #{document_id} (#{chunks.size} chunks indexed)")
      rescue EmbeddingGenerationError
        # Re-raise to trigger retry
        raise
      rescue => e
        handle_error(e, document, document_id, binding.local_variable_get(:embedding_record))
      end
    end

    private

    def chunk_document(document)
      client = HaystackClient.new

      begin
        response = client.chunk_text(
          document.content,
          chunk_size: CHUNK_SIZE,
          chunk_overlap: CHUNK_OVERLAP,
          strategy: CHUNKING_STRATEGY
        )

        if response.success? && response.result['chunks'].present?
          response.result['chunks']
        else
          # Fallback: simple word-based chunking if Haystack fails
          Rails.logger.warn("Haystack chunking failed, using fallback chunking")
          fallback_chunk(document.content)
        end
      rescue => e
        Rails.logger.warn("Chunking service error: #{e.message}, using fallback")
        fallback_chunk(document.content)
      end
    end

    def fallback_chunk(content)
      words = content.split
      chunks = []

      i = 0
      while i < words.length
        chunk_words = words[i, CHUNK_SIZE]
        chunks << {
          'content' => chunk_words.join(' '),
          'chunk_index' => chunks.size,
          'start_char' => nil,
          'end_char' => nil
        }
        i += (CHUNK_SIZE - CHUNK_OVERLAP)
      end

      chunks.presence || [{ 'content' => content, 'chunk_index' => 0 }]
    end

    def generate_chunk_embeddings(chunks, model_name, dimension, document_id)
      client = HaystackClient.new
      chunk_contents = chunks.map { |c| c['content'] }

      begin
        # Use batch embedding for efficiency
        embeddings = client.generate_embeddings_batch(
          chunk_contents,
          model_name: model_name
        )

        if embeddings.present? && embeddings.size == chunks.size
          Rails.logger.info("Generated #{embeddings.size} chunk embeddings for document #{document_id}")
          embeddings
        else
          # Fallback: generate one at a time
          Rails.logger.warn("Batch embedding returned incomplete results, falling back to sequential")
          generate_embeddings_sequentially(chunk_contents, client, model_name, dimension)
        end
      rescue => e
        Rails.logger.warn("Batch embedding failed: #{e.message}, falling back to sequential")
        generate_embeddings_sequentially(chunk_contents, client, model_name, dimension)
      end
    end

    def generate_embeddings_sequentially(contents, client, model_name, dimension)
      contents.map do |content|
        client.generate_embeddings(content, model_name: model_name, dimension: dimension)
      end
    end

    def index_chunks_in_qdrant(document, chunks, embeddings, embedding_record)
      search_service = Search::UnifiedSearchService.new

      unless search_service.healthy?
        Rails.logger.warn("Qdrant not healthy, skipping chunk indexing for document #{document.id}")
        mark_for_later_indexing(document, embedding_record, "Qdrant cluster unavailable")
        return
      end

      begin
        # Build points for all chunks
        points = chunks.zip(embeddings).map.with_index do |(chunk, embedding), index|
          {
            id: "#{document.id}_chunk_#{index}",
            vector: embedding,
            payload: {
              document_id: document.id,
              organization_id: document.organization_id,
              title: document.title,
              chunk_index: index,
              total_chunks: chunks.size,
              content: chunk['content'],
              file_type: document.file_type,
              created_at: document.created_at.iso8601,
              start_char: chunk['start_char'],
              end_char: chunk['end_char']
            }
          }
        end

        # Bulk upsert all chunks
        result = search_service.bulk_index_points(document.organization_id, points)

        if result[:success]
          embedding_record.update(
            indexed_in_hnsw: true,
            hnsw_index_reference: "qdrant:#{document.organization_id}:#{document.id}:chunks:#{chunks.size}"
          ) if embedding_record.respond_to?(:indexed_in_hnsw)

          document.update(
            indexed_in_hnsw: true,
            hnsw_index_reference: "qdrant:#{document.organization_id}:#{document.id}:chunks:#{chunks.size}"
          )

          Rails.logger.info("Successfully indexed #{chunks.size} chunks for document #{document.id} in Qdrant")
        else
          raise "Qdrant bulk upsert failed: #{result[:error]}"
        end
      rescue => e
        Rails.logger.error("Failed to index chunks for document #{document.id} in Qdrant: #{e.message}")
        mark_for_later_indexing(document, embedding_record, e.message)
      end
    end

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
