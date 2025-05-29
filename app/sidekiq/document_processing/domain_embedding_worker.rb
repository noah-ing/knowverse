module DocumentProcessing
  class DomainEmbeddingWorker
    include Sidekiq::Worker
    sidekiq_options queue: 'embedding', retry: 3
    
    # Process domain-specific embeddings for documents
    def perform(document_ids, domain, model_name = 'base', organization_id = nil)
      Rails.logger.info "Starting domain embedding generation for #{document_ids.size} documents in domain: #{domain}"
      
      begin
        # Ensure organization_id is set if domain isn't general
        unless domain == VectorEmbedding::DEFAULT_DOMAIN
          org_id = organization_id || Document.find(document_ids.first).organization_id
          raise "Organization ID required for domain-specific embeddings" unless org_id
        end
        
        # Fetch documents
        documents = Document.where(id: document_ids)
        
        if documents.empty?
          Rails.logger.warn "No documents found for IDs: #{document_ids}"
          return
        end
        
        documents.each do |document|
          process_document(document, domain, model_name, organization_id)
        end
        
        Rails.logger.info "Completed domain embedding generation for domain: #{domain}"
      rescue => e
        Rails.logger.error "Error in domain embedding generation: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise e
      end
    end
    
    private
    
    def process_document(document, domain, model_name, organization_id)
      Rails.logger.info "Processing domain embeddings for document #{document.id}, domain: #{domain}"
      
      # Skip if document has no content
      if document.content.blank?
        Rails.logger.warn "Document #{document.id} has no content, skipping."
        return
      end
      
      # Check if the document already has an embedding for this domain/model combination
      existing_embedding = document.vector_embeddings.find_by(
        domain: domain,
        model_name: model_name
      )
      
      if existing_embedding && existing_embedding.processed?
        Rails.logger.info "Document #{document.id} already has embeddings for domain #{domain}, model #{model_name}"
        return
      end
      
      # Create or update embedding
      embedding = existing_embedding || document.vector_embeddings.find_or_initialize_by(
        domain: domain,
        model_name: model_name
      )
      
      # Set dimension based on model_name
      embedding.dimension = VectorEmbedding::SUPPORTED_MODELS[model_name]
      embedding.status = VectorEmbedding::STATUS_PROCESSING
      embedding.save!
      
      begin
        # Connect to Haystack service to generate domain-specific embeddings
        haystack_client = HaystackClient.new
        embedding_data = haystack_client.generate_domain_embedding(
          text: document.content, 
          model_name: model_name, 
          domain: domain,
          organization_id: organization_id
        )
        
        # Update with embedding vector
        embedding.vector = embedding_data[:embedding]
        embedding.status = VectorEmbedding::STATUS_PROCESSED
        embedding.save!
        
        # If we have a domain embedding model reference, link it
        if domain != VectorEmbedding::DEFAULT_DOMAIN && organization_id
          domain_model = DomainEmbeddingModel.find_by(
            organization_id: organization_id,
            domain: domain,
            base_model: model_name,
            active: true
          )
          
          if domain_model
            embedding.domain_embedding_model = domain_model
            embedding.save!
          end
        end
        
        # Queue HNSW indexing if needed
        if Rails.application.config.use_hnsw_search
          DocumentProcessing::HnswMigrationWorker.perform_async([document.id], document.organization_id, model_name, domain)
        end
        
        Rails.logger.info "Successfully processed domain embeddings for document #{document.id}, domain: #{domain}"
      rescue => e
        Rails.logger.error "Error generating domain embeddings for document #{document.id}: #{e.message}"
        embedding.status = VectorEmbedding::STATUS_ERROR
        embedding.error_message = e.message
        embedding.save!
      end
    end
  end
end
