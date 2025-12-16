# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'concurrent'

module Distributed
  module Search
    # Client for executing queries against remote shards in the cluster
    class RemoteShardClient
      # Configuration
      DEFAULT_PORT = 7200
      CONNECTION_TIMEOUT = 5
      READ_TIMEOUT = 30
      MAX_RETRIES = 3
      RETRY_DELAY = 0.5

      # Connection pool settings
      POOL_SIZE = 10
      POOL_TIMEOUT = 5

      def initialize(node_registry:)
        @node_registry = node_registry  # Maps node_id => { host:, port:, status: }
        @connection_pools = Concurrent::Hash.new
        @circuit_breakers = Concurrent::Hash.new
        @metrics = Concurrent::Hash.new { |h, k| h[k] = { requests: 0, errors: 0, latency_sum: 0 } }
      end

      # Execute a search query on a specific shard
      def search(shard_id, query_vector:, k:, organization_id:, dimension:, options: {})
        node_info = @node_registry[shard_id]
        raise ShardUnavailableError, "Unknown shard: #{shard_id}" unless node_info

        # Check circuit breaker
        if circuit_open?(shard_id)
          raise ShardUnavailableError, "Circuit breaker open for shard: #{shard_id}"
        end

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          response = with_retry(shard_id) do
            execute_search_request(
              node_info,
              query_vector: query_vector,
              k: k,
              organization_id: organization_id,
              dimension: dimension,
              options: options
            )
          end

          record_success(shard_id, start_time)
          response
        rescue => e
          record_failure(shard_id, start_time, e)
          raise
        end
      end

      # Execute a batch search across multiple shards in parallel
      def parallel_search(shards:, query_vector:, k:, organization_id:, dimension:, options: {})
        results = Concurrent::Hash.new
        errors = Concurrent::Hash.new
        latch = Concurrent::CountDownLatch.new(shards.length)

        shards.each do |shard_id|
          Thread.new do
            begin
              results[shard_id] = search(
                shard_id,
                query_vector: query_vector,
                k: k,
                organization_id: organization_id,
                dimension: dimension,
                options: options
              )
            rescue => e
              errors[shard_id] = e
            ensure
              latch.count_down
            end
          end
        end

        # Wait for all requests to complete with timeout
        timeout = options[:timeout] || READ_TIMEOUT
        latch.wait(timeout)

        # Merge and sort results from all shards
        merge_search_results(results, errors, k)
      end

      # Insert a vector into a remote shard
      def insert(shard_id, vector:, document_id:, organization_id:, dimension:, metadata: {})
        node_info = @node_registry[shard_id]
        raise ShardUnavailableError, "Unknown shard: #{shard_id}" unless node_info

        if circuit_open?(shard_id)
          raise ShardUnavailableError, "Circuit breaker open for shard: #{shard_id}"
        end

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          response = with_retry(shard_id) do
            execute_insert_request(
              node_info,
              vector: vector,
              document_id: document_id,
              organization_id: organization_id,
              dimension: dimension,
              metadata: metadata
            )
          end

          record_success(shard_id, start_time)
          response
        rescue => e
          record_failure(shard_id, start_time, e)
          raise
        end
      end

      # Delete a vector from a remote shard
      def delete(shard_id, document_id:, organization_id:)
        node_info = @node_registry[shard_id]
        raise ShardUnavailableError, "Unknown shard: #{shard_id}" unless node_info

        if circuit_open?(shard_id)
          raise ShardUnavailableError, "Circuit breaker open for shard: #{shard_id}"
        end

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          response = with_retry(shard_id) do
            execute_delete_request(node_info, document_id: document_id, organization_id: organization_id)
          end

          record_success(shard_id, start_time)
          response
        rescue => e
          record_failure(shard_id, start_time, e)
          raise
        end
      end

      # Get health status of a shard
      def health_check(shard_id)
        node_info = @node_registry[shard_id]
        return { status: 'unknown', error: 'Unknown shard' } unless node_info

        begin
          uri = build_uri(node_info, '/health')
          response = execute_http_get(uri)

          JSON.parse(response.body).deep_symbolize_keys
        rescue => e
          { status: 'unhealthy', error: e.message }
        end
      end

      # Get metrics for all shards
      def shard_metrics
        @metrics.to_h.transform_values do |m|
          {
            requests: m[:requests],
            errors: m[:errors],
            error_rate: m[:requests] > 0 ? (m[:errors].to_f / m[:requests]).round(4) : 0,
            avg_latency_ms: m[:requests] > 0 ? (m[:latency_sum] / m[:requests]).round(2) : 0
          }
        end
      end

      # Reset circuit breaker for a shard
      def reset_circuit_breaker(shard_id)
        @circuit_breakers.delete(shard_id)
        Rails.logger.info("[RemoteShardClient] Reset circuit breaker for shard: #{shard_id}")
      end

      private

      def execute_search_request(node_info, query_vector:, k:, organization_id:, dimension:, options:)
        uri = build_uri(node_info, '/search')

        payload = {
          query_vector: query_vector,
          k: k,
          organization_id: organization_id,
          dimension: dimension,
          options: options
        }

        response = execute_http_post(uri, payload)

        unless response.is_a?(Net::HTTPSuccess)
          raise RemoteQueryError, "Search failed: #{response.code} - #{response.body}"
        end

        parse_search_response(response.body)
      end

      def execute_insert_request(node_info, vector:, document_id:, organization_id:, dimension:, metadata:)
        uri = build_uri(node_info, '/insert')

        payload = {
          vector: vector,
          document_id: document_id,
          organization_id: organization_id,
          dimension: dimension,
          metadata: metadata
        }

        response = execute_http_post(uri, payload)

        unless response.is_a?(Net::HTTPSuccess)
          raise RemoteQueryError, "Insert failed: #{response.code} - #{response.body}"
        end

        JSON.parse(response.body).deep_symbolize_keys
      end

      def execute_delete_request(node_info, document_id:, organization_id:)
        uri = build_uri(node_info, '/delete')

        payload = {
          document_id: document_id,
          organization_id: organization_id
        }

        response = execute_http_post(uri, payload)

        unless response.is_a?(Net::HTTPSuccess)
          raise RemoteQueryError, "Delete failed: #{response.code} - #{response.body}"
        end

        JSON.parse(response.body).deep_symbolize_keys
      end

      def build_uri(node_info, path)
        port = node_info[:port] || DEFAULT_PORT
        URI("http://#{node_info[:host]}:#{port}/api/v1/shard#{path}")
      end

      def execute_http_post(uri, payload)
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['X-Shard-Request'] = 'true'
        request.body = JSON.generate(payload)

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = CONNECTION_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        http.request(request)
      end

      def execute_http_get(uri)
        request = Net::HTTP::Get.new(uri)
        request['X-Shard-Request'] = 'true'

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = CONNECTION_TIMEOUT
        http.read_timeout = 5

        http.request(request)
      end

      def parse_search_response(body)
        data = JSON.parse(body)

        results = data['results'] || []
        results.map do |r|
          {
            id: r['id'],
            distance: r['distance'].to_f,
            score: r['score']&.to_f || (1.0 / (1.0 + r['distance'].to_f)),
            metadata: r['metadata'] || {}
          }
        end
      end

      def with_retry(shard_id)
        retries = 0

        begin
          yield
        rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
          retries += 1

          if retries <= MAX_RETRIES
            Rails.logger.warn("[RemoteShardClient] Retry #{retries}/#{MAX_RETRIES} for shard #{shard_id}: #{e.message}")
            sleep(RETRY_DELAY * retries)
            retry
          end

          raise ShardUnavailableError, "Failed after #{MAX_RETRIES} retries: #{e.message}"
        end
      end

      def merge_search_results(results, errors, k)
        # Log any errors
        errors.each do |shard_id, error|
          Rails.logger.warn("[RemoteShardClient] Shard #{shard_id} failed: #{error.message}")
        end

        # Collect all results
        all_results = results.values.flatten

        # Sort by distance (ascending) and take top k
        all_results.sort_by { |r| r[:distance] }.take(k)
      end

      # Circuit breaker pattern for failing shards
      def circuit_open?(shard_id)
        breaker = @circuit_breakers[shard_id]
        return false unless breaker

        # Check if enough time has passed to try again
        if breaker[:open] && Time.now > breaker[:retry_after]
          @circuit_breakers[shard_id][:open] = false
          return false
        end

        breaker[:open]
      end

      def record_success(shard_id, start_time)
        latency = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

        @metrics[shard_id][:requests] += 1
        @metrics[shard_id][:latency_sum] += latency

        # Reset circuit breaker on success
        @circuit_breakers[shard_id] = { open: false, failures: 0 } if @circuit_breakers[shard_id]
      end

      def record_failure(shard_id, start_time, error)
        latency = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

        @metrics[shard_id][:requests] += 1
        @metrics[shard_id][:errors] += 1
        @metrics[shard_id][:latency_sum] += latency

        # Update circuit breaker
        breaker = @circuit_breakers[shard_id] ||= { open: false, failures: 0 }
        breaker[:failures] += 1

        # Open circuit after 5 consecutive failures
        if breaker[:failures] >= 5
          breaker[:open] = true
          breaker[:retry_after] = Time.now + 30  # Half-open after 30 seconds

          Rails.logger.warn("[RemoteShardClient] Circuit breaker opened for shard: #{shard_id}")
        end
      end

      # Custom error classes
      class ShardUnavailableError < StandardError; end
      class RemoteQueryError < StandardError; end
    end
  end
end
