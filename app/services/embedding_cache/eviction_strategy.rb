module EmbeddingCache
  # EvictionStrategy provides logic for determining which cache entries should be
  # kept in memory vs. stored only in Redis, based on factors like:
  # - Domain confidence scores
  # - Query frequency
  # - Temporal locality
  # - Memory pressure
  class EvictionStrategy
    # Initialize the eviction strategy
    def initialize
      # Memory pressure threshold - when to start being more aggressive about eviction
      @memory_pressure_threshold = 0.8
      
      # How much weight to give to domain confidence in scoring
      @domain_confidence_weight = 0.6
      
      # How much weight to give to temporal locality (recency)
      @temporal_locality_weight = 0.4
      
      # Minimum score to qualify for memory tier (scale 0-1)
      @memory_tier_threshold = 0.5
    end
    
    # Determine if a value should be added to memory cache
    # @param memory_store [EmbeddingCache::MemoryStore] The memory store
    # @param key [String] Cache key
    # @param value [Object] Value to potentially store
    # @param options [Hash] Options with metadata about the value
    # @return [Boolean] Whether the value was added to memory
    def add_to_memory_if_worthy(memory_store, key, value, options = {})
      # Extract organization ID from key or options
      organization_id = options[:organization_id]
      return false unless organization_id
      
      # Extract domain from key or options
      domain = options[:domain]
      
      # Calculate the worthiness score for this entry
      score = calculate_worthiness_score(organization_id, domain)
      
      # Check memory pressure
      memory_stats = memory_store.stats
      memory_usage_ratio = memory_stats[:memory_bytes].to_f / memory_stats[:max_memory]
      
      # Adjust threshold based on memory pressure
      adjusted_threshold = if memory_usage_ratio > @memory_pressure_threshold
                            # Increase threshold when memory pressure is high
                            @memory_tier_threshold + (memory_usage_ratio - @memory_pressure_threshold)
                          else
                            @memory_tier_threshold
                          end
      
      # Determine if this entry should go into memory tier
      if score > adjusted_threshold
        # Add to memory store
        memory_store.set(key, value, options)
        true
      else
        # Not worthy of memory tier
        false
      end
    end
    
    private
    
    # Calculate a worthiness score for keeping an item in memory
    # @param organization_id [Integer] Organization ID
    # @param domain [String, nil] Domain name if applicable
    # @return [Float] Score between 0 and 1, higher means more worthy
    def calculate_worthiness_score(organization_id, domain)
      base_score = 0.5 # Default worthiness
      
      # If domain is provided, factor in domain confidence score
      if domain.present?
        confidence_score = get_domain_confidence_score(organization_id, domain)
        
        # Calculate temporal locality factor (how recently and frequently this domain has been used)
        temporal_locality = calculate_temporal_locality(organization_id, domain)
        
        # Combine factors with appropriate weights
        domain_factor = confidence_score * @domain_confidence_weight
        recency_factor = temporal_locality * @temporal_locality_weight
        
        # Final score is weighted combination
        score = base_score + domain_factor + recency_factor
        
        # Ensure score is between 0 and 1
        [0.0, [1.0, score].min].max
      else
        # For non-domain specific entries, use base score
        base_score
      end
    end
    
    # Get the confidence score for a domain
    # @param organization_id [Integer] Organization ID
    # @param domain [String] Domain name
    # @return [Float] Confidence score between 0 and 1
    def get_domain_confidence_score(organization_id, domain)
      # Try to get the most recent confidence score for this domain
      confidence_record = DomainConfidenceScore.where(
        organization_id: organization_id,
        domain: domain
      ).order(created_at: :desc).first
      
      # Return the confidence score or default
      confidence_record&.score || 0.5
    end
    
    # Calculate temporal locality factor based on recent usage
    # @param organization_id [Integer] Organization ID
    # @param domain [String] Domain name
    # @return [Float] Temporal locality factor between 0 and 1
    def calculate_temporal_locality(organization_id, domain)
      # For initial implementation, we'll use a simplified approach
      # In a real-world scenario, we'd track query frequency and recency
      
      # Check recent search queries for this domain
      one_day_ago = 24.hours.ago
      
      # Count recent queries for this domain
      recent_count = SearchQuery.where(
        organization_id: organization_id,
        created_at: one_day_ago..Time.now
      ).where("text LIKE ?", "%#{domain}%").count
      
      # Calculate a score based on recent activity
      # 0 recent queries = 0.0
      # 10+ recent queries = 1.0
      # Linear scale in between
      factor = [recent_count / 10.0, 1.0].min
      
      factor
    rescue => e
      Rails.logger.error("Error calculating temporal locality: #{e.message}")
      0.5 # Default to middle value on error
    end
  end
end
