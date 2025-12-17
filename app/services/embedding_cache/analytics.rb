module EmbeddingCache
  # Analytics tracks cache usage statistics and performance metrics
  # It provides insights into hit rates, temporal patterns, and efficiency
  class Analytics
    # Initialize analytics
    def initialize
      # Track total hits by tier
      @memory_hits = Concurrent::AtomicFixnum.new(0)
      @redis_hits = Concurrent::AtomicFixnum.new(0)
      @misses = Concurrent::AtomicFixnum.new(0)
      
      # Track organization-specific analytics
      @org_stats = Concurrent::Map.new
      
      # Track domain-specific analytics
      @domain_stats = Concurrent::Map.new
      
      # Track start time for uptime calculations
      @start_time = Time.now.to_f
      
      # Lock for complex operations
      @lock = Concurrent::ReadWriteLock.new
    end
    
    # Record a cache hit
    # @param organization_id [Integer] Organization ID
    # @param tier [Symbol] Which tier the hit occurred in (:memory or :redis)
    # @param domain [String, nil] Domain if applicable
    def record_hit(organization_id, tier, domain = nil)
      # Increment global counters
      case tier
      when :memory
        @memory_hits.increment
      when :redis
        @redis_hits.increment
      end
      
      # Update organization counter
      org_key = organization_id.to_s
      org_stats = get_or_create_org_stats(org_key)
      
      case tier
      when :memory
        org_stats[:memory_hits].increment
      when :redis
        org_stats[:redis_hits].increment
      end
      
      # Update domain counter if domain provided
      if domain.present?
        domain_key = "#{org_key}:#{domain}"
        domain_stats = get_or_create_domain_stats(domain_key)
        
        case tier
        when :memory
          domain_stats[:memory_hits].increment
        when :redis
          domain_stats[:redis_hits].increment
        end
      end
    end
    
    # Record a cache miss
    # @param organization_id [Integer] Organization ID
    # @param domain [String, nil] Domain if applicable
    def record_miss(organization_id, domain = nil)
      # Increment global miss counter
      @misses.increment
      
      # Update organization counter
      org_key = organization_id.to_s
      org_stats = get_or_create_org_stats(org_key)
      org_stats[:misses].increment
      
      # Update domain counter if domain provided
      if domain.present?
        domain_key = "#{org_key}:#{domain}"
        domain_stats = get_or_create_domain_stats(domain_key)
        domain_stats[:misses].increment
      end
    end
    
    # Get overall cache statistics
    # @return [Hash] Overall cache statistics
    def stats
      # Calculate hit and miss totals
      total_hits = @memory_hits.value + @redis_hits.value
      total_misses = @misses.value
      total_requests = total_hits + total_misses
      
      # Calculate hit rates
      hit_rate = total_requests > 0 ? total_hits.to_f / total_requests : 0
      memory_hit_rate = total_requests > 0 ? @memory_hits.value.to_f / total_requests : 0
      redis_hit_rate = total_requests > 0 ? @redis_hits.value.to_f / total_requests : 0
      
      # Calculate uptime and requests per second
      uptime_seconds = Time.now.to_f - @start_time
      requests_per_second = uptime_seconds > 0 ? total_requests.to_f / uptime_seconds : 0
      
      {
        hits: total_hits,
        misses: total_misses,
        memory_hits: @memory_hits.value,
        redis_hits: @redis_hits.value,
        total_requests: total_requests,
        hit_rate: hit_rate,
        memory_hit_rate: memory_hit_rate,
        redis_hit_rate: redis_hit_rate,
        uptime_seconds: uptime_seconds,
        requests_per_second: requests_per_second
      }
    end
    
    # Get organization-specific cache statistics
    # @param organization_id [Integer] Organization ID
    # @return [Hash] Organization-specific cache statistics
    def organization_stats(organization_id)
      org_key = organization_id.to_s
      org_stats = @org_stats[org_key]
      
      if org_stats
        # Calculate hit and miss totals
        total_hits = org_stats[:memory_hits].value + org_stats[:redis_hits].value
        total_misses = org_stats[:misses].value
        total_requests = total_hits + total_misses
        
        # Calculate hit rates
        hit_rate = total_requests > 0 ? total_hits.to_f / total_requests : 0
        memory_hit_rate = total_requests > 0 ? org_stats[:memory_hits].value.to_f / total_requests : 0
        redis_hit_rate = total_requests > 0 ? org_stats[:redis_hits].value.to_f / total_requests : 0
        
        # Collect domain statistics
        domains = {}
        
        # Combine all stats for this organization
        @domain_stats.each do |key, stats|
          # Only include domains from this organization
          if key.start_with?("#{org_key}:")
            domain_name = key.split(':', 2)[1]
            domain_hits = stats[:memory_hits].value + stats[:redis_hits].value
            domain_total = domain_hits + stats[:misses].value
            
            domains[domain_name] = {
              hits: domain_hits,
              misses: stats[:misses].value,
              memory_hits: stats[:memory_hits].value,
              redis_hits: stats[:redis_hits].value,
              total_requests: domain_total,
              hit_rate: domain_total > 0 ? domain_hits.to_f / domain_total : 0
            }
          end
        end
        
        {
          hits: total_hits,
          misses: total_misses,
          memory_hits: org_stats[:memory_hits].value,
          redis_hits: org_stats[:redis_hits].value,
          total_requests: total_requests,
          hit_rate: hit_rate,
          memory_hit_rate: memory_hit_rate,
          redis_hit_rate: redis_hit_rate,
          domains: domains
        }
      else
        # Return empty stats if organization not found
        {
          hits: 0,
          misses: 0,
          memory_hits: 0,
          redis_hits: 0,
          total_requests: 0,
          hit_rate: 0,
          memory_hit_rate: 0,
          redis_hit_rate: 0,
          domains: {}
        }
      end
    end
    
    private
    
    # Get or create stats object for an organization
    # @param org_key [String] Organization key
    # @return [Hash] Organization stats object
    def get_or_create_org_stats(org_key)
      # Get existing or create new
      @org_stats.compute_if_absent(org_key) do
        {
          memory_hits: Concurrent::AtomicFixnum.new(0),
          redis_hits: Concurrent::AtomicFixnum.new(0),
          misses: Concurrent::AtomicFixnum.new(0)
        }
      end
    end
    
    # Get or create stats object for a domain
    # @param domain_key [String] Domain key (org:domain format)
    # @return [Hash] Domain stats object
    def get_or_create_domain_stats(domain_key)
      # Get existing or create new
      @domain_stats.compute_if_absent(domain_key) do
        {
          memory_hits: Concurrent::AtomicFixnum.new(0),
          redis_hits: Concurrent::AtomicFixnum.new(0),
          misses: Concurrent::AtomicFixnum.new(0)
        }
      end
    end
  end
end
