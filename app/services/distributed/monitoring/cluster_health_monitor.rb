# frozen_string_literal: true

require 'concurrent'

module Distributed
  module Monitoring
    # Monitors cluster health, node status, and triggers alerts
    class ClusterHealthMonitor
      include Singleton

      # Health check intervals (seconds)
      HEARTBEAT_INTERVAL = 5
      HEALTH_CHECK_INTERVAL = 15
      METRIC_COLLECTION_INTERVAL = 30
      STALE_THRESHOLD = 30

      # Health status constants
      module Status
        HEALTHY = 'healthy'
        DEGRADED = 'degraded'
        UNHEALTHY = 'unhealthy'
        UNKNOWN = 'unknown'
      end

      attr_reader :cluster_status, :node_statuses, :alerts

      def initialize
        @lock = Mutex.new
        @running = false
        @cluster_status = Status::UNKNOWN
        @node_statuses = Concurrent::Hash.new
        @node_metrics = Concurrent::Hash.new
        @alerts = Concurrent::Array.new
        @alert_handlers = []
        @health_check_timer = nil
        @metric_collection_timer = nil

        # Thresholds for health assessment
        @thresholds = {
          cpu_warning: 70,
          cpu_critical: 90,
          memory_warning: 80,
          memory_critical: 95,
          disk_warning: 75,
          disk_critical: 90,
          latency_warning: 100,  # ms
          latency_critical: 500,  # ms
          error_rate_warning: 0.01,
          error_rate_critical: 0.05
        }
      end

      # Start health monitoring
      def start
        return if @running

        @lock.synchronize do
          return if @running
          @running = true

          # Start health check timer
          start_health_check_timer

          # Start metric collection timer
          start_metric_collection_timer

          Rails.logger.info("[ClusterHealth] Started monitoring")
        end
      end

      # Stop health monitoring
      def stop
        return unless @running

        @lock.synchronize do
          @running = false

          @health_check_timer&.kill
          @metric_collection_timer&.kill

          Rails.logger.info("[ClusterHealth] Stopped monitoring")
        end
      end

      # Register an alert handler
      def on_alert(&handler)
        @alert_handlers << handler if block_given?
      end

      # Get current cluster health summary
      def health_summary
        @lock.synchronize do
          {
            cluster_status: @cluster_status,
            nodes: @node_statuses.to_h,
            total_nodes: @node_statuses.size,
            healthy_nodes: @node_statuses.count { |_, s| s[:status] == Status::HEALTHY },
            degraded_nodes: @node_statuses.count { |_, s| s[:status] == Status::DEGRADED },
            unhealthy_nodes: @node_statuses.count { |_, s| s[:status] == Status::UNHEALTHY },
            active_alerts: @alerts.select { |a| !a[:resolved] }.size,
            last_check: @last_health_check,
            metrics: aggregate_metrics
          }
        end
      end

      # Get detailed status for a specific node
      def node_status(node_id)
        @node_statuses[node_id]
      end

      # Get recent alerts
      def recent_alerts(limit: 50)
        @alerts.last(limit).reverse
      end

      # Acknowledge an alert
      def acknowledge_alert(alert_id, acknowledged_by:)
        alert = @alerts.find { |a| a[:id] == alert_id }
        return false unless alert

        alert[:acknowledged] = true
        alert[:acknowledged_by] = acknowledged_by
        alert[:acknowledged_at] = Time.now

        Rails.logger.info("[ClusterHealth] Alert #{alert_id} acknowledged by #{acknowledged_by}")
        true
      end

      # Resolve an alert
      def resolve_alert(alert_id, resolution_note:)
        alert = @alerts.find { |a| a[:id] == alert_id }
        return false unless alert

        alert[:resolved] = true
        alert[:resolution_note] = resolution_note
        alert[:resolved_at] = Time.now

        Rails.logger.info("[ClusterHealth] Alert #{alert_id} resolved: #{resolution_note}")
        true
      end

      # Force a health check
      def check_health_now
        perform_health_check
      end

      # Update thresholds
      def set_threshold(metric, value)
        if @thresholds.key?(metric.to_sym)
          @thresholds[metric.to_sym] = value
          Rails.logger.info("[ClusterHealth] Updated threshold #{metric} to #{value}")
        end
      end

      private

      def start_health_check_timer
        @health_check_timer = Thread.new do
          while @running
            perform_health_check
            sleep(HEALTH_CHECK_INTERVAL)
          end
        end
      end

      def start_metric_collection_timer
        @metric_collection_timer = Thread.new do
          while @running
            collect_metrics
            sleep(METRIC_COLLECTION_INTERVAL)
          end
        end
      end

      def perform_health_check
        Rails.logger.debug("[ClusterHealth] Performing health check")

        # Get list of nodes from configuration
        config = Distributed::Config::ConfigurationAdapter.instance.get_configuration
        nodes = config[:nodes] || []

        # Check each node
        nodes.each do |node_id|
          check_node_health(node_id)
        end

        # Update overall cluster status
        update_cluster_status

        @last_health_check = Time.now
      end

      def check_node_health(node_id)
        begin
          # Get node info from shard manager
          shard_manager = Distributed::Sharding::ShardingManager.instance
          node_info = get_node_info(node_id)

          # If local node, get local metrics
          if node_id == local_node_id
            update_local_node_status(node_id)
          else
            # For remote nodes, make HTTP health check
            update_remote_node_status(node_id, node_info)
          end
        rescue => e
          Rails.logger.warn("[ClusterHealth] Health check failed for #{node_id}: #{e.message}")

          @node_statuses[node_id] = {
            status: Status::UNHEALTHY,
            error: e.message,
            last_check: Time.now
          }

          check_and_create_alert(node_id, :node_unreachable, e.message)
        end
      end

      def update_local_node_status(node_id)
        metrics = collect_local_metrics

        status = assess_node_health(metrics)

        @node_statuses[node_id] = {
          status: status,
          metrics: metrics,
          last_check: Time.now,
          is_leader: Distributed::Consensus::RaftNode.instance.leader?,
          term: Distributed::Consensus::RaftNode.instance.current_term
        }

        check_metric_alerts(node_id, metrics)
      end

      def update_remote_node_status(node_id, node_info)
        return unless node_info

        uri = URI("http://#{node_info[:host]}:#{node_info[:port] || 7200}/health")
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 2
        http.read_timeout = 5

        response = http.get(uri.path)

        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body).deep_symbolize_keys

          status = data[:status] || Status::HEALTHY
          metrics = data[:metrics] || {}

          @node_statuses[node_id] = {
            status: status,
            metrics: metrics,
            last_check: Time.now,
            is_leader: data[:is_leader],
            term: data[:term]
          }

          # Check if previously unreachable node is now back
          resolve_node_alert(node_id, :node_unreachable)

          check_metric_alerts(node_id, metrics)
        else
          @node_statuses[node_id] = {
            status: Status::DEGRADED,
            error: "HTTP #{response.code}",
            last_check: Time.now
          }
        end
      rescue Timeout::Error, Errno::ECONNREFUSED, SocketError => e
        @node_statuses[node_id] = {
          status: Status::UNHEALTHY,
          error: e.message,
          last_check: Time.now
        }

        check_and_create_alert(node_id, :node_unreachable, e.message)
      end

      def assess_node_health(metrics)
        # Check critical thresholds first
        if metrics[:cpu] && metrics[:cpu] >= @thresholds[:cpu_critical]
          return Status::UNHEALTHY
        end

        if metrics[:memory] && metrics[:memory] >= @thresholds[:memory_critical]
          return Status::UNHEALTHY
        end

        if metrics[:disk] && metrics[:disk] >= @thresholds[:disk_critical]
          return Status::UNHEALTHY
        end

        if metrics[:error_rate] && metrics[:error_rate] >= @thresholds[:error_rate_critical]
          return Status::UNHEALTHY
        end

        # Check warning thresholds
        if (metrics[:cpu] && metrics[:cpu] >= @thresholds[:cpu_warning]) ||
           (metrics[:memory] && metrics[:memory] >= @thresholds[:memory_warning]) ||
           (metrics[:disk] && metrics[:disk] >= @thresholds[:disk_warning]) ||
           (metrics[:latency] && metrics[:latency] >= @thresholds[:latency_warning]) ||
           (metrics[:error_rate] && metrics[:error_rate] >= @thresholds[:error_rate_warning])
          return Status::DEGRADED
        end

        Status::HEALTHY
      end

      def update_cluster_status
        statuses = @node_statuses.values.map { |n| n[:status] }

        if statuses.empty? || statuses.all? { |s| s == Status::UNKNOWN }
          @cluster_status = Status::UNKNOWN
        elsif statuses.any? { |s| s == Status::UNHEALTHY }
          unhealthy_count = statuses.count { |s| s == Status::UNHEALTHY }

          # If majority of nodes are unhealthy, cluster is unhealthy
          if unhealthy_count > statuses.size / 2
            @cluster_status = Status::UNHEALTHY
            check_and_create_alert('cluster', :cluster_unhealthy, "#{unhealthy_count}/#{statuses.size} nodes unhealthy")
          else
            @cluster_status = Status::DEGRADED
            check_and_create_alert('cluster', :cluster_degraded, "#{unhealthy_count} unhealthy nodes")
          end
        elsif statuses.any? { |s| s == Status::DEGRADED }
          @cluster_status = Status::DEGRADED
        else
          @cluster_status = Status::HEALTHY
          resolve_cluster_alerts
        end

        # Check for leader
        leader_count = @node_statuses.values.count { |n| n[:is_leader] }
        if leader_count == 0
          check_and_create_alert('cluster', :no_leader, "No leader elected in cluster")
        elsif leader_count > 1
          check_and_create_alert('cluster', :multiple_leaders, "Multiple leaders detected: #{leader_count}")
        end
      end

      def collect_metrics
        # Collect metrics from all nodes
        @node_statuses.each do |node_id, status|
          next unless status[:metrics]

          @node_metrics[node_id] ||= []
          @node_metrics[node_id] << {
            timestamp: Time.now,
            metrics: status[:metrics]
          }

          # Keep only recent metrics (last hour)
          @node_metrics[node_id] = @node_metrics[node_id].select do |m|
            m[:timestamp] > 1.hour.ago
          end
        end
      end

      def collect_local_metrics
        {
          cpu: get_cpu_usage,
          memory: get_memory_usage,
          disk: get_disk_usage,
          latency: get_average_latency,
          error_rate: get_error_rate,
          vector_count: get_vector_count,
          connections: get_connection_count
        }
      end

      def get_cpu_usage
        # Read from /proc/stat on Linux
        if File.exist?('/proc/stat')
          cpu_line = File.readlines('/proc/stat').first
          parts = cpu_line.split[1..].map(&:to_i)
          idle = parts[3]
          total = parts.sum
          ((total - idle).to_f / total * 100).round(1)
        else
          0
        end
      rescue
        0
      end

      def get_memory_usage
        if File.exist?('/proc/meminfo')
          meminfo = File.read('/proc/meminfo')
          total = meminfo.match(/MemTotal:\s+(\d+)/)[1].to_i
          available = meminfo.match(/MemAvailable:\s+(\d+)/)[1].to_i
          ((total - available).to_f / total * 100).round(1)
        else
          0
        end
      rescue
        0
      end

      def get_disk_usage
        # Use df command for disk usage
        output = `df -P / | tail -1 2>/dev/null`
        parts = output.split
        parts[4].to_i if parts[4]
      rescue
        0
      end

      def get_average_latency
        # Get from distributed search service metrics
        metrics = Distributed::Search::DistributedSearchService.instance.get_metrics
        metrics[:avg_search_time] || 0
      rescue
        0
      end

      def get_error_rate
        # Calculate from recent requests
        metrics = Distributed::Search::DistributedSearchService.instance.get_metrics
        # This would need to be tracked separately
        0
      rescue
        0
      end

      def get_vector_count
        # Total vectors across all indexes
        Distributed::Search::DistributedSearchService.instance.get_metrics[:total_indexes] || 0
      rescue
        0
      end

      def get_connection_count
        # Active database connections
        ActiveRecord::Base.connection_pool.stat[:size] rescue 0
      end

      def aggregate_metrics
        return {} if @node_metrics.empty?

        {
          avg_cpu: @node_statuses.values.map { |n| n.dig(:metrics, :cpu) }.compact.sum.to_f / @node_statuses.size,
          avg_memory: @node_statuses.values.map { |n| n.dig(:metrics, :memory) }.compact.sum.to_f / @node_statuses.size,
          avg_latency: @node_statuses.values.map { |n| n.dig(:metrics, :latency) }.compact.sum.to_f / @node_statuses.size,
          total_vectors: @node_statuses.values.map { |n| n.dig(:metrics, :vector_count) }.compact.sum
        }
      end

      def check_metric_alerts(node_id, metrics)
        # CPU alerts
        if metrics[:cpu]
          if metrics[:cpu] >= @thresholds[:cpu_critical]
            check_and_create_alert(node_id, :cpu_critical, "CPU usage: #{metrics[:cpu]}%")
          elsif metrics[:cpu] >= @thresholds[:cpu_warning]
            check_and_create_alert(node_id, :cpu_warning, "CPU usage: #{metrics[:cpu]}%")
          else
            resolve_node_alert(node_id, :cpu_critical)
            resolve_node_alert(node_id, :cpu_warning)
          end
        end

        # Memory alerts
        if metrics[:memory]
          if metrics[:memory] >= @thresholds[:memory_critical]
            check_and_create_alert(node_id, :memory_critical, "Memory usage: #{metrics[:memory]}%")
          elsif metrics[:memory] >= @thresholds[:memory_warning]
            check_and_create_alert(node_id, :memory_warning, "Memory usage: #{metrics[:memory]}%")
          else
            resolve_node_alert(node_id, :memory_critical)
            resolve_node_alert(node_id, :memory_warning)
          end
        end

        # Disk alerts
        if metrics[:disk]
          if metrics[:disk] >= @thresholds[:disk_critical]
            check_and_create_alert(node_id, :disk_critical, "Disk usage: #{metrics[:disk]}%")
          elsif metrics[:disk] >= @thresholds[:disk_warning]
            check_and_create_alert(node_id, :disk_warning, "Disk usage: #{metrics[:disk]}%")
          else
            resolve_node_alert(node_id, :disk_critical)
            resolve_node_alert(node_id, :disk_warning)
          end
        end
      end

      def check_and_create_alert(node_id, alert_type, message)
        # Check if active alert already exists
        existing = @alerts.find do |a|
          a[:node_id] == node_id && a[:type] == alert_type && !a[:resolved]
        end

        return if existing

        alert = {
          id: SecureRandom.uuid,
          node_id: node_id,
          type: alert_type,
          message: message,
          severity: alert_severity(alert_type),
          created_at: Time.now,
          acknowledged: false,
          resolved: false
        }

        @alerts << alert

        # Keep only last 1000 alerts
        @alerts.shift if @alerts.size > 1000

        # Notify handlers
        @alert_handlers.each do |handler|
          begin
            handler.call(alert)
          rescue => e
            Rails.logger.error("[ClusterHealth] Alert handler error: #{e.message}")
          end
        end

        Rails.logger.warn("[ClusterHealth] Alert: #{alert_type} on #{node_id} - #{message}")
      end

      def resolve_node_alert(node_id, alert_type)
        @alerts.each do |alert|
          if alert[:node_id] == node_id && alert[:type] == alert_type && !alert[:resolved]
            alert[:resolved] = true
            alert[:resolved_at] = Time.now
            alert[:resolution_note] = 'Auto-resolved'

            Rails.logger.info("[ClusterHealth] Auto-resolved alert: #{alert_type} on #{node_id}")
          end
        end
      end

      def resolve_cluster_alerts
        [:cluster_unhealthy, :cluster_degraded].each do |alert_type|
          resolve_node_alert('cluster', alert_type)
        end
      end

      def alert_severity(alert_type)
        case alert_type.to_s
        when /critical/, /unreachable/, /no_leader/, /multiple_leaders/
          :critical
        when /warning/, /degraded/
          :warning
        else
          :info
        end
      end

      def get_node_info(node_id)
        # Get node connection info from config
        config = Distributed::Config::ConfigurationAdapter.instance
        # This would need to be stored in configuration
        # For now, return nil for remote nodes
        nil
      end

      def local_node_id
        Rails.configuration.distributed&.node_id
      end
    end
  end
end
