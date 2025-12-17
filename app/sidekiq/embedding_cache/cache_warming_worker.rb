module EmbeddingCache
  # CacheWarmingWorker is responsible for pre-generating and caching embeddings
  # for frequently used or important queries to improve response times
  class CacheWarmingWorker
    include Sidekiq::Worker
    
    # Configure Sidekiq options
    sidekiq_options queue: :cache_warming, 
                    retry: 3, 
                    backtrace: true,
                    dead: false
    
    # Process a cache warming job
    # @param organization_id [Integer] Organization ID
    # @param query [String] The query to warm the cache with
    # @param options [Hash] Options for warming (domains, models, etc.)
    def perform(organization_id, query, options = {})
      # Skip if blank query
      return if query.blank?
      
      # Normalize options (convert string keys to symbols)
      options = options.transform_keys(&:to_sym) if options.is_a?(Hash)
      
      # Check which models to warm (default to base model)
      models = options[:models] || ['base']
      domain = options[:domain]
      
      warm_success = false
      
      # Process each requested model
      models.each do |model_name|
        # Generate embeddings with caching enabled
        begin
          # Use the HaystackClient to generate embeddings
          client = HaystackClient.new
          embedding = client.generate_embeddings(
            query,
            organization_id: organization_id,
            domain: domain,
            model_name: model_name,
            use_cache: true,
            warming: true  # Flag that this is a warming request
          )
          
          # Check if embedding was generated
          if embedding.present?
            Rails.logger.info "Cache warming successful for query '#{query}' (org: #{organization_id}, domain: #{domain || 'general'}, model: #{model_name})"
            warm_success = true
          else
            Rails.logger.warn "Cache warming failed to generate embedding for query '#{query}' (org: #{organization_id}, domain: #{domain || 'general'}, model: #{model_name})"
          end
        rescue => e
          Rails.logger.error "Error during cache warming for query '#{query}': #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end
      
      # Record warming attempt result
      record_warming_analytics(organization_id, domain, warm_success)
    end
    
    private
    
    # Record analytics for cache warming
    # @param organization_id [Integer] Organization ID
    # @param domain [String, nil] Domain if applicable
    # @param success [Boolean] Whether warming was successful
    def record_warming_analytics(organization_id, domain, success)
      # Record could be added to a cache warming metrics store
      # For now, we'll just log
      status = success ? 'successful' : 'failed'
      domain_str = domain.present? ? "domain #{domain}" : "general domain"
      Rails.logger.info "Cache warming #{status} for organization #{organization_id} (#{domain_str})"
      
      # Could track warming stats here in a more permanent store
      # if needed for admin dashboard metrics
    end
  end
end
