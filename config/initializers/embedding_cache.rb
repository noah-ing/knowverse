# Initialize the Universal Two-Tier Embedding Cache system (Enterprise-grade)
#
# This initializer configures the embedding cache with universal settings for
# environment-specific needs and ensures all cache components are properly set up.
# Universal configuration supports both memory and Redis on all platforms.

Rails.application.config.after_initialize do
  # Only set up in environments where we want caching
  if Rails.env.production? || Rails.env.development? || ENV['ENABLE_EMBEDDING_CACHE'] == 'true'
    
    Rails.logger.info "Initializing Universal Two-Tier Embedding Cache..."
    
    # Universal configuration with Redis support on all platforms
    redis_url = ENV['REDIS_URL'] || 'redis://localhost:6379/1'
    redis_namespace = ENV['REDIS_CACHE_NAMESPACE'] || 'embedding_cache'
    redis_ttl = (ENV['REDIS_CACHE_TTL'] || 86_400).to_i # Default 24 hours
    
    # Configure memory store settings (universal)
    memory_max_entries = (ENV['EMBEDDING_CACHE_MAX_ENTRIES'] || 100_000).to_i
    memory_max_mb = (ENV['EMBEDDING_CACHE_MAX_MB'] || 1024).to_i # Default 1GB
    
    # Set up class-level configuration for memory store
    if defined?(EmbeddingCache::MemoryStore)
      EmbeddingCache::MemoryStore.class_variable_set(:@@config, {
        max_entries: memory_max_entries,
        max_memory: memory_max_mb * 1024 * 1024 # Convert to bytes
      })
    end
    
    # Set up class-level configuration for Redis store  
    if defined?(EmbeddingCache::RedisStore)
      EmbeddingCache::RedisStore.class_variable_set(:@@config, {
        url: redis_url,
        namespace: redis_namespace,
        ttl: redis_ttl
      })
    end
    
    # Configure cache thresholds and weights for eviction strategy (all platforms)
    memory_pressure_threshold = (ENV['CACHE_MEMORY_PRESSURE_THRESHOLD'] || 0.8).to_f
    domain_confidence_weight = (ENV['CACHE_DOMAIN_CONFIDENCE_WEIGHT'] || 0.6).to_f
    temporal_locality_weight = (ENV['CACHE_TEMPORAL_LOCALITY_WEIGHT'] || 0.4).to_f
    memory_tier_threshold = (ENV['CACHE_MEMORY_TIER_THRESHOLD'] || 0.5).to_f
    
    # Set up the domain-aware eviction strategy
    strategy_options = {
      domain_weight: domain_confidence_weight,
      recency_weight: temporal_locality_weight,
      frequency_weight: 1.0 - domain_confidence_weight - temporal_locality_weight,
      domain_ttl_multiplier: (ENV['CACHE_DOMAIN_TTL_MULTIPLIER'] || 2.0).to_f,
      min_confidence_threshold: (ENV['CACHE_MIN_CONFIDENCE_THRESHOLD'] || 0.6).to_f,
      semantic_clustering: ENV['CACHE_SEMANTIC_CLUSTERING'] != 'false',
      organization_isolation: ENV['CACHE_ORGANIZATION_ISOLATION'] != 'false',
      prefetch_popular: ENV['CACHE_PREFETCH_POPULAR'] != 'false',
      ttl_sliding_window: ENV['CACHE_TTL_SLIDING_WINDOW'] != 'false'
    }
    
    # Register the domain-aware strategy with the cache manager
    if defined?(EmbeddingCache::CacheManager) && defined?(EmbeddingCache::DomainAwareStrategy)
      Rails.logger.info "Registering Domain-Aware Eviction Strategy..."
      
      # Create and initialize the strategy
      domain_strategy = EmbeddingCache::DomainAwareStrategy.new(strategy_options)
      
      # Set it as the default strategy for the cache manager
      manager = EmbeddingCache::CacheManager.instance
      manager.strategy = domain_strategy if manager.respond_to?(:strategy=)
      
      # Set up cache warming job if enabled (universal background job support)
      if ENV['ENABLE_CACHE_WARMING'] == 'true' && defined?(EmbeddingCache::CacheWarmingWorker)
        Rails.logger.info "Setting up embedding cache warming..."
        
        # Schedule the cache warming job to run periodically
        warming_interval = (ENV['CACHE_WARMING_INTERVAL_MINUTES'] || 30).to_i
        EmbeddingCache::CacheWarmingWorker.perform_in(5.minutes)
        
        # Add a recurring job if Sidekiq-Scheduler is available
        if defined?(Sidekiq) && Sidekiq.respond_to?(:set_schedule)
          Sidekiq.set_schedule(
            'embedding_cache_warming',
            {
              'every' => "#{warming_interval}m",
              'class' => 'EmbeddingCache::CacheWarmingWorker',
              'queue' => 'low'
            }
          )
        end
      end
    else
      Rails.logger.warn "DomainAwareStrategy not loaded - using default eviction strategy"
    end
    
    # Enable cache in HaystackClient (all platforms)
    if defined?(HaystackClient)
      # Patch HaystackClient to use embedding cache
      unless HaystackClient.method_defined?(:generate_embeddings_with_cache)
        HaystackClient.class_eval do
          # The original method
          alias_method :generate_embeddings_without_cache, :generate_embeddings
          
          # The new method with caching
          def generate_embeddings(text, options = {})
            # Skip cache if explicitly disabled
            return generate_embeddings_without_cache(text, options) unless options[:use_cache] != false
            
            # Get organization ID, domain, and model
            organization_id = options[:organization_id]
            domain = options[:domain]
            model_name = options[:model_name] || 'base'
            
            # Skip cache if no organization ID
            return generate_embeddings_without_cache(text, options) unless organization_id.present?
            
            # Get cache manager
            cache_manager = EmbeddingCache::CacheManager.instance
            
            # Generate cache key
            # Normalize text to create consistent keys
            normalized_text = text.to_s.strip.downcase
            cache_key = "embedding:#{normalized_text.hash}"
            
            # Try to get from cache
            embedding = cache_manager.fetch(organization_id, cache_key, 
                                          domain: domain, 
                                          model_name: model_name) do
              # Generate if not in cache
              generate_embeddings_without_cache(text, options)
            end
            
            embedding
          end
        end
        
        Rails.logger.info "HaystackClient patched to use embedding cache"
      end
    end
    
    Rails.logger.info "Universal Two-Tier Embedding Cache initialized successfully"
  else
    Rails.logger.info "Embedding Cache not enabled in this environment"
  end
end
