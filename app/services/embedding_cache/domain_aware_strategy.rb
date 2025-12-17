# frozen_string_literal: true

module EmbeddingCache
  # Domain-aware cache eviction strategy that optimizes for domain-specific embedding models
  # and vector search patterns.
  #
  # This strategy prioritizes cache entries based on:
  # 1. Domain relevance scores
  # 2. Recent usage patterns
  # 3. Organization-specific query distributions
  # 4. Semantic clustering of related queries
  #
  class DomainAwareStrategy < EvictionStrategy
    # Configure the strategy with domain-aware options
    # @param options [Hash] Configuration options
    def initialize(options = {})
      super() # Call the parent initializer with no arguments
      
      @options = {
        domain_weight: 0.5,           # Weight given to domain relevance (0-1)
        recency_weight: 0.3,          # Weight given to recency (0-1)
        frequency_weight: 0.2,        # Weight given to access frequency (0-1)
        domain_ttl_multiplier: 2.0,   # Multiply TTL for domain-specific entries
        min_confidence_threshold: 0.6, # Minimum confidence for preferential caching
        semantic_clustering: true,    # Use semantic clustering for related queries
        organization_isolation: true, # Isolate caches by organization
        prefetch_popular: true,       # Prefetch popular queries
        ttl_sliding_window: true      # Use sliding window TTL based on access
      }.merge(options)
      
      # Override parent class settings with our options if provided
      @memory_pressure_threshold = @options[:memory_pressure_threshold] if @options[:memory_pressure_threshold]
      @domain_confidence_weight = @options[:domain_weight] if @options[:domain_weight]
      @temporal_locality_weight = @options[:recency_weight] if @options[:recency_weight]
      @memory_tier_threshold = @options[:memory_tier_threshold] if @options[:memory_tier_threshold]
      
      @domain_confidence_scores = {}
      @access_stats = {}
      @semantic_clusters = {}
    end
    
    # Choose entries to evict based on domain-aware priorities
    # @param entries [Array<CacheEntry>] List of cache entries
    # @param space_needed [Integer] Amount of space needed in bytes
    # @return [Array<CacheEntry>] Entries to evict
    def choose_entries_to_evict(entries, space_needed)
      # Skip if no entries
      return [] if entries.nil? || entries.empty?
      
      # Calculate scores for each entry
      scored_entries = entries.map do |entry|
        score = calculate_entry_score(entry)
        [entry, score]
      end
      
      # Sort by score (lower scores are evicted first)
      sorted_entries = scored_entries.sort_by { |_, score| score }
      
      # Choose entries to evict until space needed is satisfied
      entries_to_evict = []
      space_freed = 0
      
      sorted_entries.each do |entry, _|
        break if space_freed >= space_needed
        
        entries_to_evict << entry
        space_freed += entry.size
      end
      
      entries_to_evict
    end
    
    # Calculate a priority score for a cache entry
    # @param entry [CacheEntry] The cache entry
    # @return [Float] Priority score (higher means more important)
    def calculate_entry_score(entry)
      # Extract metadata from entry key
      metadata = extract_metadata_from_key(entry.key)
      
      # Calculate component scores
      domain_score = calculate_domain_score(metadata, entry)
      recency_score = calculate_recency_score(entry)
      frequency_score = calculate_frequency_score(entry.key)
      
      # Combine scores with configured weights
      total_score = (
        domain_score * @options[:domain_weight] +
        recency_score * @options[:recency_weight] +
        frequency_score * @options[:frequency_weight]
      )
      
      # Adjust for organization isolation if needed
      if @options[:organization_isolation] && metadata[:organization_id]
        # Boost organization-specific entries
        total_score *= 1.5
      end
      
      # Boost semantically related entries to recent queries
      if @options[:semantic_clustering] && in_recent_semantic_cluster?(metadata)
        total_score *= 1.2
      end
      
      total_score
    end
    
    # Record an access to a cache entry for statistics
    # @param key [String] Cache key
    # @param hit [Boolean] Whether the access was a cache hit
    def record_access(key, hit = true)
      @access_stats[key] ||= { hits: 0, misses: 0, last_access: nil }
      
      if hit
        @access_stats[key][:hits] += 1
      else
        @access_stats[key][:misses] += 1
      end
      
      @access_stats[key][:last_access] = Time.current
      
      # Update semantic clusters if enabled
      update_semantic_clusters(key) if @options[:semantic_clustering]
    end
    
    # Adjust TTL for a cache entry based on domain relevance
    # @param key [String] Cache key
    # @param ttl [Integer] Original TTL in seconds
    # @return [Integer] Adjusted TTL
    def adjust_ttl(key, ttl)
      return ttl unless @options[:ttl_sliding_window]
      
      metadata = extract_metadata_from_key(key)
      
      # If domain-specific with high confidence, extend TTL
      if metadata[:domain_id] && metadata[:domain_id] != 'default'
        # Check if we have a confidence score
        if metadata[:confidence] && metadata[:confidence] >= @options[:min_confidence_threshold]
          return (ttl * @options[:domain_ttl_multiplier]).to_i
        end
      end
      
      # Use standard TTL for other entries
      ttl
    end
    
    # Update domain confidence scores for a model
    # @param domain_id [String] Domain ID
    # @param confidence_data [Hash] Confidence score data
    def update_domain_confidence(domain_id, confidence_data)
      @domain_confidence_scores[domain_id.to_s] = confidence_data
    end
    
    # Identify candidates for prefetching
    # @param max_count [Integer] Maximum number of candidates
    # @return [Array<String>] Keys of entries to prefetch
    def prefetch_candidates(max_count = 20)
      return [] unless @options[:prefetch_popular]
      
      # Get entries with highest frequency scores
      entries = @access_stats.sort_by { |_, stats| -calculate_frequency_from_stats(stats) }
      
      # Return top N keys
      entries.take(max_count).map(&:first)
    end
    
    # Reset all statistics
    def reset_stats
      @access_stats = {}
      @semantic_clusters = {}
    end
    
    private
    
    # Extract metadata from a cache key
    # @param key [String] Cache key
    # @return [Hash] Extracted metadata
    def extract_metadata_from_key(key)
      metadata = {}
      
      # Try to parse vector search keys
      if key.to_s.start_with?('vector_search:')
        parts = key.to_s.split(':')
        
        if parts.length >= 2
          metadata[:domain_id] = parts[1]
          
          # If query hash contains confidence in format domain:hash:confidence
          if parts.length >= 4 && parts[3].to_f > 0
            metadata[:confidence] = parts[3].to_f
          end
          
          # Check if organization-specific
          if parts.length >= 3 && parts[2].match?(/^org_\d+$/)
            metadata[:organization_id] = parts[2].sub('org_', '')
          end
        end
      end
      
      metadata
    end
    
    # Calculate domain relevance score
    # @param metadata [Hash] Entry metadata
    # @param entry [CacheEntry] Cache entry
    # @return [Float] Domain score (0-1)
    def calculate_domain_score(metadata, entry)
      # Default score for non-domain entries
      return 0.1 unless metadata[:domain_id] && metadata[:domain_id] != 'default'
      
      # Get confidence from metadata or default
      confidence = metadata[:confidence] || 0.7
      
      # Check if we have domain confidence data
      if @domain_confidence_scores[metadata[:domain_id]]
        confidence_data = @domain_confidence_scores[metadata[:domain_id]]
        
        # If entry has a confidence score, use that as base
        base_score = [confidence, 0.2].max
        
        # Adjust using domain confidence data
        usage_factor = confidence_data[:usage_frequency] || 0.5
        quality_factor = confidence_data[:quality_metric] || 0.5
        
        return base_score * (0.5 + usage_factor * 0.25 + quality_factor * 0.25)
      end
      
      # If no confidence data, just use confidence
      [confidence, 0.3].max
    end
    
    # Calculate recency score based on last access time
    # @param entry [CacheEntry] Cache entry
    # @return [Float] Recency score (0-1)
    def calculate_recency_score(entry)
      stats = @access_stats[entry.key]
      
      # If no stats, check entry created_at
      last_access = if stats && stats[:last_access]
                      stats[:last_access]
                    elsif entry.respond_to?(:created_at)
                      entry.created_at
                    else
                      1.day.ago
                    end
      
      # Calculate how recent this access is (1.0 = just now, 0.0 = oldest possible)
      # Use logarithmic decay over time (maintains high score for recent items)
      seconds_ago = Time.current - last_access
      Math.exp(-(seconds_ago / 1.day)) # Exponential decay over a day
    end
    
    # Calculate frequency score based on access counts
    # @param key [String] Cache key
    # @return [Float] Frequency score (0-1)
    def calculate_frequency_score(key)
      stats = @access_stats[key]
      return 0.1 unless stats
      
      calculate_frequency_from_stats(stats)
    end
    
    # Calculate frequency from stats hash
    # @param stats [Hash] Access statistics
    # @return [Float] Frequency score (0-1)
    def calculate_frequency_from_stats(stats)
      total_accesses = stats[:hits] + stats[:misses]
      
      # Logarithmic scale - provides diminishing returns for very frequent access
      # but still gives higher values to more accessed entries
      if total_accesses > 0
        # Normalize to 0-1 range with logarithmic scaling
        # ln(1) = 0, ln(100) ≈ 4.6, ln(1000) ≈ 6.9
        # So we divide by 7 to normalize approximately
        [Math.log(total_accesses) / 7, 1.0].min
      else
        0.0
      end
    end
    
    # Check if entry belongs to a recently active semantic cluster
    # @param metadata [Hash] Entry metadata
    # @return [Boolean] Whether in recent cluster
    def in_recent_semantic_cluster?(metadata)
      return false unless @options[:semantic_clustering]
      return false if @semantic_clusters.empty?
      
      # For now, just check if domain matches any recent cluster
      return false unless metadata[:domain_id]
      
      # Find recent clusters (accessed in last hour)
      recent_clusters = @semantic_clusters.select do |_, cluster|
        cluster[:last_access] > 1.hour.ago
      end
      
      # Check if any cluster contains this domain
      recent_clusters.any? do |_, cluster|
        cluster[:domains].include?(metadata[:domain_id])
      end
    end
    
    # Update semantic clusters with a new access
    # @param key [String] Cache key
    def update_semantic_clusters(key)
      metadata = extract_metadata_from_key(key)
      return unless metadata[:domain_id]
      
      # Find or create cluster
      cluster_key = "cluster_#{metadata[:domain_id]}"
      
      @semantic_clusters[cluster_key] ||= {
        domains: [metadata[:domain_id]],
        last_access: Time.current,
        access_count: 0
      }
      
      # Update cluster stats
      @semantic_clusters[cluster_key][:last_access] = Time.current
      @semantic_clusters[cluster_key][:access_count] += 1
    end
  end
end
