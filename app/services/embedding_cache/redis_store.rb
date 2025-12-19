require 'redis'

module EmbeddingCache
  # RedisStore provides a persistent cache using Redis for embedding vectors
  # This is the second tier of the caching architecture for persistence across application restarts
  class RedisStore
    # Default configuration
    DEFAULT_TTL = 86_400  # 24 hours in seconds
    DEFAULT_NAMESPACE = 'embedding_cache'
    
    # Class variable for configuration
    @@config = {}
    
    # Initialize the Redis store
    def initialize
      # Get configuration
      config = @@config.dup
      
      # Get Redis URL from config or environment
      redis_url = config[:url] || ENV['REDIS_URL'] || 'redis://localhost:6379/1'
      
      # Get namespace from config
      @namespace = config[:namespace] || DEFAULT_NAMESPACE
      
      # Get default TTL from config
      @default_ttl = config[:ttl] || DEFAULT_TTL
      
      # Initialize Redis client
      @redis = Redis.new(url: redis_url)
      
      # Test connection
      begin
        @redis.ping
        Rails.logger.info "RedisStore connected to #{redis_url} with namespace '#{@namespace}'"
      rescue Redis::CannotConnectError, Redis::ConnectionError, Errno::ECONNRESET, Errno::ECONNREFUSED => e
        Rails.logger.warn "RedisStore failed to connect to #{redis_url}: #{e.message} - falling back to memory-only caching"
        @redis = nil
      rescue => e
        Rails.logger.warn "RedisStore unexpected error: #{e.class} #{e.message} - falling back to memory-only caching"
        @redis = nil
      end
    end
    
    # Check if a key exists in the cache
    # @param key [String] The key to check
    # @return [Boolean] Whether the key exists
    def exists?(key)
      return false unless @redis
      
      # Add namespace to key
      namespaced_key = namespaced(key)
      
      # Check if key exists
      @redis.exists?(namespaced_key)
    end
    
    # Get a value from the cache
    # @param key [String] The key to get
    # @return [Object, nil] The value if found, nil otherwise
    def get(key)
      return nil unless @redis
      
      # Add namespace to key
      namespaced_key = namespaced(key)
      
      # Get serialized value
      serialized = @redis.get(namespaced_key)
      return nil unless serialized
      
      # Deserialize value (JSON for metadata, Marshal for vector data)
      begin
        data = JSON.parse(serialized)
        
        # Check if this is a metadata wrapper or direct value
        if data.is_a?(Hash) && data.key?('__vector')
          # Deserialize the actual vector data
          Marshal.load(Base64.decode64(data['__vector']))
        else
          # Return data directly
          data
        end
      rescue JSON::ParserError, TypeError => e
        # If not valid JSON, try direct Marshal deserialization
        begin
          Marshal.load(serialized)
        rescue => e2
          Rails.logger.error "Error deserializing value for '#{key}': #{e2.message}"
          nil
        end
      end
    end
    
    # Store a value in the cache
    # @param key [String] The key to store
    # @param value [Object] The value to store
    # @param options [Hash] Options including TTL, metadata, etc.
    # @return [Boolean] Whether the value was stored
    def set(key, value, options = {})
      return false unless @redis
      
      # Add namespace to key
      namespaced_key = namespaced(key)
      
      # Get TTL from options or use default
      ttl = options[:ttl] || @default_ttl
      
      # Add metadata if provided
      metadata = options[:metadata]
      
      # Serialize the value
      serialized = if metadata
                    # Store with metadata (use JSON for metadata, Base64+Marshal for vector)
                    JSON.generate({
                      '__vector' => Base64.encode64(Marshal.dump(value)),
                      'metadata' => metadata,
                      'created_at' => Time.now.to_i
                    })
                  else
                    # Store vector directly (use Marshal for efficiency)
                    Marshal.dump(value)
                  end
      
      # Set value with TTL
      @redis.setex(namespaced_key, ttl, serialized)
    end
    
    # Delete a key from the cache
    # @param key [String] The key to delete
    # @return [Boolean] Whether the key was deleted
    def delete(key)
      return false unless @redis
      
      # Add namespace to key
      namespaced_key = namespaced(key)
      
      # Delete the key
      @redis.del(namespaced_key) > 0
    end
    
    # Delete keys matching a pattern
    # @param pattern [String] The pattern to match (with * as wildcard)
    # @return [Boolean] Whether any keys were deleted
    def delete_pattern(pattern)
      return false unless @redis
      
      # Add namespace to pattern
      namespaced_pattern = namespaced(pattern)
      
      # Get keys matching pattern
      keys = @redis.keys(namespaced_pattern)
      return false if keys.empty?
      
      # Delete all matched keys
      @redis.del(*keys) > 0
    end
    
    # Get organization-specific statistics
    # @param organization_id [Integer] Organization ID
    # @return [Hash] Organization-specific statistics
    def organization_stats(organization_id)
      return { size: 0, domains: [] } unless @redis
      
      # Pattern for organization keys
      org_pattern = namespaced("org:#{organization_id}:*")
      
      # Get keys for this organization
      keys = @redis.keys(org_pattern)
      
      # Get domain statistics
      domains = {}
      keys.each do |key|
        # Extract domain from key if present
        if key =~ /org:#{organization_id}:domain:([^:]+):/
          domain = $1
          domains[domain] ||= 0
          domains[domain] += 1
        end
      end
      
      # Format domain stats
      domain_stats = domains.map do |domain, count|
        { domain: domain, count: count }
      end
      
      {
        size: keys.size,
        domains: domain_stats
      }
    end
    
    # Get overall statistics
    # @return [Hash] Overall statistics
    def stats
      return { size: 0 } unless @redis
      
      # Pattern for all keys in namespace
      pattern = namespaced('*')
      
      # Get all keys
      keys = @redis.keys(pattern)
      
      # Count by organization
      orgs = {}
      keys.each do |key|
        if key =~ /org:(\d+):/
          org_id = $1
          orgs[org_id] ||= 0
          orgs[org_id] += 1
        end
      end
      
      {
        size: keys.size,
        organizations: orgs
      }
    end
    
    private
    
    # Add namespace to key
    # @param key [String] The original key
    # @return [String] The namespaced key
    def namespaced(key)
      "#{@namespace}:#{key}"
    end
  end
end
