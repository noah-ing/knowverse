require 'concurrent'

module EmbeddingCache
  # MemoryStore provides an in-memory LRU cache for embedding vectors
  # This is the first tier of the caching architecture for ultra-fast access
  class MemoryStore
    # Default configuration
    DEFAULT_MAX_ENTRIES = 100_000 # Maximum number of entries
    DEFAULT_MAX_MEMORY = 1_073_741_824 # 1GB in bytes
    
    # Class variable for configuration
    @@config = {}
    
    # Initialize the memory store
    def initialize
      # The main LRU cache to store entries with values
      @cache = Concurrent::Map.new
      
      # Access time tracking for LRU eviction
      @access_times = Concurrent::Map.new
      
      # Organization entry counting for multi-tenant isolation
      @org_counters = Concurrent::Map.new
      
      # Approximate memory usage tracking (in bytes)
      @memory_usage = Concurrent::AtomicFixnum.new(0)
      
      # Cache settings
      @max_entries = @@config[:max_entries] || DEFAULT_MAX_ENTRIES
      @max_memory = @@config[:max_memory] || DEFAULT_MAX_MEMORY
      
      # Lock for complex operations
      @lock = Concurrent::ReadWriteLock.new
      
      Rails.logger.info "MemoryStore initialized with max #{@max_entries} entries, #{@max_memory / 1_048_576}MB memory limit"
    end
    
    # Check if a key exists in the cache
    # @param key [String] The key to check
    # @return [Boolean] Whether the key exists
    def exists?(key)
      @cache.key?(key)
    end
    
    # Get a value from the cache
    # @param key [String] The key to get
    # @return [Object, nil] The value if found, nil otherwise
    def get(key)
      # Check if the key exists
      return nil unless @cache.key?(key)
      
      # Update access time for LRU tracking
      @access_times[key] = Time.now.to_f
      
      # Return the value
      @cache[key]
    end
    
    # Store a value in the cache
    # @param key [String] The key to store
    # @param value [Object] The value to store
    # @param options [Hash] Options including organization_id, TTL, etc.
    # @return [Boolean] Whether the value was stored
    def set(key, value, options = {})
      # Extract organization ID from key or options
      organization_id = options[:organization_id] || extract_org_id(key)
      
      # Calculate memory usage for this entry (approximate)
      entry_size = estimate_size(key, value)
      
      # Check if we have enough space or need to evict entries
      need_eviction = false
      
      # Acquire write lock for eviction check
      @lock.with_read_lock do
        total_entries = @cache.size
        total_memory = @memory_usage.value
        
        # Check if we need to evict based on entry count or memory limit
        need_eviction = (total_entries >= @max_entries) || 
                        (total_memory + entry_size >= @max_memory)
      end
      
      # Perform eviction if needed
      if need_eviction
        # Evict entries based on LRU policy
        evict_entries(entry_size, organization_id)
      end
      
      # Check if the key already exists
      if @cache.key?(key)
        # Update existing entry
        old_value = @cache[key]
        old_size = estimate_size(key, old_value)
        
        # Update memory usage (subtract old, add new)
        @memory_usage.update { |v| v - old_size + entry_size }
      else
        # Add new entry
        
        # Update organization counter
        if organization_id
          org_count = @org_counters[organization_id] || Concurrent::AtomicFixnum.new(0)
          org_count.increment
          @org_counters[organization_id] = org_count
        end
        
        # Update memory usage
        @memory_usage.update { |v| v + entry_size }
      end
      
      # Store the value and update access time
      @cache[key] = value
      @access_times[key] = Time.now.to_f
      
      true
    end
    
    # Delete a key from the cache
    # @param key [String] The key to delete
    # @return [Boolean] Whether the key was deleted
    def delete(key)
      # Check if the key exists
      return false unless @cache.key?(key)
      
      # Acquire write lock for deletion
      @lock.with_write_lock do
        # Get the value
        value = @cache[key]
        
        # Calculate entry size
        entry_size = estimate_size(key, value)
        
        # Update memory usage
        @memory_usage.update { |v| v - entry_size }
        
        # Extract organization ID and update counter
        organization_id = extract_org_id(key)
        if organization_id
          org_count = @org_counters[organization_id]
          org_count&.decrement
        end
        
        # Remove from all tracking maps
        @cache.delete(key)
        @access_times.delete(key)
      end
      
      true
    end
    
    # Delete keys matching a pattern
    # @param pattern [String] The pattern to match (with * as wildcard)
    # @return [Boolean] Whether any keys were deleted
    def delete_pattern(pattern)
      # Convert pattern to regex
      regex_pattern = Regexp.new("^#{pattern.gsub('*', '.*')}$")
      
      # Collect keys to delete
      keys_to_delete = []
      
      # Acquire read lock to collect keys
      @lock.with_read_lock do
        @cache.each_key do |key|
          keys_to_delete << key if key.match?(regex_pattern)
        end
      end
      
      # Return false if no keys match
      return false if keys_to_delete.empty?
      
      # Delete each key
      keys_to_delete.each { |key| delete(key) }
      
      true
    end
    
    # Get organization-specific statistics
    # @param organization_id [Integer] Organization ID
    # @return [Hash] Organization-specific statistics
    def organization_stats(organization_id)
      org_key = organization_id.to_s
      
      # Get organization entry count
      size = (@org_counters[org_key] || Concurrent::AtomicFixnum.new(0)).value
      
      # Default stats
      stats = {
        size: size,
        memory_bytes: 0
      }
      
      # Acquire read lock to calculate memory usage
      @lock.with_read_lock do
        # Only calculate detailed stats if organization has entries
        if size > 0
          # Calculate approximate memory usage
          memory_bytes = 0
          
          # Collect entries for this organization
          @cache.each do |key, value|
            if key.include?("org:#{organization_id}:")
              memory_bytes += estimate_size(key, value)
            end
          end
          
          stats[:memory_bytes] = memory_bytes
        end
      end
      
      stats
    end
    
    # Get overall statistics
    # @return [Hash] Overall statistics
    def stats
      # Acquire read lock for consistent stats
      @lock.with_read_lock do
        {
          size: @cache.size,
          memory_bytes: @memory_usage.value,
          max_entries: @max_entries,
          max_memory: @max_memory,
          organization_count: @org_counters.size,
          organizations: @org_counters.each_pair.map { |org_id, counter| [org_id, counter.value] }.to_h
        }
      end
    end
    
    private
    
    # Evict entries based on LRU policy
    # @param needed_space [Integer] Bytes needed
    # @param preserve_org_id [Integer] Organization ID to preserve
    def evict_entries(needed_space, preserve_org_id = nil)
      # Acquire write lock for eviction
      @lock.with_write_lock do
        # Get current memory usage
        current_usage = @memory_usage.value
        target_usage = (current_usage + needed_space) - (@max_memory * 0.8)
        
        # Sort entries by access time (oldest first)
        sorted_entries = @access_times.each_pair.map { |k, v| [k, v] }.sort_by { |_, v| v }
        
        # Track how much space we've freed
        freed_bytes = 0
        evicted_count = 0
        
        # Evict entries until we have enough space
        sorted_entries.each do |key, _|
          # Skip if this is from the organization we're preserving
          # This helps prevent cache thrashing for a single organization
          if preserve_org_id && key.include?("org:#{preserve_org_id}:")
            next
          end
          
          # Get value and calculate size
          value = @cache[key]
          entry_size = estimate_size(key, value)
          
          # Extract organization ID and update counter
          organization_id = extract_org_id(key)
          
          # Delete the entry
          @cache.delete(key)
          @access_times.delete(key)
          
          # Update organization counter
          if organization_id
            org_count = @org_counters[organization_id.to_s]
            org_count&.decrement
          end
          
          # Update memory tracking
          freed_bytes += entry_size
          evicted_count += 1
          
          # Stop if we've freed enough space
          break if freed_bytes >= target_usage
        end
        
        # Update overall memory usage
        @memory_usage.update { |v| v - freed_bytes }
        
        # Log eviction
        Rails.logger.info "MemoryStore evicted #{evicted_count} entries, freed #{freed_bytes} bytes"
      end
    end
    
    # Extract organization ID from a key
    # @param key [String] The key to extract from
    # @return [String, nil] The organization ID or nil
    def extract_org_id(key)
      # Organization keys are expected to be in format "org:<org_id>:*"
      if key.is_a?(String) && key.start_with?('org:')
        match = key.match(/^org:([^:]+):/)
        match[1] if match
      else
        nil
      end
    end
    
    # Estimate memory size of an entry
    # @param key [String] The key
    # @param value [Object] The value
    # @return [Integer] Approximate size in bytes
    def estimate_size(key, value)
      # Key size
      key_size = key.bytesize
      
      # Value size - approximate for common types
      value_size = case value
                   when String
                     value.bytesize
                   when Array
                     # For embedding vectors (arrays of floats)
                     # Each float is approximately 8 bytes
                     value.size * 8
                   when Hash
                     # Rough approximation for hashes
                     value.sum { |k, v| (k.to_s.bytesize + v.to_s.bytesize) }
                   else
                     # Default approximation for other objects
                     value.to_s.bytesize
                   end
      
      # Add overhead for object structure
      overhead = 64
      
      key_size + value_size + overhead
    end
  end
end
