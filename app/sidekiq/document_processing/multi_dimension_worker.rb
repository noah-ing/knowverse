module DocumentProcessing
  class MultiDimensionWorker < ActiveJob::Base
    queue_as :embeddings
    
    # For backwards compatibility with existing code that might still use Sidekiq API
    def self.perform_async(document_ids, models = ['base'], organization_id = nil)
      perform_later(document_ids, models, organization_id)
    end
    
    # Process multiple models for a document or batch of documents
    # @param document_ids [Array, Integer] Single document ID or array of document IDs
    # @param models [Array] Array of model names to generate embeddings for
    # @param organization_id [Integer] Optional organization ID to filter documents
    def perform(document_ids, models = ['base'], organization_id = nil)
      document_ids = Array(document_ids)
      models = Array(models)
      
      # Validate models
      models = models.select { |m| VectorEmbedding::SUPPORTED_MODELS.key?(m) }
      return if models.empty?
      
      # Prepare document scope
      documents = Document.where(id: document_ids)
      documents = documents.where(organization_id: organization_id) if organization_id.present?
      
      Rails.logger.info("Processing #{models.join(', ')} embeddings for #{documents.count} documents")
      
      # Process each document with each model
      documents.find_each do |document|
        process_document(document, models)
      end
    end
    
    private
    
    def process_document(document, models)
      # Skip documents that aren't ready for embedding
      unless document.processed?
        Rails.logger.info("Skipping document #{document.id}: not processed")
        return
      end
      
      # Process each requested model
      models.each do |model_name|
        # Skip if already processed or in progress
        embedding = document.vector_embeddings.find_by(model_name: model_name)
        if embedding && (embedding.processed? || embedding.processing?)
          Rails.logger.info("Skipping #{model_name} for document #{document.id}: already #{embedding.status}")
          next
        end
        
        # Queue embedding generation
        Rails.logger.info("Queueing #{model_name} embedding for document #{document.id}")
        DocumentProcessing::EmbeddingGenerationWorker.perform_later(
          document.id, 
          model_name
        )
      end
      
      # If this is the first time we're generating embeddings, mark as processing
      if document.embedding_status == 'pending'
        document.mark_embedding_as_processing!
      end
    end
  end
end
