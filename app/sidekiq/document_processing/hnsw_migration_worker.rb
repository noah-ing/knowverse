module DocumentProcessing
  class HnswMigrationWorker < ActiveJob::Base
    queue_as :vector_migration
    
    # For backwards compatibility with existing code that might still use Sidekiq API
    def self.perform_async(batch_size = 100, organization_id = nil, model_name = 'base', dimension = nil)
      perform_later(batch_size, organization_id, model_name, dimension)
    end
    
    def perform(batch_size = 100, organization_id = nil, model_name = 'base', dimension = nil)
      # Determine dimension if not provided
      dimension ||= SearchRouter::MODELS[model_name] || 1024
      
      # Prepare scope for documents to migrate
      scope = Document.where(indexed_in_hnsw: false)
                     .where.not(embedding: nil)
                     .where(embedding_status: 'processed')
      
      # Filter by organization if specified
      scope = scope.where(organization_id: organization_id) if organization_id
      
      # Order by migration priority and limit to batch size
      documents = scope.order(migration_priority: :desc)
                      .limit(batch_size)
      
      # Process each document
      documents.find_each do |document|
        migrate_document(document, model_name, dimension)
      end
      
      # Schedule next batch if more documents exist
      remaining_count = scope.count - batch_size
      if remaining_count > 0
        Rails.logger.info("Scheduling next batch of HNSW migrations. Remaining: #{remaining_count}")
        HnswMigrationWorker.set(wait: 5.minutes).perform_later(batch_size, organization_id, model_name, dimension)
      end
    end
    
    private
    
    def migrate_document(document, model_name = 'base', dimension = nil)
      dimension ||= SearchRouter::MODELS[model_name] || 1024
      Rails.logger.info("Migrating document #{document.id} to HNSW index (dimension: #{dimension})")
      
      begin
        # Extract pgvector embedding
        pgvector_embedding = document.embedding
        return if pgvector_embedding.nil?
        
        # Convert to HNSW-compatible format
        hnsw_embedding = Wasm::WebassemblySearchService.instance.format_vector(pgvector_embedding)
        
        # Insert into HNSW index
        index_reference = Wasm::WebassemblySearchService.instance.insert(
          hnsw_embedding, 
          document.id,
          document.organization_id
        )
        
        # Mark as migrated and save reference
        document.update!(
          indexed_in_hnsw: true,
          hnsw_index_reference: index_reference,
          vector_dimension: dimension,
          embedding_model_name: model_name
        )
        
        Rails.logger.info("Successfully migrated document #{document.id} to HNSW index")
      rescue => e
        # Log error and tag document for retry
        Rails.logger.error("HNSW migration failed for document #{document.id}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        
        document.update(
          migration_error: e.message
        )
      end
    end
  end
end
