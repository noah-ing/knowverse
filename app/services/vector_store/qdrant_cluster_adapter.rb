# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module VectorStore
  # Production-grade Qdrant cluster adapter
  # Leverages Qdrant's native Raft consensus for distributed vector operations
  # https://qdrant.tech/documentation/guides/distributed_deployment/
  class QdrantClusterAdapter
    # Configuration
    DEFAULT_GRPC_PORT = 6334
    DEFAULT_HTTP_PORT = 6333
    REPLICATION_FACTOR = 3
    SHARD_NUMBER_AUTO = 'auto'

    # Collection configuration for hierarchical HNSW
    HNSW_CONFIG = {
      m: 16,                    # Max connections per node
      ef_construct: 200,        # Search scope during construction
      full_scan_threshold: 10_000,  # Switch to full scan below this
      max_indexing_threads: 0,  # Auto-detect CPU cores
      on_disk: true             # Enable disk-backed storage
    }.freeze

    # Optimizers for 100M+ vectors
    OPTIMIZER_CONFIG = {
      deleted_threshold: 0.2,
      vacuum_min_vector_number: 1000,
      default_segment_number: 4,
      max_segment_size: 200_000,
      memmap_threshold: 50_000,
      indexing_threshold: 20_000,
      flush_interval_sec: 5
    }.freeze

    attr_reader :cluster_urls, :current_leader

    def initialize(cluster_urls:, api_key: nil)
      @cluster_urls = Array(cluster_urls)
      @api_key = api_key
      @current_leader = @cluster_urls.first
      @connection_pool = ConnectionPool.new(@cluster_urls)
      @metrics = MetricsCollector.new
    end

    # Create a collection with optimal configuration for scale
    def create_collection(name:, dimension:, distance: :cosine, on_disk: true, replication_factor: REPLICATION_FACTOR)
      payload = {
        vectors: {
          size: dimension,
          distance: distance.to_s.capitalize,
          on_disk: on_disk,
          hnsw_config: HNSW_CONFIG
        },
        shard_number: calculate_shard_number(dimension),
        replication_factor: replication_factor,
        write_consistency_factor: (replication_factor / 2) + 1,  # Majority writes
        optimizers_config: OPTIMIZER_CONFIG,
        wal_config: {
          wal_capacity_mb: 256,
          wal_segments_ahead: 2
        }
      }

      response = http_put("/collections/#{name}", payload)

      if response[:status] == 'ok'
        Rails.logger.info("[Qdrant] Created collection #{name} with #{payload[:shard_number]} shards")
        { success: true, collection: name }
      else
        { success: false, error: response[:error] }
      end
    end

    # Insert vectors with automatic batching for throughput
    def upsert(collection:, points:, wait: true, ordering: :weak)
      # Batch into optimal chunks (Qdrant recommends 64-256 per batch)
      batch_size = 128
      results = []

      points.each_slice(batch_size) do |batch|
        payload = {
          points: batch.map do |point|
            {
              id: point[:id],
              vector: point[:vector],
              payload: point[:payload] || {}
            }
          end
        }

        params = { wait: wait, ordering: ordering }
        response = http_put("/collections/#{collection}/points?#{URI.encode_www_form(params)}", payload)

        results << response
        @metrics.record_upsert(batch.size)
      end

      { success: results.all? { |r| r[:status] == 'ok' }, batches: results.size }
    end

    # Search with automatic shard routing
    def search(collection:, vector:, limit: 10, filter: nil, score_threshold: nil, with_payload: true, with_vectors: false)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      payload = {
        vector: vector,
        limit: limit,
        with_payload: with_payload,
        with_vector: with_vectors
      }

      payload[:filter] = build_filter(filter) if filter
      payload[:score_threshold] = score_threshold if score_threshold

      response = http_post("/collections/#{collection}/points/search", payload)

      duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
      @metrics.record_search(duration)

      if response[:result]
        {
          success: true,
          results: response[:result].map do |r|
            {
              id: r[:id],
              score: r[:score],
              distance: 1.0 - r[:score],  # Convert cosine similarity to distance
              payload: r[:payload]
            }
          end,
          latency_ms: duration
        }
      else
        { success: false, error: response[:error], results: [] }
      end
    end

    # Batch search for multiple queries
    def search_batch(collection:, searches:)
      payload = {
        searches: searches.map do |s|
          {
            vector: s[:vector],
            limit: s[:limit] || 10,
            filter: s[:filter] ? build_filter(s[:filter]) : nil,
            with_payload: true
          }.compact
        end
      }

      response = http_post("/collections/#{collection}/points/search/batch", payload)

      if response[:result]
        {
          success: true,
          results: response[:result].map do |batch_result|
            batch_result.map do |r|
              { id: r['id'], score: r['score'], payload: r['payload'] }
            end
          end
        }
      else
        { success: false, error: response[:error] }
      end
    end

    # Scroll through all points (for export/migration)
    def scroll(collection:, limit: 100, offset: nil, filter: nil, with_payload: true, with_vectors: false)
      payload = {
        limit: limit,
        with_payload: with_payload,
        with_vector: with_vectors
      }

      payload[:offset] = offset if offset
      payload[:filter] = build_filter(filter) if filter

      response = http_post("/collections/#{collection}/points/scroll", payload)

      if response[:result]
        {
          success: true,
          points: response[:result]['points'],
          next_offset: response[:result]['next_page_offset']
        }
      else
        { success: false, error: response[:error] }
      end
    end

    # Delete points by IDs or filter
    def delete(collection:, ids: nil, filter: nil, wait: true)
      payload = if ids
        { points: ids }
      elsif filter
        { filter: build_filter(filter) }
      else
        raise ArgumentError, "Must provide either ids or filter"
      end

      response = http_post("/collections/#{collection}/points/delete?wait=#{wait}", payload)

      { success: response[:status] == 'ok' }
    end

    # Get cluster status
    def cluster_status
      response = http_get("/cluster")

      if response[:result]
        result = response[:result]
        {
          status: result[:status],
          peer_id: result[:peer_id],
          peers: result[:peers],
          raft_info: result[:raft_info],
          consensus_thread_status: result[:consensus_thread_status]
        }
      else
        { status: 'error', error: response[:error] }
      end
    end

    # Get collection info including shard distribution
    def collection_info(collection)
      response = http_get("/collections/#{collection}")

      if response[:result]
        result = response[:result]
        {
          status: result['status'],
          vectors_count: result['vectors_count'],
          points_count: result['points_count'],
          segments_count: result['segments_count'],
          config: result['config'],
          optimizer_status: result['optimizer_status']
        }
      else
        { status: 'error', error: response[:error] }
      end
    end

    # Get shard distribution for a collection
    def shard_info(collection)
      response = http_get("/collections/#{collection}/cluster")

      if response[:result]
        {
          local_shards: response[:result]['local_shards'],
          remote_shards: response[:result]['remote_shards'],
          shard_transfers: response[:result]['shard_transfers']
        }
      else
        { status: 'error', error: response[:error] }
      end
    end

    # Trigger collection optimization
    def optimize(collection)
      response = http_post("/collections/#{collection}/index", {})

      { success: response[:status] == 'ok' }
    end

    # Create snapshot for backup
    def create_snapshot(collection)
      response = http_post("/collections/#{collection}/snapshots", {})

      if response[:result]
        { success: true, snapshot: response[:result] }
      else
        { success: false, error: response[:error] }
      end
    end

    # Get metrics
    def metrics
      @metrics.summary
    end

    private

    def calculate_shard_number(dimension)
      # Optimal shard sizing: ~10M vectors per shard
      # Estimate based on dimension and target capacity
      # For 100M vectors with 768 dimensions, use 10 shards
      base_shards = 6
      dimension_factor = [1, dimension / 512].max

      [base_shards * dimension_factor, 32].min  # Cap at 32 shards
    end

    def build_filter(filter)
      return nil unless filter

      # Check if already in Qdrant format (has must/should/must_not keys)
      if filter.is_a?(Hash)
        qdrant_keys = [:must, :should, :must_not, 'must', 'should', 'must_not']
        if (filter.keys & qdrant_keys).any?
          # Already in Qdrant format, pass through
          return filter
        end

        # Convert simple hash filter to Qdrant filter format
        must_conditions = filter.map do |key, value|
          if value.is_a?(Array)
            { key: key.to_s, match: { any: value } }
          else
            { key: key.to_s, match: { value: value } }
          end
        end

        { must: must_conditions }
      else
        filter  # Assume already in Qdrant format
      end
    end

    def http_get(path)
      execute_request(:get, path)
    end

    def http_post(path, body)
      execute_request(:post, path, body)
    end

    def http_put(path, body)
      execute_request(:put, path, body)
    end

    def execute_request(method, path, body = nil)
      retries = 0
      max_retries = 3

      begin
        conn = @connection_pool.checkout(@current_leader)
        uri = URI("#{@current_leader}#{path}")

        request = case method
        when :get
          Net::HTTP::Get.new(uri)
        when :post
          req = Net::HTTP::Post.new(uri)
          req.body = JSON.generate(body) if body
          req
        when :put
          req = Net::HTTP::Put.new(uri)
          req.body = JSON.generate(body) if body
          req
        end

        request['Content-Type'] = 'application/json'
        request['api-key'] = @api_key if @api_key

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 5
        http.read_timeout = 30

        response = http.request(request)

        case response.code.to_i
        when 200..299
          JSON.parse(response.body, symbolize_names: true)
        when 503
          # Service unavailable - try another node
          try_failover
          raise RetryableError, "Node unavailable"
        else
          { status: 'error', error: "HTTP #{response.code}: #{response.body}" }
        end

      rescue RetryableError, Timeout::Error, Errno::ECONNREFUSED => e
        retries += 1
        if retries <= max_retries
          sleep(0.1 * retries)
          retry
        end
        { status: 'error', error: e.message }
      ensure
        @connection_pool.checkin(conn) if conn
      end
    end

    def try_failover
      # Rotate to next node in cluster
      current_index = @cluster_urls.index(@current_leader) || 0
      @current_leader = @cluster_urls[(current_index + 1) % @cluster_urls.size]

      Rails.logger.warn("[Qdrant] Failover to #{@current_leader}")
    end

    class RetryableError < StandardError; end

    # Simple connection pool
    class ConnectionPool
      def initialize(urls)
        @urls = urls
        @connections = {}
        @lock = Mutex.new
      end

      def checkout(url)
        @lock.synchronize do
          @connections[url] ||= []
        end
        url
      end

      def checkin(url)
        # No-op for HTTP connections
      end
    end

    # Metrics collector for observability
    class MetricsCollector
      def initialize
        @upsert_count = 0
        @search_count = 0
        @search_latencies = []
        @lock = Mutex.new
      end

      def record_upsert(count)
        @lock.synchronize { @upsert_count += count }
      end

      def record_search(latency_ms)
        @lock.synchronize do
          @search_count += 1
          @search_latencies << latency_ms
          @search_latencies.shift if @search_latencies.size > 1000
        end
      end

      def summary
        @lock.synchronize do
          avg_latency = @search_latencies.empty? ? 0 : @search_latencies.sum / @search_latencies.size.to_f

          {
            total_upserts: @upsert_count,
            total_searches: @search_count,
            avg_search_latency_ms: avg_latency.round(2),
            p99_search_latency_ms: percentile(@search_latencies, 99).round(2)
          }
        end
      end

      private

      def percentile(array, p)
        return 0 if array.empty?
        sorted = array.sort
        index = (p / 100.0 * sorted.size).ceil - 1
        sorted[[index, 0].max]
      end
    end
  end
end
