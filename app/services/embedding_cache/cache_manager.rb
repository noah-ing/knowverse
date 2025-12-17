require 'singleton'

module EmbeddingCache
  # CacheManager provides a unified interface for working with the two-tier embedding cache
  # It orchestrates operations between the in-memory cache and Redis persistence layer
  # Implements the singleton pattern for global access across the application
  # Universal Docker environment: Full two-tier caching (memory + Redis) on all platforms
  class CacheManager
    include Singleton
    
    # Initialize cache manager for universal Docker environment
    def initialize
      # Initialize memory store (LRU cache) - available on all platforms
      @memory_store = MemoryStore.new
      
      # Initialize Redis store for persistence - full two-tier caching in Docker
      @redis_store = RedisStore.new
      Rails.logger.info "CacheManager: Universal Docker environment - using two-tier caching (memory + Redis)"
      
      # Initialize eviction strategy
      @eviction_strategy = EvictionStrategy.new
      
      # Initialize analytics for tracking cache usage
      @analytics = Analytics.new
      
      # Ready state indicator
      @initialized = true
      
      Rails.logger.info "CacheManager initialized with two-tier (memory + Redis) caching"
    end
    
    # Check if value exists in cache for a specific key
    # @param organization_id [Integer] Organization ID
    # @param key [String] The key to check
    # @param options [Hash] Options including domain, etc.
    # @return [Boolean] Whether the value exists in any cache level
    def exists?(organization_id, key, options = {})
      cache_key = build_cache_key(organization_id, key, options)
      
      # Check memory store first
      return true if @memory_store.exists?(cache_key)
      
      # Check Redis store (always available in Docker)
      return @redis_store.exists?(cache_key)
    end
    
    # Fetch value from cache, computing it if not found
    # @param organization_id [Integer] Organization ID
    # @param key [String] The key to fetch
    # @param options [Hash] Options including domain, etc.
    # @param block [Block] Block to execute if key not found
    # @return [Object] The value from cache or computed
    def fetch(organization_id, key, options = {}, &block)
      cache_key = build_cache_key(organization_id, key, options)
      
      # Check memory store first (first tier)
      value = @memory_store.get(cache_key)
      if value
        # Record analytics for memory hit
        @analytics.record_hit(organization_id, :memory, options[:domain])
        return value
      end
      
      # Check Redis store (second tier) - always available in Docker
      value = @redis_store.get(cache_key)
      if value
        # Record analytics for Redis hit
        @analytics.record_hit(organization_id, :redis, options[:domain])
        
        # Promote to memory cache if worthy
        @eviction_strategy.add_to_memory_if_worthy(
          @memory_store, 
          cache_key, 
          value,
          options.merge(organization_id: organization_id)
        )
        
        return value
      end
      
      # Record analytics for cache miss
      @analytics.record_miss(organization_id, options[:domain])
      
      # If block given, compute value and store
      if block_given?
        # Compute value using provided block
        value = yield
        
        # Store value in available cache tiers
        store(organization_id, key, value, options)
        
        return value
      end
      
      nil
    end
    
    # Store value in cache
    # @param organization_id [Integer] Organization ID
    # @param key [String] The key to store
    # @param value [Object] The value to store
    # @param options [Hash] Options including domain, TTL, etc.
    # @return [Boolean] Whether the value was stored successfully
    def store(organization_id, key, value, options = {})
      return false unless value
      
      cache_key = build_cache_key(organization_id, key, options)
      
      # Store in Redis (second tier) - always available in Docker
      redis_result = @redis_store.set(
        cache_key, 
        value, 
        ttl: options[:ttl],
        metadata: {
          organization_id: organization_id,
          domain: options[:domain],
          model: options[:model_name],
          dimension: options[:dimension]
        }
      )
      
      # Try to store in memory (first tier) based on eviction strategy
      memory_result = @eviction_strategy.add_to_memory_if_worthy(
        @memory_store,
        cache_key,
        value,
        options.merge(organization_id: organization_id)
      )
      
      # Return true if stored in either tier
      memory_result || redis_result
    end
    
    # Delete a specific entry from the cache
    # @param organization_id [Integer] Organization ID
    # @param key [String] The key to delete
    # @param options [Hash] Options including domain, etc.
    # @return [Boolean] Whether the value was deleted
    def delete(organization_id, key, options = {})
      cache_key = build_cache_key(organization_id, key, options)
      
      # Delete from both tiers
      memory_result = @memory_store.delete(cache_key)
      redis_result = @redis_store.delete(cache_key)
      
      # Return true if deleted from either tier
      memory_result || redis_result
    end
    
    # Clear the cache for a specific organization
    # @param organization_id [Integer] Organization ID
    # @return [Boolean] Whether the operation was successful
    def clear_organization(organization_id)
      # Clear from memory store (pattern: org:123:*)
      memory_result = @memory_store.delete_pattern("org:#{organization_id}:*")
      
      # Clear from Redis store - always available in Docker
      redis_result = @redis_store.delete_pattern("org:#{organization_id}:*")
      
      # Return true if cleared from either tier
      memory_result || redis_result
    end
    
    # Clear the cache for a specific domain within an organization
    # @param organization_id [Integer] Organization ID
    # @param domain [String] Domain name
    # @return [Boolean] Whether the operation was successful
    def clear_domain(organization_id, domain)
      # Only proceed if domain is provided
      return false unless domain.present?
      
      # Clear from memory store (pattern: org:123:domain:example:*)
      memory_result = @memory_store.delete_pattern("org:#{organization_id}:domain:#{domain}:*")
      
      # Clear from Redis store - always available in Docker
      redis_result = @redis_store.delete_pattern("org:#{organization_id}:domain:#{domain}:*")
      
      # Return true if cleared from either tier
      memory_result || redis_result
    end
    
    # Warm the cache for a specific organization - full background job support in Docker
    # @param organization_id [Integer] Organization ID
    # @param options [Hash] Options including source, limit, etc.
    # @return [Integer] Number of warming jobs enqueued
    def warm_cache(organization_id, options = {})
      source = options.delete(:source) || :popular_queries
      limit = options.delete(:limit) || 100
      models = options.delete(:models) || ['base']
      
      # Get queries to warm from specified source
      queries = get_warm_queries(organization_id, source, limit)
      return 0 if queries.empty?
      
      # Enqueue warming jobs for each query
      count = 0
      queries.each do |query|
        # Skip empty queries
        next if query.blank?
        
        # Enqueue the warming job
        EmbeddingCache::CacheWarmingWorker.perform_async(
          organization_id,
          query,
          options.merge(models: models)
        )
        
        count += 1
      end
      
      # Return number of warming jobs enqueued
      count
    end
    
    # Get overall cache statistics
    # @return [Hash] Cache statistics
    def stats
      # Get memory store stats
      memory_stats = @memory_store.stats
      
      # Get Redis store stats - always available in Docker
      redis_stats = @redis_store.stats
      
      # Get analytics stats
      analytics_stats = @analytics.stats
      
      {
        memory: memory_stats,
        redis: redis_stats,
        analytics: analytics_stats,
        platform: 'docker',
        cache_type: 'two-tier'
      }
    end
    
    # Get organization-specific cache statistics
    # @param organization_id [Integer] Organization ID
    # @return [Hash] Organization-specific cache statistics
    def organization_stats(organization_id)
      # Get memory store stats for organization
      memory_stats = @memory_store.organization_stats(organization_id)
      
      # Get Redis store stats for organization - always available in Docker
      redis_stats = @redis_store.organization_stats(organization_id)
      
      # Get analytics stats for organization
      analytics_stats = @analytics.organization_stats(organization_id)
      
      {
        memory: memory_stats,
        redis: redis_stats,
        analytics: analytics_stats,
        platform: 'docker',
        cache_type: 'two-tier'
      }
    end
    
    private
    
    # Build cache key from components
    # @param organization_id [Integer] Organization ID
    # @param key [String] Base key
    # @param options [Hash] Options for the key
    # @return [String] The constructed cache key
    def build_cache_key(organization_id, key, options = {})
      # Get domain if provided, or use general domain
      domain = options[:domain] || 'general'
      model = options[:model_name] || 'base'
      
      # Organization-scoped key with domain and model
      "org:#{organization_id}:domain:#{domain}:model:#{model}:#{key}"
    end
    
    # Get queries to use for cache warming
    # @param organization_id [Integer] Organization ID
    # @param source [Symbol] Source of queries (:popular_queries, :recent_queries, etc.)
    # @param limit [Integer] Maximum number of queries to return
    # @return [Array<String>] List of queries for warming
    def get_warm_queries(organization_id, source, limit)
      case source
      when :popular_queries
        # Get popular queries from search history
        SearchQuery.where(organization_id: organization_id)
                   .group(:text)
                   .order(Arel.sql('COUNT(*) DESC'))
                   .limit(limit)
                   .pluck(:text)
      when :recent_queries
        # Get most recent queries
        SearchQuery.where(organization_id: organization_id)
                   .order(created_at: :desc)
                   .limit(limit)
                   .pluck(:text)
                   .uniq
      when :problem_queries
        # Get queries with low relevance ratings
        SearchQuery.joins(:search_feedbacks)
                   .where(organization_id: organization_id)
                   .where(search_feedbacks: { relevant: false })
                   .group(:text)
                   .order(Arel.sql('COUNT(*) DESC'))
                   .limit(limit)
                   .pluck(:text)
      when :trending_queries
        # Get queries that have had a sudden increase in frequency
        # (implementation would depend on specific analytics schema)
        # For now, use a placeholder implementation
        SearchQuery.where(organization_id: organization_id)
                   .where('created_at > ?', 24.hours.ago)
                   .group(:text)
                   .order(Arel.sql('COUNT(*) DESC'))
                   .limit(limit)
                   .pluck(:text)
      else
        # Default to popular queries
        get_warm_queries(organization_id, :popular_queries, limit)
      end
    rescue => e
      Rails.logger.error("Error getting warm queries: #{e.message}")
      [] # Return empty array on error
    end
  end
end
