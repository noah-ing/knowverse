module DocumentProcessing
  class EmbeddingGenerationWorker < ActiveJob::Base
    queue_as :embedding_generation

    # Custom error class for embedding generation failures
    class EmbeddingGenerationError < StandardError; end

    # Retry configuration: exponential backoff for transient failures
    # Haystack service might be temporarily unavailable
    retry_on EmbeddingGenerationError,
             wait: :polynomially_longer,
             attempts: 5

    # Don't retry on permanent failures
    discard_on ActiveRecord::RecordNotFound

    # For backwards compatibility with existing code that might still use Sidekiq API
    def self.perform_async(document_id, model_name = 'small')
      perform_later(document_id, model_name)
    end
    
    # For direct access in Rails console to process documents
    def self.process_all_pending
      Document.embedding_pending.where(status: 'processed').each do |document|
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
        # Set initial document embedding status (if first time)
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
          return
        end
        
        # Create or update embedding record
        embedding_record = existing || document.vector_embeddings.new(
          embedding_model: model_name,
          dimension: dimension
        )
        embedding_record.mark_as_processing!
        
        # Generate embeddings using the HaystackClient
        # CRITICAL: We must get real embeddings - random vectors corrupt the search index
        embedding_vector = nil
        haystack_error = nil

        begin
          client = HaystackClient.new
          embedding_vector = client.generate_embeddings(
            document.content,
            model_name: model_name,
            dimension: dimension,
            organization_id: document.organization_id,
            use_cache: true
          )

          Rails.logger.info("Generated embeddings for document #{document_id} with model #{model_name}")
        rescue => e
          haystack_error = e
          Rails.logger.error("Haystack service error: #{e.message}")
          Rails.logger.error(e.backtrace.first(5).join("\n"))
        end

        # FAIL FAST: Do not use random/mock embeddings - they corrupt search results
        # If we couldn't generate real embeddings, fail the job so it can be retried
        if embedding_vector.nil? || embedding_vector.empty?
          error_msg = if haystack_error
            "Embedding generation failed: #{haystack_error.message}"
          else
            "Embedding generation returned empty result"
          end

          Rails.logger.error(
            "CRITICAL: Cannot generate embeddings for document #{document.id}. " \
            "Refusing to use mock embeddings as they would corrupt search results. " \
            "Error: #{error_msg}"
          )

          # Mark as failed so it can be retried
          embedding_record.mark_as_error!(error_msg)

          # Raise to trigger job retry with exponential backoff
          raise EmbeddingGenerationError, error_msg
        end

        # Validate embedding vector
        unless embedding_vector.is_a?(Array) && embedding_vector.size == dimension
          error_msg = "Invalid embedding: expected array of size #{dimension}, got #{embedding_vector.class} of size #{embedding_vector&.size}"
          Rails.logger.error("Embedding validation failed for document #{document.id}: #{error_msg}")
          embedding_record.mark_as_error!(error_msg)
          raise EmbeddingGenerationError, error_msg
        end
        
        # Store in vector_embeddings table
        embedding_record.update!(
          embedding_data: embedding_vector,
          status: VectorEmbedding::STATUS_PROCESSED
        )
        
        # For backward compatibility, also store in document.embedding for the primary embedding
        if document.primary_embedding_type == model_name || document.primary_embedding_type.nil?
          document.update(
            embedding: embedding_vector,
            embedding_status: 'processed',
            vector_dimension: dimension,
            primary_embedding_type: model_name
          )
        end
        
        # Set as primary if first embedding or no primary set
        if document.primary_embedding_type.nil? || document.vector_embeddings.processed.count == 1
          document.set_primary_embedding_type(model_name)
        end
        
        # Update document embedding status if at least one embedding is processed
        if document.embedding_status != 'processed' && document.vector_embeddings.processed.any?
          document.mark_embedding_as_processed!
        end
        
        # Also store in HNSW index (dual-write approach)
        store_in_hnsw(document, embedding_vector, dimension, embedding_record)
        
        Rails.logger.info("Successfully completed embedding process for document #{document_id}")
      rescue => e
        # Handle errors
        Rails.logger.error("Embedding generation failed for document #{document_id}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        
        # Update embedding record with error if it exists
        if defined?(embedding_record) && embedding_record
          embedding_record.mark_as_error!(e.message)
        end
        
        # Only update document status if it doesn't have any successful embeddings
        if document.vector_embeddings.processed.none?
          document.mark_embedding_as_error!(e.message)
        end
      end
    end
    
    private
    
    def store_in_hnsw(document, embedding_vector, dimension, embedding_record)
      begin
        # Format for HNSW
        hnsw_embedding = Wasm::WebassemblySearchService.instance.format_vector(embedding_vector)
        
        # Store in HNSW index
        index_reference = Wasm::WebassemblySearchService.instance.insert(
          hnsw_embedding,
          document.id,
          document.organization_id,
          dimension
        )
        
        # Update embedding record with HNSW reference
        embedding_record.mark_as_indexed_in_hnsw!(index_reference)
        
        # For backward compatibility, also update document for primary embedding
        if document.primary_embedding_type == embedding_record.embedding_model
          document.update(
            indexed_in_hnsw: true,
            hnsw_index_reference: index_reference
          )
        end
        
        Rails.logger.info("Successfully stored document #{document.id} embedding in HNSW index")
      rescue => e
        # Log error but don't fail the whole process
        Rails.logger.error("Failed to store document #{document.id} in HNSW index: #{e.message}")
        
        # Mark for later migration
        embedding_record.update(
          indexed_in_hnsw: false,
          error_message: e.message
        )
        
        # For backward compatibility
        if document.primary_embedding_type == embedding_record.embedding_model
          document.update(
            migration_priority: 10, # High priority
            migration_error: e.message
          )
        end
      end
    end
  end
end
