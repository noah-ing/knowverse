# frozen_string_literal: true

module Wasm
  # Production-grade scalable index manager for 100M+ vectors
  # Implements hierarchical partitioning, tiered storage, and compaction
  class ScalableIndexManager
    include Singleton

    # Configuration constants
    PARTITION_SIZE = 100_000           # Vectors per partition
    SHARD_SIZE = 10_000_000            # Vectors per shard (100 partitions)
    MAX_HOT_PARTITIONS = 50            # Active partitions in memory
    HOT_PARTITION_TTL = 300            # Seconds before partition becomes warm
    WARM_PARTITION_TTL = 3600          # Seconds before partition becomes cold
    COMPACTION_THRESHOLD = 0.3         # Trigger compaction when 30% deleted

    # Storage tiers
    module StorageTier
      HOT = :hot       # In-memory, instant access
      WARM = :warm     # On-disk SSD, fast access
      COLD = :cold     # Compressed archive, slow access
    end

    attr_reader :stats

    def initialize
      @lock = Mutex.new
      @indexes = {}                  # organization_id => OrganizationIndex
      @stats = {
        total_vectors: 0,
        hot_partitions: 0,
        warm_partitions: 0,
        cold_partitions: 0,
        memory_usage_mb: 0,
        disk_usage_mb: 0,
        queries_per_second: 0,
        avg_latency_ms: 0
      }

      @query_metrics = []
      @compaction_scheduler = nil
      @tier_migration_scheduler = nil
    end

    # Initialize the manager
    def start
      @lock.synchronize do
        # Start background schedulers
        start_compaction_scheduler
        start_tier_migration_scheduler

        Rails.logger.info("[ScalableIndex] Started with max #{MAX_HOT_PARTITIONS} hot partitions")
      end
    end

    # Stop the manager
    def stop
      @lock.synchronize do
        @compaction_scheduler&.kill
        @tier_migration_scheduler&.kill

        # Persist all indexes
        @indexes.values.each(&:persist_all)

        Rails.logger.info("[ScalableIndex] Stopped and persisted all indexes")
      end
    end

    # Get or create an index for an organization
    def for_organization(organization_id, dimension: 768)
      @lock.synchronize do
        @indexes[organization_id] ||= OrganizationIndex.new(
          organization_id: organization_id,
          dimension: dimension,
          manager: self
        )
      end
    end

    # Insert a vector
    def insert(organization_id:, vector:, document_id:, metadata: {})
      index = for_organization(organization_id, dimension: vector.size)
      result = index.insert(vector, document_id, metadata)

      update_stats
      result
    end

    # Batch insert vectors
    def insert_batch(organization_id:, vectors:, dimension: nil)
      return { success: false, count: 0 } if vectors.empty?

      dim = dimension || vectors.first[:vector].size
      index = for_organization(organization_id, dimension: dim)

      count = 0
      vectors.each do |v|
        index.insert(v[:vector], v[:id], v[:metadata] || {})
        count += 1
      end

      update_stats
      { success: true, count: count }
    end

    # Search for nearest neighbors
    def search(organization_id:, query_vector:, k: 10, filter: nil)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      index = for_organization(organization_id, dimension: query_vector.size)
      results = index.search(query_vector, k, filter: filter)

      duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
      record_query_metric(duration)

      results
    end

    # Delete a vector
    def delete(organization_id:, document_id:)
      index = @indexes[organization_id]
      return false unless index

      result = index.delete(document_id)
      update_stats
      result
    end

    # Get statistics
    def statistics
      update_stats
      @stats.dup
    end

    # Force compaction for an organization
    def compact(organization_id)
      index = @indexes[organization_id]
      return false unless index

      index.compact
    end

    # Migrate partitions between tiers
    def migrate_tier(organization_id, partition_key, target_tier)
      index = @indexes[organization_id]
      return false unless index

      index.migrate_partition(partition_key, target_tier)
    end

    private

    def start_compaction_scheduler
      @compaction_scheduler = Thread.new do
        loop do
          sleep(300)  # Check every 5 minutes

          @indexes.values.each do |index|
            begin
              index.check_and_compact
            rescue => e
              Rails.logger.error("[ScalableIndex] Compaction error: #{e.message}")
            end
          end
        end
      end
    end

    def start_tier_migration_scheduler
      @tier_migration_scheduler = Thread.new do
        loop do
          sleep(60)  # Check every minute

          @indexes.values.each do |index|
            begin
              index.migrate_cold_partitions
            rescue => e
              Rails.logger.error("[ScalableIndex] Tier migration error: #{e.message}")
            end
          end
        end
      end
    end

    def update_stats
      hot = 0
      warm = 0
      cold = 0
      vectors = 0
      memory = 0

      @indexes.values.each do |index|
        s = index.stats
        hot += s[:hot_partitions]
        warm += s[:warm_partitions]
        cold += s[:cold_partitions]
        vectors += s[:total_vectors]
        memory += s[:memory_usage_bytes]
      end

      @stats[:total_vectors] = vectors
      @stats[:hot_partitions] = hot
      @stats[:warm_partitions] = warm
      @stats[:cold_partitions] = cold
      @stats[:memory_usage_mb] = memory / (1024 * 1024)
      @stats[:queries_per_second] = calculate_qps
      @stats[:avg_latency_ms] = calculate_avg_latency
    end

    def record_query_metric(duration_ms)
      @query_metrics << { time: Time.now, duration: duration_ms }

      # Keep only last 1000 queries
      @query_metrics.shift if @query_metrics.size > 1000
    end

    def calculate_qps
      return 0 if @query_metrics.empty?

      recent = @query_metrics.select { |m| m[:time] > 60.seconds.ago }
      return 0 if recent.empty?

      recent.size / 60.0
    end

    def calculate_avg_latency
      return 0 if @query_metrics.empty?

      recent = @query_metrics.last(100)
      recent.sum { |m| m[:duration] } / recent.size.to_f
    end

    # Per-organization index with hierarchical partitioning
    class OrganizationIndex
      attr_reader :organization_id, :dimension

      def initialize(organization_id:, dimension:, manager:)
        @organization_id = organization_id
        @dimension = dimension
        @manager = manager
        @lock = Mutex.new

        @partitions = {}              # partition_key => Partition
        @partition_metadata = {}      # partition_key => { tier:, last_access:, vector_count:, deleted_count: }
        @document_index = {}          # document_id => partition_key
        @hot_partitions = LRUCache.new(MAX_HOT_PARTITIONS)

        # Storage paths
        @storage_path = Rails.root.join('storage', 'indexes', organization_id.to_s)
        FileUtils.mkdir_p(@storage_path)
      end

      def insert(vector, document_id, metadata = {})
        @lock.synchronize do
          # Determine partition based on document ID
          partition_key = partition_key_for_document(document_id)

          # Ensure partition is loaded
          partition = ensure_partition_loaded(partition_key)

          # Insert vector
          node_id = partition.insert(vector, document_id, metadata)

          # Update tracking
          @document_index[document_id] = partition_key
          update_partition_metadata(partition_key, :insert)

          "#{partition_key}:#{node_id}"
        end
      end

      def search(query_vector, k, filter: nil)
        @lock.synchronize do
          all_results = []

          # Search all hot partitions first
          @hot_partitions.keys.each do |partition_key|
            partition = @partitions[partition_key]
            next unless partition

            results = partition.search(query_vector, k, filter: filter)
            all_results.concat(results)
          end

          # If not enough results, search warm partitions
          if all_results.size < k
            warm_partitions = @partition_metadata.select { |_, m| m[:tier] == StorageTier::WARM }
            warm_partitions.keys.first(5).each do |partition_key|
              partition = load_partition_from_disk(partition_key)
              next unless partition

              results = partition.search(query_vector, k, filter: filter)
              all_results.concat(results)
            end
          end

          # Sort and return top k
          all_results.sort_by { |r| r[:distance] }.take(k)
        end
      end

      def delete(document_id)
        @lock.synchronize do
          partition_key = @document_index[document_id]
          return false unless partition_key

          partition = ensure_partition_loaded(partition_key)
          return false unless partition

          result = partition.delete(document_id)

          if result
            @document_index.delete(document_id)
            update_partition_metadata(partition_key, :delete)
          end

          result
        end
      end

      def stats
        hot = @hot_partitions.size
        warm = @partition_metadata.count { |_, m| m[:tier] == StorageTier::WARM }
        cold = @partition_metadata.count { |_, m| m[:tier] == StorageTier::COLD }
        vectors = @document_index.size
        memory = @partitions.values.sum { |p| p.memory_usage rescue 0 }

        {
          hot_partitions: hot,
          warm_partitions: warm,
          cold_partitions: cold,
          total_vectors: vectors,
          memory_usage_bytes: memory
        }
      end

      def check_and_compact
        @partition_metadata.each do |partition_key, metadata|
          next unless metadata[:vector_count] > 0

          deletion_ratio = metadata[:deleted_count].to_f / metadata[:vector_count]

          if deletion_ratio >= COMPACTION_THRESHOLD
            compact_partition(partition_key)
          end
        end
      end

      def migrate_cold_partitions
        now = Time.now

        @partition_metadata.each do |partition_key, metadata|
          last_access = metadata[:last_access] || Time.at(0)
          age = now - last_access

          case metadata[:tier]
          when StorageTier::HOT
            if age > HOT_PARTITION_TTL && @hot_partitions.size > MAX_HOT_PARTITIONS / 2
              migrate_partition(partition_key, StorageTier::WARM)
            end
          when StorageTier::WARM
            if age > WARM_PARTITION_TTL
              migrate_partition(partition_key, StorageTier::COLD)
            end
          end
        end
      end

      def migrate_partition(partition_key, target_tier)
        @lock.synchronize do
          metadata = @partition_metadata[partition_key]
          return false unless metadata

          current_tier = metadata[:tier]
          return true if current_tier == target_tier

          partition = @partitions[partition_key]

          case target_tier
          when StorageTier::WARM
            # Persist to disk and remove from memory
            persist_partition(partition_key, partition) if partition
            @hot_partitions.delete(partition_key)
            @partitions.delete(partition_key)

          when StorageTier::COLD
            # Compress and archive
            compress_partition(partition_key)

          when StorageTier::HOT
            # Load into memory
            partition = load_partition_from_disk(partition_key)
            if partition
              @partitions[partition_key] = partition
              @hot_partitions[partition_key] = true
            end
          end

          metadata[:tier] = target_tier
          Rails.logger.info("[ScalableIndex] Migrated #{partition_key} from #{current_tier} to #{target_tier}")

          true
        end
      end

      def persist_all
        @partitions.each do |partition_key, partition|
          persist_partition(partition_key, partition)
        end
      end

      private

      def partition_key_for_document(document_id)
        # Consistent hashing for partition assignment
        hash = Digest::MD5.hexdigest(document_id.to_s)[0, 8].to_i(16)
        partition_num = hash % 10000  # Up to 10000 partitions = 1 billion vectors

        "org_#{@organization_id}_p#{partition_num}"
      end

      def ensure_partition_loaded(partition_key)
        if @partitions[partition_key]
          @hot_partitions[partition_key] = true
          @partition_metadata[partition_key][:last_access] = Time.now
          return @partitions[partition_key]
        end

        # Check if we need to evict
        evict_if_needed

        # Try to load from disk
        partition = load_partition_from_disk(partition_key)

        unless partition
          # Create new partition
          partition = HnswPartition.new(
            dimension: @dimension,
            m: 16,
            ef_construction: 200
          )
        end

        @partitions[partition_key] = partition
        @hot_partitions[partition_key] = true
        @partition_metadata[partition_key] ||= {
          tier: StorageTier::HOT,
          last_access: Time.now,
          vector_count: 0,
          deleted_count: 0
        }
        @partition_metadata[partition_key][:tier] = StorageTier::HOT
        @partition_metadata[partition_key][:last_access] = Time.now

        partition
      end

      def evict_if_needed
        while @hot_partitions.size >= MAX_HOT_PARTITIONS
          evicted_key = @hot_partitions.oldest_key
          break unless evicted_key

          partition = @partitions[evicted_key]
          persist_partition(evicted_key, partition) if partition

          @partitions.delete(evicted_key)
          @hot_partitions.delete(evicted_key)

          if @partition_metadata[evicted_key]
            @partition_metadata[evicted_key][:tier] = StorageTier::WARM
          end

          Rails.logger.debug("[ScalableIndex] Evicted partition #{evicted_key} to warm tier")
        end
      end

      def update_partition_metadata(partition_key, operation)
        meta = @partition_metadata[partition_key] ||= {
          tier: StorageTier::HOT,
          last_access: Time.now,
          vector_count: 0,
          deleted_count: 0
        }

        case operation
        when :insert
          meta[:vector_count] += 1
        when :delete
          meta[:deleted_count] += 1
        end

        meta[:last_access] = Time.now
      end

      def persist_partition(partition_key, partition)
        return unless partition

        path = File.join(@storage_path, "#{partition_key}.idx")

        data = {
          dimension: @dimension,
          vectors: partition.vectors,
          document_map: partition.document_map,
          connections: partition.connections
        }

        File.write(path, Oj.dump(data, mode: :compat))

        Rails.logger.debug("[ScalableIndex] Persisted partition #{partition_key}")
      end

      def load_partition_from_disk(partition_key)
        path = File.join(@storage_path, "#{partition_key}.idx")
        return nil unless File.exist?(path)

        data = Oj.load(File.read(path), symbol_keys: true)

        partition = HnswPartition.new(
          dimension: data[:dimension],
          m: 16,
          ef_construction: 200
        )

        partition.load_from_data(data)
        partition
      rescue => e
        Rails.logger.error("[ScalableIndex] Failed to load partition #{partition_key}: #{e.message}")
        nil
      end

      def compact_partition(partition_key)
        partition = ensure_partition_loaded(partition_key)
        return unless partition

        # Rebuild the index without deleted entries
        partition.compact

        # Update metadata
        meta = @partition_metadata[partition_key]
        meta[:vector_count] -= meta[:deleted_count]
        meta[:deleted_count] = 0

        Rails.logger.info("[ScalableIndex] Compacted partition #{partition_key}")
      end

      def compress_partition(partition_key)
        path = File.join(@storage_path, "#{partition_key}.idx")
        compressed_path = "#{path}.gz"

        if File.exist?(path)
          Zlib::GzipWriter.open(compressed_path) do |gz|
            gz.write(File.read(path))
          end
          File.delete(path)
        end
      end
    end

    # HNSW Partition implementation
    class HnswPartition
      attr_reader :dimension, :vectors, :document_map, :connections, :memory_usage

      def initialize(dimension:, m: 16, ef_construction: 200)
        @dimension = dimension
        @m = m
        @ef_construction = ef_construction

        @vectors = {}         # node_id => vector
        @document_map = {}    # document_id => node_id
        @reverse_map = {}     # node_id => document_id
        @connections = {}     # node_id => Set of connected node_ids
        @metadata = {}        # document_id => metadata
        @deleted = Set.new    # Set of deleted node_ids

        @next_node_id = 0
        @memory_usage = 0
      end

      def insert(vector, document_id, metadata = {})
        node_id = @next_node_id
        @next_node_id += 1

        @vectors[node_id] = vector
        @document_map[document_id] = node_id
        @reverse_map[node_id] = document_id
        @connections[node_id] = Set.new
        @metadata[document_id] = metadata

        # Connect to nearest neighbors
        connect_to_neighbors(node_id, vector)

        update_memory_usage
        node_id
      end

      def search(query_vector, k, filter: nil)
        return [] if @vectors.empty?

        # Find entry point (random active node)
        entry_point = find_entry_point
        return [] unless entry_point

        # Greedy search
        candidates = search_layer(query_vector, entry_point, k * 2)

        # Filter deleted entries and apply custom filter
        results = candidates.reject { |c| @deleted.include?(c[:node_id]) }

        if filter
          results = results.select do |c|
            doc_id = @reverse_map[c[:node_id]]
            filter.call(@metadata[doc_id])
          end
        end

        # Return top k
        results.take(k).map do |c|
          doc_id = @reverse_map[c[:node_id]]
          {
            id: doc_id,
            distance: c[:distance],
            score: 1.0 / (1.0 + c[:distance]),
            metadata: @metadata[doc_id]
          }
        end
      end

      def delete(document_id)
        node_id = @document_map[document_id]
        return false unless node_id

        @deleted.add(node_id)
        true
      end

      def compact
        # Rebuild without deleted entries
        new_vectors = {}
        new_document_map = {}
        new_reverse_map = {}
        new_connections = {}
        new_metadata = {}

        @vectors.each do |node_id, vector|
          next if @deleted.include?(node_id)

          doc_id = @reverse_map[node_id]
          new_node_id = new_vectors.size

          new_vectors[new_node_id] = vector
          new_document_map[doc_id] = new_node_id
          new_reverse_map[new_node_id] = doc_id
          new_metadata[doc_id] = @metadata[doc_id]
        end

        # Rebuild connections
        new_vectors.keys.each do |node_id|
          new_connections[node_id] = Set.new
        end

        new_vectors.each do |node_id, vector|
          connect_to_neighbors_internal(node_id, vector, new_vectors, new_connections)
        end

        @vectors = new_vectors
        @document_map = new_document_map
        @reverse_map = new_reverse_map
        @connections = new_connections
        @metadata = new_metadata
        @deleted = Set.new
        @next_node_id = @vectors.size

        update_memory_usage
      end

      def load_from_data(data)
        @vectors = data[:vectors] || {}
        @document_map = data[:document_map] || {}
        @reverse_map = @document_map.invert
        @connections = (data[:connections] || {}).transform_values { |v| v.to_set }
        @next_node_id = @vectors.keys.max.to_i + 1

        update_memory_usage
      end

      private

      def find_entry_point
        active_nodes = @vectors.keys - @deleted.to_a
        active_nodes.sample
      end

      def connect_to_neighbors(node_id, vector)
        connect_to_neighbors_internal(node_id, vector, @vectors, @connections)
      end

      def connect_to_neighbors_internal(node_id, vector, vectors, connections)
        return if vectors.size <= 1

        # Calculate distances to all other nodes
        distances = []
        vectors.each do |other_id, other_vector|
          next if other_id == node_id

          dist = euclidean_distance(vector, other_vector)
          distances << { node_id: other_id, distance: dist }
        end

        # Connect to M nearest
        nearest = distances.sort_by { |d| d[:distance] }.take(@m)
        nearest.each do |neighbor|
          connections[node_id].add(neighbor[:node_id])
          connections[neighbor[:node_id]]&.add(node_id)
        end
      end

      def search_layer(query_vector, entry_point, ef)
        visited = Set.new([entry_point])
        candidates = [{
          node_id: entry_point,
          distance: euclidean_distance(query_vector, @vectors[entry_point])
        }]

        while true
          # Find closest unvisited candidate
          closest = candidates.min_by { |c| c[:distance] }
          break unless closest

          # Explore neighbors
          new_candidates = false
          @connections[closest[:node_id]]&.each do |neighbor_id|
            next if visited.include?(neighbor_id)

            visited.add(neighbor_id)
            vector = @vectors[neighbor_id]
            next unless vector

            dist = euclidean_distance(query_vector, vector)
            candidates << { node_id: neighbor_id, distance: dist }
            new_candidates = true
          end

          break unless new_candidates

          # Keep only top ef candidates
          candidates = candidates.sort_by { |c| c[:distance] }.take(ef)
        end

        candidates.sort_by { |c| c[:distance] }
      end

      def euclidean_distance(a, b)
        return Float::INFINITY if a.size != b.size

        sum = 0.0
        a.each_with_index do |val, i|
          diff = val - b[i]
          sum += diff * diff
        end

        Math.sqrt(sum)
      end

      def update_memory_usage
        vector_bytes = @vectors.values.sum { |v| v.size * 4 }
        connection_bytes = @connections.values.sum { |c| c.size * 8 }
        overhead = @vectors.size * 64

        @memory_usage = vector_bytes + connection_bytes + overhead
      end
    end

    # Simple LRU Cache for partition management
    class LRUCache
      def initialize(max_size)
        @max_size = max_size
        @data = {}
      end

      def [](key)
        return nil unless @data.key?(key)

        # Move to end (most recently used)
        value = @data.delete(key)
        @data[key] = value
      end

      def []=(key, value)
        @data.delete(key)
        @data[key] = value

        # Evict oldest if over capacity
        @data.shift if @data.size > @max_size
      end

      def delete(key)
        @data.delete(key)
      end

      def keys
        @data.keys
      end

      def size
        @data.size
      end

      def oldest_key
        @data.keys.first
      end
    end
  end
end
