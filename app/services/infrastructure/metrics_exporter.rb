# frozen_string_literal: true

require 'concurrent'

module Infrastructure
  # Prometheus-compatible metrics exporter with distributed tracing support
  # Provides observability for vector search, document processing, and distributed consensus
  class MetricsExporter
    include Singleton

    # Metric types
    COUNTER = :counter
    GAUGE = :gauge
    HISTOGRAM = :histogram
    SUMMARY = :summary

    # Default histogram buckets for latency measurements
    LATENCY_BUCKETS = [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10].freeze
    SIZE_BUCKETS = [100, 1000, 10_000, 100_000, 1_000_000, 10_000_000].freeze

    def initialize
      @metrics = Concurrent::Hash.new
      @lock = Mutex.new

      # Register default metrics
      register_default_metrics
    end

    # Register a new metric
    def register(name, type:, help:, labels: [], buckets: nil)
      @lock.synchronize do
        @metrics[name] = {
          type: type,
          help: help,
          labels: labels,
          buckets: buckets || (type == HISTOGRAM ? LATENCY_BUCKETS : nil),
          values: Concurrent::Hash.new { |h, k| h[k] = default_value(type, buckets) }
        }
      end
    end

    # Increment a counter
    def increment(name, labels: {}, by: 1)
      metric = @metrics[name]
      return unless metric && metric[:type] == COUNTER

      key = label_key(labels)
      metric[:values][key] += by
    end

    # Set a gauge value
    def set(name, value, labels: {})
      metric = @metrics[name]
      return unless metric && metric[:type] == GAUGE

      key = label_key(labels)
      metric[:values][key] = value
    end

    # Increment a gauge
    def gauge_inc(name, labels: {}, by: 1)
      metric = @metrics[name]
      return unless metric && metric[:type] == GAUGE

      key = label_key(labels)
      metric[:values][key] += by
    end

    # Decrement a gauge
    def gauge_dec(name, labels: {}, by: 1)
      gauge_inc(name, labels: labels, by: -by)
    end

    # Observe a value for histogram
    def observe(name, value, labels: {})
      metric = @metrics[name]
      return unless metric && metric[:type] == HISTOGRAM

      key = label_key(labels)
      histogram = metric[:values][key]

      histogram[:sum] += value
      histogram[:count] += 1

      # Update bucket counts
      metric[:buckets].each do |bucket|
        histogram[:buckets][bucket] += 1 if value <= bucket
      end
    end

    # Time a block and record as histogram observation
    def time(name, labels: {})
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      observe(name, duration, labels: labels)
      result
    end

    # Export all metrics in Prometheus format
    def export
      output = StringIO.new

      @metrics.each do |name, metric|
        output.puts "# HELP #{name} #{metric[:help]}"
        output.puts "# TYPE #{name} #{prometheus_type(metric[:type])}"

        case metric[:type]
        when COUNTER, GAUGE
          export_simple_metric(output, name, metric)
        when HISTOGRAM
          export_histogram(output, name, metric)
        end

        output.puts
      end

      output.string
    end

    # Get a specific metric value
    def get(name, labels: {})
      metric = @metrics[name]
      return nil unless metric

      key = label_key(labels)
      metric[:values][key]
    end

    # Record a distributed trace span
    def trace(operation, labels: {})
      trace_id = Thread.current[:trace_id] || SecureRandom.hex(16)
      span_id = SecureRandom.hex(8)
      parent_id = Thread.current[:span_id]

      Thread.current[:trace_id] = trace_id
      Thread.current[:span_id] = span_id

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        result = yield
        status = 'ok'
        result
      rescue => e
        status = 'error'
        raise
      ensure
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        # Record span
        record_span(
          trace_id: trace_id,
          span_id: span_id,
          parent_id: parent_id,
          operation: operation,
          duration: duration,
          status: status,
          labels: labels
        )

        Thread.current[:span_id] = parent_id
      end
    end

    private

    def register_default_metrics
      # Request metrics
      register('knowverse_http_requests_total', type: COUNTER,
        help: 'Total HTTP requests', labels: [:method, :path, :status])

      register('knowverse_http_request_duration_seconds', type: HISTOGRAM,
        help: 'HTTP request duration', labels: [:method, :path])

      # Search metrics
      register('knowverse_search_requests_total', type: COUNTER,
        help: 'Total search requests', labels: [:provider, :organization])

      register('knowverse_search_duration_seconds', type: HISTOGRAM,
        help: 'Search request duration', labels: [:provider])

      register('knowverse_search_results_count', type: HISTOGRAM,
        help: 'Number of search results returned', labels: [:provider], buckets: [0, 1, 5, 10, 20, 50, 100])

      # Vector operations
      register('knowverse_vectors_inserted_total', type: COUNTER,
        help: 'Total vectors inserted', labels: [:organization])

      register('knowverse_vectors_total', type: GAUGE,
        help: 'Total vectors in index', labels: [:organization, :shard])

      register('knowverse_vector_insert_duration_seconds', type: HISTOGRAM,
        help: 'Vector insert duration', labels: [:batch_size])

      # Document processing
      register('knowverse_documents_processed_total', type: COUNTER,
        help: 'Total documents processed', labels: [:type, :status])

      register('knowverse_document_processing_duration_seconds', type: HISTOGRAM,
        help: 'Document processing duration', labels: [:type])

      register('knowverse_document_size_bytes', type: HISTOGRAM,
        help: 'Document size in bytes', labels: [:type], buckets: SIZE_BUCKETS)

      # Raft consensus
      register('knowverse_raft_term', type: GAUGE,
        help: 'Current Raft term', labels: [:node])

      register('knowverse_raft_state', type: GAUGE,
        help: 'Raft node state (0=follower, 1=candidate, 2=leader)', labels: [:node])

      register('knowverse_raft_log_entries', type: GAUGE,
        help: 'Number of log entries', labels: [:node])

      register('knowverse_raft_commit_index', type: GAUGE,
        help: 'Current commit index', labels: [:node])

      register('knowverse_raft_elections_total', type: COUNTER,
        help: 'Total leader elections', labels: [:node, :result])

      register('knowverse_raft_rpc_duration_seconds', type: HISTOGRAM,
        help: 'Raft RPC duration', labels: [:rpc_type, :peer])

      # Cluster health
      register('knowverse_cluster_nodes_total', type: GAUGE,
        help: 'Total nodes in cluster', labels: [:status])

      register('knowverse_cluster_shards_total', type: GAUGE,
        help: 'Total shards', labels: [:tier])

      # Rate limiting
      register('knowverse_rate_limit_requests_total', type: COUNTER,
        help: 'Rate limited requests', labels: [:key, :result])

      register('knowverse_concurrent_requests', type: GAUGE,
        help: 'Current concurrent requests')

      register('knowverse_backpressure_active', type: GAUGE,
        help: 'Backpressure mode active (1=yes, 0=no)')

      # Resource usage
      register('knowverse_memory_usage_bytes', type: GAUGE,
        help: 'Memory usage', labels: [:component])

      register('knowverse_index_memory_bytes', type: GAUGE,
        help: 'Index memory usage', labels: [:organization, :tier])

      # Embedding generation
      register('knowverse_embeddings_generated_total', type: COUNTER,
        help: 'Total embeddings generated', labels: [:model])

      register('knowverse_embedding_duration_seconds', type: HISTOGRAM,
        help: 'Embedding generation duration', labels: [:model, :batch_size])

      # Cache metrics
      register('knowverse_cache_hits_total', type: COUNTER,
        help: 'Cache hits', labels: [:cache_type])

      register('knowverse_cache_misses_total', type: COUNTER,
        help: 'Cache misses', labels: [:cache_type])
    end

    def default_value(type, buckets)
      case type
      when COUNTER
        0
      when GAUGE
        0
      when HISTOGRAM
        {
          sum: 0.0,
          count: 0,
          buckets: (buckets || LATENCY_BUCKETS).map { |b| [b, 0] }.to_h
        }
      end
    end

    def label_key(labels)
      labels.sort.map { |k, v| "#{k}=#{v}" }.join(',')
    end

    def prometheus_type(type)
      case type
      when COUNTER then 'counter'
      when GAUGE then 'gauge'
      when HISTOGRAM then 'histogram'
      when SUMMARY then 'summary'
      end
    end

    def export_simple_metric(output, name, metric)
      metric[:values].each do |labels_str, value|
        label_part = labels_str.empty? ? '' : "{#{labels_str}}"
        output.puts "#{name}#{label_part} #{value}"
      end
    end

    def export_histogram(output, name, metric)
      metric[:values].each do |labels_str, histogram|
        base_labels = labels_str.empty? ? '' : "#{labels_str},"

        # Export bucket counts
        histogram[:buckets].each do |le, count|
          output.puts "#{name}_bucket{#{base_labels}le=\"#{le}\"} #{count}"
        end
        output.puts "#{name}_bucket{#{base_labels}le=\"+Inf\"} #{histogram[:count]}"

        # Export sum and count
        sum_labels = labels_str.empty? ? '' : "{#{labels_str}}"
        output.puts "#{name}_sum#{sum_labels} #{histogram[:sum]}"
        output.puts "#{name}_count#{sum_labels} #{histogram[:count]}"
      end
    end

    def record_span(trace_id:, span_id:, parent_id:, operation:, duration:, status:, labels:)
      # In production, this would send to Jaeger/Zipkin/OTLP
      # For now, just log if trace logging is enabled
      if Rails.logger.level <= Logger::DEBUG
        Rails.logger.debug(
          "[TRACE] #{operation} trace=#{trace_id} span=#{span_id} " \
          "parent=#{parent_id || 'root'} duration=#{(duration * 1000).round(2)}ms status=#{status}"
        )
      end
    end
  end

  # Rack middleware for automatic request metrics
  class MetricsMiddleware
    def initialize(app)
      @app = app
      @metrics = MetricsExporter.instance
    end

    def call(env)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      status, headers, response = @app.call(env)

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      path = normalize_path(env['PATH_INFO'])

      @metrics.increment('knowverse_http_requests_total',
        labels: { method: env['REQUEST_METHOD'], path: path, status: status })

      @metrics.observe('knowverse_http_request_duration_seconds',
        duration, labels: { method: env['REQUEST_METHOD'], path: path })

      [status, headers, response]
    end

    private

    def normalize_path(path)
      # Normalize paths to avoid cardinality explosion
      path
        .gsub(/\/\d+/, '/:id')
        .gsub(/\/[a-f0-9-]{36}/, '/:uuid')
        .gsub(/\?.+/, '')
    end
  end

  # Controller for exposing metrics endpoint
  class MetricsController < ActionController::API
    def index
      render plain: MetricsExporter.instance.export, content_type: 'text/plain; charset=utf-8'
    end
  end
end
