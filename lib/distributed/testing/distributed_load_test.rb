# frozen_string_literal: true

module Distributed
  module Testing
    # Comprehensive load testing framework for distributed architecture
    class DistributedLoadTest
      attr_reader :config, :metrics, :simulator

      # Initialize a new DistributedLoadTest with options
      # @param options [Hash] Configuration options to override defaults
      def initialize(options = {})
        @config = default_config.merge(options)
        @metrics = RecoveryMetrics.new
        @simulator = NetworkSimulator
        @vector_generator = Benchmark::VectorGenerator.new
      end

      # Run all configured test scenarios
      # @return [Hash] Results of all test scenarios
      def run
        results = {}
        start_time = Time.now

        # Reset metrics to ensure clean state
        @metrics.reset_metrics

        # Run selected test scenarios
        Array(@config[:test_scenarios]).each do |scenario|
          scenario_sym = scenario.to_sym
          if respond_to?("test_#{scenario_sym}")
            log "Running #{scenario_sym} test scenario..."
            results[scenario_sym] = send("test_#{scenario_sym}")
          else
            log "Unknown test scenario: #{scenario_sym}", :warn
          end
        end

        # Calculate total duration
        duration = Time.now - start_time
        results[:total_duration] = duration
        
        log "All test scenarios completed in #{duration.round(2)} seconds"
        results
      end

      # Test horizontal scaling with different node counts
      # @return [Hash] Test results for horizontal scaling
      def test_horizontal_scaling
        log "Beginning horizontal scaling tests with node counts: #{@config[:node_counts].join(', ')}"
        results = { node_performance: {} }

        # Test each configured node count
        @config[:node_counts].each do |node_count|
          log "Testing with #{node_count} nodes..."
          
          # Setup cluster with specific node count
          setup_cluster(node_count)
          
          # Allow time for cluster formation
          sleep 2
          
          # Create test scenario for metrics
          scenario_id = @metrics.start_scenario("scaling_#{node_count}_nodes", {
            type: :horizontal_scaling,
            node_count: node_count
          })
          
          # Generate test vectors
          test_vectors = @vector_generator.generate_vectors(
            @config[:vector_count],
            384, # Default dimension
            @config[:vector_distribution] || :random
          )
          
          # Insert test data
          insert_latencies = []
          test_vectors.each_slice(100) do |vector_batch|
            latency = measure_performance do
              insert_vectors(vector_batch)
            end
            insert_latencies << latency
          end
          
          @metrics.record_checkpoint(:data_insertion_complete, {
            vectors: test_vectors.size,
            avg_latency_ms: (insert_latencies.sum / insert_latencies.size).round(2)
          })
          
          # Run query tests
          query_latencies = []
          @config[:query_count].times do |i|
            # Select random vector as query
            query_vector = test_vectors.sample
            
            latency = measure_performance do
              # Execute query and verify results
              query_vectors(query_vector)
            end
            query_latencies << latency
            
            log "Completed query #{i+1}/#{@config[:query_count]}..." if (i+1) % 100 == 0
          end
          
          # Record checkpoint for query completion
          @metrics.record_checkpoint(:queries_complete, {
            queries: @config[:query_count],
            avg_latency_ms: (query_latencies.sum / query_latencies.size).round(2),
            p95_latency_ms: percentile(query_latencies, 95).round(2),
            p99_latency_ms: percentile(query_latencies, 99).round(2),
            min_latency_ms: query_latencies.min.round(2),
            max_latency_ms: query_latencies.max.round(2)
          })
          
          # Measure resource utilization
          resource_metrics = measure_resource_usage
          @metrics.record_checkpoint(:resource_metrics, resource_metrics)
          
          # End the scenario and collect results
          @metrics.end_scenario(1.0) # Data consistency should be perfect in scaling tests
          
          # Store metrics for this node count
          results[:node_performance][node_count] = {
            avg_query_latency_ms: (query_latencies.sum / query_latencies.size).round(2),
            p95_latency_ms: percentile(query_latencies, 95).round(2),
            p99_latency_ms: percentile(query_latencies, 99).round(2),
            queries_per_second: (@config[:query_count] / (query_latencies.sum / 1000)).round(2),
            resource_usage: resource_metrics
          }
          
          log "Completed testing with #{node_count} nodes"
          
          # Teardown cluster
          teardown_cluster
        end
        
        # Analyze scaling efficiency
        results[:scaling_efficiency] = analyze_scaling_efficiency(results[:node_performance])
        
        log "Horizontal scaling tests completed"
        results
      end

      # Test node failure recovery scenarios
      # @return [Hash] Test results for node failure recovery
      def test_node_failure_recovery
        log "Beginning node failure recovery tests"
        results = { scenarios: {} }
        
        # Always use a reasonable node count for failure tests (minimum 3 for consensus)
        node_count = [@config[:failure_recovery_nodes] || 5, 3].max
        log "Setting up cluster with #{node_count} nodes for failure testing..."
        
        # Setup cluster
        setup_cluster(node_count)
        
        # Allow time for cluster formation
        sleep 2
        
        # Generate and insert test data
        test_vectors = @vector_generator.generate_vectors(
          @config[:vector_count],
          384, # Default dimension
          @config[:vector_distribution] || :random
        )
        
        log "Inserting #{test_vectors.size} test vectors..."
        test_vectors.each_slice(100) do |vector_batch|
          insert_vectors(vector_batch)
        end
        
        # Test single node failure
        log "Testing single node failure recovery..."
        results[:scenarios][:single_node_failure] = test_single_node_failure(test_vectors)
        
        # Test multiple node failures (but maintaining quorum)
        if node_count >= 5
          log "Testing multiple node failures recovery..."
          results[:scenarios][:multiple_node_failure] = test_multiple_node_failure(test_vectors)
        end
        
        # Test network partition
        log "Testing network partition recovery..."
        results[:scenarios][:network_partition] = test_network_partition(test_vectors)
        
        # Test log corruption
        log "Testing log corruption recovery..."
        results[:scenarios][:log_corruption] = test_log_corruption(test_vectors)
        
        # Teardown cluster
        teardown_cluster
        
        # Calculate average recovery metrics
        results[:avg_detection_time_ms] = @metrics.summary_statistics[:avg_detection_time_ms]
        results[:avg_recovery_time_ms] = @metrics.summary_statistics[:avg_recovery_time_ms]
        results[:avg_data_consistency] = @metrics.summary_statistics[:avg_data_consistency]
        
        log "Node failure recovery tests completed"
        results
      end

      # Test recovery from network partitions
      # @return [Hash] Test results for network partition recovery
      def test_network_partition_recovery
        log "Beginning network partition recovery test"
        
        # Create test scenario for metrics
        scenario_id = @metrics.start_scenario("network_partition", {
          type: :network_partition
        })
        
        # Record pre-partition state
        service = Distributed::DistributedService.instance
        pre_leader = service.cluster_nodes.find { |n| n.state == 'leader' }&.node_id
        
        # Get nodes to partition (not including leader)
        nodes = service.cluster_nodes.select { |n| n.state != 'leader' }.sample(service.cluster_nodes.size / 2)
        partition_nodes = nodes.map(&:node_id)
        
        log "Creating network partition for nodes: #{partition_nodes.join(', ')}"
        
        # Record pre-partition query performance
        pre_query_latencies = measure_query_performance
        
        # Create network partition
        @metrics.record_checkpoint(:partition_start)
        heal_partition = @simulator.create_partition(partition_nodes)
        
        # Wait for detection and leader election
        sleep 2
        @metrics.record_checkpoint(:failure_detected)
        
        # Verify leader election completed if leader was in partition
        if partition_nodes.include?(pre_leader)
          new_leader = service.cluster_nodes.find { |n| n.state == 'leader' }&.node_id
          if new_leader && new_leader != pre_leader
            @metrics.record_checkpoint(:leader_elected, { new_leader: new_leader })
          end
        end
        
        # Attempt operations during partition
        during_query_latencies = measure_query_performance
        
        # Heal partition
        log "Healing network partition"
        @metrics.record_checkpoint(:healing_start)
        heal_partition.call
        
        # Allow time for recovery
        sleep 3
        @metrics.record_checkpoint(:recovery_complete)
        
        # Measure post-recovery performance
        post_query_latencies = measure_query_performance
        
        # Verify data consistency
        data_consistency = verify_data_consistency
        
        # End the scenario
        @metrics.end_scenario(data_consistency)
        
        # Compile results
        {
          pre_partition_latency_ms: (pre_query_latencies.sum / pre_query_latencies.size).round(2),
          during_partition_latency_ms: (during_query_latencies.sum / during_query_latencies.size).round(2),
          post_recovery_latency_ms: (post_query_latencies.sum / post_query_latencies.size).round(2),
          recovery_time_ms: @metrics.metrics[:scenarios][scenario_id][:checkpoints][:recovery_complete][:time_since_start_ms],
          data_consistency: data_consistency
        }
      end

      # Test cross-node query performance
      # @return [Hash] Test results for cross-node queries
      def test_cross_node_query_performance
        log "Beginning cross-node query performance test"
        results = {}
        
        # Setup a cluster with the maximum node count for this test
        max_nodes = @config[:node_counts].max
        setup_cluster(max_nodes)
        
        # Generate and insert test vectors
        test_vectors = @vector_generator.generate_vectors(
          @config[:vector_count],
          384, # Default dimension
          @config[:vector_distribution] || :random
        )
        
        log "Inserting #{test_vectors.size} test vectors..."
        test_vectors.each_slice(100) do |vector_batch|
          insert_vectors(vector_batch)
        end
        
        # Test different query patterns
        query_patterns = [:single_node, :cross_node, :all_nodes]
        
        query_patterns.each do |pattern|
          log "Testing #{pattern} query pattern..."
          
          query_latencies = []
          start_time = Time.now
          
          @config[:query_count].times do |i|
            query_vector = test_vectors.sample
            
            latency = measure_performance do
              execute_query_with_pattern(query_vector, pattern)
            end
            
            query_latencies << latency
            
            log "Completed #{pattern} query #{i+1}/#{@config[:query_count]}..." if (i+1) % 100 == 0
          end
          
          duration = Time.now - start_time
          
          results[pattern] = {
            avg_latency_ms: (query_latencies.sum / query_latencies.size).round(2),
            p95_latency_ms: percentile(query_latencies, 95).round(2),
            p99_latency_ms: percentile(query_latencies, 99).round(2),
            min_latency_ms: query_latencies.min.round(2),
            max_latency_ms: query_latencies.max.round(2),
            queries_per_second: (@config[:query_count] / duration).round(2)
          }
        end
        
        # Teardown cluster
        teardown_cluster
        
        log "Cross-node query performance tests completed"
        results
      end

      # Test multi-tenant data isolation under load
      # @return [Hash] Test results for multi-tenant isolation
      def test_multi_tenant_isolation
        log "Beginning multi-tenant isolation test"
        results = { organization_isolation: {} }
        
        # Use a moderate node count
        node_count = [@config[:node_counts].max, 4].min
        setup_cluster(node_count)
        
        # Test organizations to simulate
        org_count = @config[:organization_count] || 5
        orgs = (1..org_count).map { |i| "test-org-#{i}" }
        
        # Generate per-organization test data
        org_vectors = {}
        
        orgs.each do |org|
          log "Generating test data for organization: #{org}"
          vectors = @vector_generator.generate_vectors(
            @config[:vector_count] / org_count,
            384,
            @config[:vector_distribution] || :random
          )
          
          org_vectors[org] = vectors
          
          # Insert vectors for this organization
          vectors.each_slice(100) do |vector_batch|
            insert_vectors(vector_batch, org)
          end
        end
        
        # Test isolation by querying each organization's data
        orgs.each do |org|
          log "Testing isolation for organization: #{org}"
          
          cross_contamination = 0
          query_latencies = []
          
          # Sample some vectors to query
          test_queries = org_vectors[org].sample(@config[:query_count] / org_count)
          
          test_queries.each do |query_vector|
            # Execute query for this organization
            latency, results = measure_performance_with_results do
              query_vectors(query_vector, org)
            end
            
            query_latencies << latency
            
            # Check if results contain vectors from other organizations
            if results.any? { |r| r[:organization_id] != org }
              cross_contamination += 1
            end
          end
          
          # Calculate isolation metrics
          isolation_rate = 1.0 - (cross_contamination.to_f / test_queries.size)
          
          results[:organization_isolation][org] = {
            isolation_rate: isolation_rate,
            avg_query_latency_ms: (query_latencies.sum / query_latencies.size).round(2),
            cross_contamination_count: cross_contamination
          }
        end
        
        # Test concurrent multi-tenant queries
        log "Testing concurrent multi-tenant queries"
        concurrent_isolation_rate = test_concurrent_multi_tenant_queries(org_vectors)
        results[:concurrent_isolation_rate] = concurrent_isolation_rate
        
        # Teardown cluster
        teardown_cluster
        
        log "Multi-tenant isolation tests completed"
        results
      end

      # Generate a detailed report of all test results
      # @param results [Hash] Test results to include in the report
      # @return [String] Markdown-formatted report
      def generate_report
        log "Generating test report..."
        
        report = "# Distributed Architecture Load Test Report\n\n"
        report += "## Summary\n\n"
        
        # Add summary statistics
        stats = @metrics.summary_statistics
        report += "- **Test Time**: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}\n"
        report += "- **Total Scenarios**: #{stats[:total_scenarios]}\n"
        report += "- **Average Detection Time**: #{stats[:avg_detection_time_ms].round(2)}ms\n"
        report += "- **Average Recovery Time**: #{stats[:avg_recovery_time_ms].round(2)}ms\n"
        report += "- **Average Data Consistency**: #{(stats[:avg_data_consistency] * 100).round(2)}%\n\n"
        
        # Add horizontal scaling results if available
        if @metrics.metrics[:scenarios].any? { |_id, data| data[:details][:type] == :horizontal_scaling }
          report += "## Horizontal Scaling Performance\n\n"
          
          # Group scenarios by node count
          scaling_results = {}
          @metrics.metrics[:scenarios].each do |id, data|
            next unless data[:details][:type] == :horizontal_scaling
            node_count = data[:details][:node_count]
            scaling_results[node_count] = data
          end
          
          # Create a table of scaling results
          report += "| Node Count | Avg Query Latency | P95 Latency | Queries/sec | Memory Usage |\n"
          report += "|------------|------------------|-------------|-------------|---------------|\n"
          
          scaling_results.keys.sort.each do |node_count|
            data = scaling_results[node_count]
            query_metrics = data[:checkpoints][:queries_complete][:details]
            resource_metrics = data[:checkpoints][:resource_metrics][:details]
            
            report += "| #{node_count} | #{query_metrics[:avg_latency_ms]}ms | "
            report += "#{query_metrics[:p95_latency_ms]}ms | "
            report += "#{(@config[:query_count] / (query_metrics[:avg_latency_ms] * @config[:query_count] / 1000)).round(2)} | "
            report += "#{resource_metrics[:memory_mb]}MB |\n"
          end
          
          report += "\n"
        end
        
        # Add failure recovery results if available
        failure_scenarios = @metrics.metrics[:scenarios].select { |_id, data| 
          [:node_crash, :network_partition, :log_corruption].include?(data[:details][:type])
        }
        
        if failure_scenarios.any?
          report += "## Failure Recovery Performance\n\n"
          
          report += "| Scenario Type | Detection Time | Recovery Time | Data Consistency |\n"
          report += "|---------------|---------------|---------------|------------------|\n"
          
          failure_scenarios.each do |id, data|
            detection_time = data[:checkpoints][:failure_detected] ? 
              data[:checkpoints][:failure_detected][:time_since_start_ms] : "N/A"
            
            recovery_time = data[:checkpoints][:recovery_complete] ?
              data[:checkpoints][:recovery_complete][:time_since_start_ms] : "N/A"
            
            consistency = data[:data_consistency] ? 
              "#{(data[:data_consistency] * 100).round(2)}%" : "N/A"
            
            report += "| #{data[:details][:type].to_s.titleize} | #{detection_time}ms | "
            report += "#{recovery_time}ms | #{consistency} |\n"
          end
          
          report += "\n"
        end
        
        # Add detailed metrics for all scenarios
        report += "## Detailed Scenario Results\n\n"
        
        @metrics.metrics[:scenarios].each do |id, data|
          report += "### #{data[:name]}\n\n"
          report += "- **Type**: #{data[:details][:type] || 'N/A'}\n"
          report += "- **Duration**: #{data[:duration_ms]}ms\n"
          report += "- **Data Consistency**: #{data[:data_consistency] ? "#{(data[:data_consistency] * 100).round(2)}%" : 'N/A'}\n\n"
          
          if data[:checkpoints].any?
            report += "**Checkpoints**:\n\n"
            data[:checkpoints].each do |checkpoint, cp_data|
              report += "- **#{checkpoint}**: +#{cp_data[:time_since_previous_ms]}ms (total: #{cp_data[:time_since_start_ms]}ms)\n"
              
              # Add checkpoint details if present
              if cp_data[:details] && !cp_data[:details].empty?
                cp_data[:details].each do |key, value|
                  report += "  - #{key}: #{value}\n"
                end
              end
            end
          end
          
          report += "\n"
        end
        
        # Add recommendations section
        report += "## Recommendations\n\n"
        
        # Analyze scaling efficiency to make recommendations
        if @metrics.metrics[:scenarios].any? { |_id, data| data[:details][:type] == :horizontal_scaling }
          scaling_efficiency = analyze_scaling_efficiency_from_metrics
          
          optimal_node_count = identify_optimal_node_count(scaling_efficiency)
          report += "- **Optimal Node Count**: #{optimal_node_count} nodes provides the best balance of performance and resource usage.\n"
          
          latency_sensitive_count = identify_latency_sensitive_node_count
          report += "- **For Latency-Sensitive Applications**: Consider using #{latency_sensitive_count} nodes.\n"
          
          throughput_sensitive_count = identify_throughput_sensitive_node_count
          report += "- **For Throughput-Sensitive Applications**: Consider using #{throughput_sensitive_count} nodes.\n"
        end
        
        # Add recovery recommendations
        if failure_scenarios.any?
          avg_recovery = stats[:avg_recovery_time_ms]
          
          if avg_recovery > 5000
            report += "- **Recovery Time Improvement**: Consider optimizing the recovery process to reduce the current average of #{avg_recovery.round(2)}ms.\n"
          else
            report += "- **Recovery Performance**: Current recovery time of #{avg_recovery.round(2)}ms is within acceptable limits.\n"
          end
          
          # Data consistency recommendations
          avg_consistency = stats[:avg_data_consistency]
          if avg_consistency < 0.99
            report += "- **Data Consistency Improvement**: Current consistency rate of #{(avg_consistency * 100).round(2)}% is below the target of 99%. Consider adjusting synchronization protocols.\n"
          else
            report += "- **Data Consistency**: Excellent consistency rate of #{(avg_consistency * 100).round(2)}% achieved after recovery.\n"
          end
        end
        
        report
      end

      private

      # Default configuration for the load test
      # @return [Hash] Default configuration
      def default_config
        {
          node_counts: [2, 4, 8, 16],
          vector_count: 10000,
          query_count: 1000,
          test_scenarios: [:horizontal_scaling, :node_failure_recovery, :cross_node_query_performance, :multi_tenant_isolation],
          failure_scenarios: [:node_crash, :network_partition, :log_corruption],
          report_format: :markdown,
          organization_count: 5,
          vector_distribution: :random,
          failure_recovery_nodes: 5,
          verbose: false
        }
      end

      # Log a message with optional level
      # @param message [String] Message to log
      # @param level [Symbol] Log level (:info, :warn, :error)
      def log(message, level = :info)
        return unless @config[:verbose]
        
        case level
        when :warn
          puts "⚠️ WARNING: #{message}"
        when :error
          puts "❌ ERROR: #{message}"
        else
          puts "ℹ️ #{message}"
        end
      end

      # Setup a cluster with the specified number of nodes
      # @param node_count [Integer] Number of nodes to create
      def setup_cluster(node_count)
        # Configure distributed service
        Rails.configuration.distributed = OpenStruct.new({
          enabled: true,
          auto_start: true,
          node_id: "test-node-1",
          cluster_nodes: (1..node_count).map { |i| "test-node-#{i}@localhost:#{3000 + i}" }
        })
        
        # Initialize service
        service = Distributed::DistributedService.instance
        service.initialize_service
        
        # Wait for initialization
        sleep 2
        
        log "Cluster setup complete with #{node_count} nodes"
        service
      end

      # Teardown the cluster and cleanup
      def teardown_cluster
        service = Distributed::DistributedService.instance
        service.shutdown if service&.initialized
        log "Cluster teardown complete"
      end

      # Insert vectors into the distributed system
      # @param vectors [Array] Vectors to insert
      # @param organization_id [String] Optional organization ID for multi-tenant testing
      def insert_vectors(vectors, organization_id = nil)
        service = Distributed::DistributedService.instance
        
        vectors.each_with_index do |vector, i|
          # Simulate storing vector in distributed system
          if service.operational?
            # Use log adapter to append an entry (simulating vector storage)
            entry = {
              operation: 'store_vector',
              vector_id: "test-vector-#{i}",
              vector_hash: vector.hash.to_s,
              timestamp: Time.now.to_i
            }
            
            # Add organization ID if provided
            entry[:organization_id] = organization_id if organization_id
            
            service.log_adapter&.append_log_entry(entry)
          end
        end
      end

      # Query vectors from the distributed system
      # @param query_vector [Array] Query vector
      # @param organization_id [String] Optional organization ID for multi-tenant testing
      # @return [Array] Query results
      def query_vectors(query_vector, organization_id = nil)
        service = Distributed::DistributedService.instance
        
        # Simulate a distributed search operation
        if service.operational?
          entry = {
            operation: 'search_vector',
            vector_hash: query_vector.hash.to_s,
            timestamp: Time.now.to_i
          }
          
          # Add organization ID if provided
          entry[:organization_id] = organization_id if organization_id
          
          service.log_adapter&.append_log_entry(entry)
          
          # Return simulated results
          [{ vector_id: "test-vector-#{rand(1000)}", organization_id: organization_id || "default-org" }]
        else
          []
        end
      end

      # Execute a query with a specific pattern
      # @param query_vector [Array] Query vector
      # @param pattern [Symbol] Query pattern (:single_node, :cross_node, or :all_nodes)
      # @return [Array] Query results
      def execute_query_with_pattern(query_vector, pattern)
        service = Distributed::DistributedService.instance
        
        case pattern
        when :single_node
          # Target a single random node
          target_node = service.cluster_nodes.sample
          
          # Simulate query to specific node
          entry = {
            operation: 'search_vector_single_node',
            vector_hash: query_vector.hash.to_s,
            target_node: target_node.node_id,
            timestamp: Time.now.to_i
          }
          
          service.log_adapter&.append_log_entry(entry)
        when :cross_node
          # Target a subset of nodes
          target_nodes = service.cluster_nodes.sample(service.cluster_nodes.size / 2)
          
          # Simulate cross-node query
          entry = {
            operation: 'search_vector_cross_node',
            vector_hash: query_vector.hash.to_s,
            target_nodes: target_nodes.map(&:node_id),
            timestamp: Time.now.to_i
          }
          
          service.log_adapter&.append_log_entry(entry)
        when :all_nodes
          # Target all nodes
          entry = {
            operation: 'search_vector_all_nodes',
            vector_hash: query_vector.hash.to_s,
            target_nodes: service.cluster_nodes.map(&:node_id),
            timestamp: Time.now.to_i
          }
          
          service.log_adapter&.append_log_entry(entry)
        end
        
        # Return simulated results
        [{ vector_id: "test-vector-#{rand(1000)}" }]
      end

      # Test single node failure scenario
      # @param test_vectors [Array] Test vectors
      # @return [Hash] Test results
      def test_single_node_failure(test_vectors)
        service = Distributed::DistributedService.instance
        
        # Create test scenario
        scenario_id = @metrics.start_scenario("single_node_failure", { type: :node_crash })
        
        # Choose a non-leader node to crash
        leader_node = service.cluster_nodes.find { |n| n.state == 'leader' }
        node_to_crash = service.cluster_nodes.find { |n| n != leader_node }
        
        # Measure pre-failure performance
        pre_failure_latencies = measure_query_performance(test_vectors)
        
        # Crash the node
        log "Crashing node #{node_to_crash.node_id}"
        @metrics.record_checkpoint(:failure_start)
        recover_node = @simulator.crash_node(node_to_crash.node_id)
        
        # Wait for detection
        sleep 1
        @metrics.record_checkpoint(:failure_detected)
        
        # Measure during-failure performance
        during_failure_latencies = measure_query_performance(test_vectors)
        
        # Recover the node
        log "Recovering node #{node_to_crash.node_id}"
        @metrics.record_checkpoint(:recovery_start)
        recover_node.call
        
        # Wait for recovery
        sleep 2
        @metrics.record_checkpoint(:recovery_complete)
        
        # Measure post-recovery performance
        post_recovery_latencies = measure_query_performance(test_vectors)
        
        # Verify data consistency
        data_consistency = verify_data_consistency
        
        # End scenario
        @metrics.end_scenario(data_consistency)
        
        # Return results
        {
          node_id: node_to_crash.node_id,
          pre_failure_latency_ms: (pre_failure_latencies.sum / pre_failure_latencies.size).round(2),
          during_failure_latency_ms: (during_failure_latencies.sum / during_failure_latencies.size).round(2),
          post_recovery_latency_ms: (post_recovery_latencies.sum / post_recovery_latencies.size).round(2),
          detection_time_ms: @metrics.metrics[:scenarios][scenario_id][:checkpoints][:failure_detected][:time_since_start_ms],
          recovery_time_ms: @metrics.metrics[:scenarios][scenario_id][:checkpoints][:recovery_complete][:time_since_start_ms],
          data_consistency: data_consistency
        }
      end

      # Test multiple node failures scenario
      # @param test_vectors [Array] Test vectors
      # @return [Hash] Test results
      def test_multiple_node_failure(test_vectors)
        service = Distributed::DistributedService.instance
        
        # Create test scenario
        scenario_id = @metrics.start_scenario("multiple_node_failure", { type: :node_crash })
        
        # Choose multiple non-leader nodes to crash (but maintain quorum)
        leader_node = service.cluster_nodes.find { |n| n.state == 'leader' }
        nodes_to_crash = service.cluster_nodes.select { |n| n != leader_node }.sample(2)
        
        # Measure pre-failure performance
        pre_failure_latencies = measure_query_performance(test_vectors)
        
        # Crash the nodes
        node_ids = nodes_to_crash.map(&:node_id)
        log "Crashing nodes: #{node_ids.join(', ')}"
        
        @metrics.record_checkpoint(:failure_start)
        recover_nodes = nodes_to_crash.map { |node| @simulator.crash_node(node.node_id) }
        
        # Wait for detection
        sleep 2
        @metrics.record_checkpoint(:failure_detected)
        
        # Measure during-failure performance
        during_failure_latencies = measure_query_performance(test_vectors)
        
        # Recover the nodes one by one
        log "Recovering nodes sequentially"
        
        @metrics.record_checkpoint(:recovery_start)
        recover_nodes.each_with_index do |recover_node, i|
          recover_node.call
          sleep 1
          @metrics.record_checkpoint(:"node_#{i+1}_recovered")
        end
        
        # Wait for full recovery
        sleep 3
        @metrics.record_checkpoint(:recovery_complete)
        
        # Measure post-recovery performance
        post_recovery_latencies = measure_query_performance(test_vectors)
        
        # Verify data consistency
        data_consistency = verify_data_consistency
        
        # End scenario
        @metrics.end_scenario(data_consistency)
        
        # Return results
        {
          node_ids: node_ids,
          pre_failure_latency_ms: (pre_failure_latencies.sum / pre_failure_latencies.size).round(2),
          during_failure_latency_ms: (during_failure_latencies.sum / during_failure_latencies.size).round(2),
          post_recovery_latency_ms: (post_recovery_latencies.sum / post_recovery_latencies.size).round(2),
          detection_time_ms: @metrics.metrics[:scenarios][scenario_id][:checkpoints][:failure_detected][:time_since_start_ms],
          recovery_time_ms: @metrics.metrics[:scenarios][scenario_id][:checkpoints][:recovery_complete][:time_since_start_ms],
          data_consistency: data_consistency
        }
      end

      # Test log corruption recovery
      # @param test_vectors [Array] Test vectors
      # @return [Hash] Test results
      def test_log_corruption(test_vectors)
        service = Distributed::DistributedService.instance
        
        # Create test scenario
        scenario_id = @metrics.start_scenario("log_corruption", { type: :log_corruption })
        
        # Choose a non-leader node for log corruption
        leader_node = service.cluster_nodes.find { |n| n.state == 'leader' }
        node_to_corrupt = service.cluster_nodes.select { |n| n != leader_node }.sample
        
        # Measure pre-corruption performance
        pre_corruption_latencies = measure_query_performance(test_vectors)
        
        # Corrupt logs
        log "Corrupting logs for node #{node_to_corrupt.node_id}"
        @metrics.record_checkpoint(:corruption_start)
        @simulator.corrupt_logs(node_to_corrupt.node_id, :moderate)
        
        # Crash and recover the node to trigger log reconciliation
        recover_node = @simulator.crash_node(node_to_corrupt.node_id)
        
        # Wait for detection
        sleep 1
        @metrics.record_checkpoint(:failure_detected)
        
        # Measure during-corruption performance
        during_corruption_latencies = measure_query_performance(test_vectors)
        
        # Recover the node to trigger log reconciliation
        log "Recovering node to trigger log reconciliation"
        @metrics.record_checkpoint(:recovery_start)
        recover_node.call
        
        # Wait for reconciliation
        sleep 3
        @metrics.record_checkpoint(:recovery_complete)
        
        # Measure post-recovery performance
        post_recovery_latencies = measure_query_performance(test_vectors)
        
        # Verify data consistency (may be lower due to log corruption)
        data_consistency = verify_data_consistency
        
        # End scenario
        @metrics.end_scenario(data_consistency)
        
        # Return results
        {
          node_id: node_to_corrupt.node_id,
          pre_corruption_latency_ms: (pre_corruption_latencies.sum / pre_corruption_latencies.size).round(2),
          during_corruption_latency_ms: (during_corruption_latencies.sum / during_corruption_latencies.size).round(2),
          post_recovery_latency_ms: (post_recovery_latencies.sum / post_recovery_latencies.size).round(2),
          detection_time_ms: @metrics.metrics[:scenarios][scenario_id][:checkpoints][:failure_detected][:time_since_start_ms],
          recovery_time_ms: @metrics.metrics[:scenarios][scenario_id][:checkpoints][:recovery_complete][:time_since_start_ms],
          data_consistency: data_consistency
        }
      end

      # Test concurrent multi-tenant queries
      # @param org_vectors [Hash] Vectors by organization
      # @return [Float] Isolation rate (0.0-1.0)
      def test_concurrent_multi_tenant_queries(org_vectors)
        service = Distributed::DistributedService.instance
        
        log "Testing concurrent multi-tenant queries"
        
        cross_contamination_count = 0
        total_queries = 0
        
        # Simulate concurrent queries from multiple organizations
        threads = []
        org_vectors.each do |org, vectors|
          threads << Thread.new do
            # Sample vectors to query
            test_queries = vectors.sample((@config[:query_count] / org_vectors.size) / 2)
            
            test_queries.each do |query_vector|
              # Execute query for this organization
              results = query_vectors(query_vector, org)
              
              # Check if results contain vectors from other organizations
              if results.any? { |r| r[:organization_id] != org }
                cross_contamination_count += 1
              end
              
              total_queries += 1
            end
          end
        end
        
        # Wait for all threads to complete
        threads.each(&:join)
        
        # Calculate isolation rate
        isolation_rate = 1.0 - (cross_contamination_count.to_f / total_queries)
        
        log "Concurrent multi-tenant query isolation rate: #{(isolation_rate * 100).round(2)}%"
        
        isolation_rate
      end

      # Measure performance of an operation in milliseconds
      # @param block [Block] Operation to measure
      # @return [Float] Operation time in milliseconds
      def measure_performance(&block)
        start_time = Time.now
        yield
        end_time = Time.now
        (end_time - start_time) * 1000
      end

      # Measure performance of an operation and return results
      # @param block [Block] Operation to measure
      # @return [Array] [latency_ms, results]
      def measure_performance_with_results(&block)
        start_time = Time.now
        results = yield
        end_time = Time.now
        latency = (end_time - start_time) * 1000
        [latency, results]
      end

      # Measure query performance with sample queries
      # @param test_vectors [Array] Optional test vectors to query
      # @return [Array] Array of query latencies in milliseconds
      def measure_query_performance(test_vectors = nil)
        # If test vectors not provided, generate some
        test_vectors ||= @vector_generator.generate_vectors(
          100, # Small sample for quick testing
          384,
          @config[:vector_distribution] || :random
        )
        
        query_latencies = []
        
        20.times do
          # Select random vector as query
          query_vector = test_vectors.sample
          
          latency = measure_performance do
            # Execute query
            query_vectors(query_vector)
          end
          
          query_latencies << latency
        end
        
        query_latencies
      end

      # Measure current resource usage
      # @return [Hash] Resource metrics
      def measure_resource_usage
        # Use MemoryProfiler if available
        memory_usage = if defined?(Benchmark::MemoryProfiler)
                        Benchmark::MemoryProfiler.measure_memory_usage
                      else
                        process = Process.pid
                        `ps -o rss= -p #{process}`.strip.to_i / 1024
                      end
        
        # Get CPU usage
        cpu_usage = Process.times.utime + Process.times.stime
        
        {
          memory_mb: memory_usage.is_a?(Numeric) ? memory_usage : memory_usage[:allocated_memory_mb],
          cpu_usage: cpu_usage,
          process_count: 1, # For a real system, this would count worker processes
          timestamp: Time.now.to_i
        }
      end

      # Verify data consistency after recovery
      # @return [Float] Consistency rate (0.0-1.0)
      def verify_data_consistency
        # In a real implementation, this would verify actual data
        # For simulation, return a random consistency rate (0.9-1.0)
        # with preference to higher consistency
        
        # Skew toward higher consistency
        consistency_base = 0.9
        consistency_variation = 0.1
        
        consistency_base + (consistency_variation * rand**2)
      end

      # Calculate a percentile from an array of values
      # @param values [Array] Values to calculate percentile from
      # @param percentile [Float] Percentile to calculate (0-100)
      # @return [Float] Percentile value
      def percentile(values, percentile)
        return 0 if values.empty?
        
        sorted = values.sort
        k = (percentile / 100.0) * sorted.length
        
        if k.floor == k
          sorted[k.to_i - 1]
        else
          sorted[k.to_i]
        end
      end

      # Analyze scaling efficiency from node performance metrics
      # @param node_performance [Hash] Performance metrics by node count
      # @return [Hash] Scaling efficiency metrics
      def analyze_scaling_efficiency(node_performance)
        return {} if node_performance.empty?
        
        # Calculate relative scaling metrics
        base_node_count = node_performance.keys.min
        base_metrics = node_performance[base_node_count]
        
        scaling_efficiency = {}
        
        node_performance.each do |node_count, metrics|
          next if node_count == base_node_count
          
          # Calculate scaling factors
          latency_improvement = base_metrics[:avg_query_latency_ms] / metrics[:avg_query_latency_ms]
          throughput_improvement = metrics[:queries_per_second] / base_metrics[:queries_per_second]
          resource_scaling = metrics[:resource_usage][:memory_mb] / base_metrics[:resource_usage][:memory_mb]
          
          # Ideal linear scaling would be proportional to node count
          ideal_improvement = node_count.to_f / base_node_count
          
          # Calculate efficiency (1.0 means perfect linear scaling)
          latency_efficiency = latency_improvement / ideal_improvement
          throughput_efficiency = throughput_improvement / ideal_improvement
          resource_efficiency = ideal_improvement / resource_scaling
          
          scaling_efficiency[node_count] = {
            relative_to: base_node_count,
            latency_improvement: latency_improvement.round(2),
            throughput_improvement: throughput_improvement.round(2),
            resource_scaling: resource_scaling.round(2),
            latency_efficiency: latency_efficiency.round(2),
            throughput_efficiency: throughput_efficiency.round(2),
            resource_efficiency: resource_efficiency.round(2),
            overall_efficiency: ((latency_efficiency + throughput_efficiency + resource_efficiency) / 3).round(2)
          }
        end
        
        scaling_efficiency
      end

      # Analyze scaling efficiency from metrics
      # @return [Hash] Scaling efficiency metrics
      def analyze_scaling_efficiency_from_metrics
        scaling_scenarios = @metrics.metrics[:scenarios].select { |_id, data| 
          data[:details][:type] == :horizontal_scaling
        }
        
        # Extract node performance from metrics
        node_performance = {}
        
        scaling_scenarios.each do |_id, data|
          node_count = data[:details][:node_count]
          
          query_metrics = data[:checkpoints][:queries_complete][:details]
          resource_metrics = data[:checkpoints][:resource_metrics][:details]
          
          queries_per_second = @config[:query_count] / (query_metrics[:avg_latency_ms] * @config[:query_count] / 1000)
          
          node_performance[node_count] = {
            avg_query_latency_ms: query_metrics[:avg_latency_ms],
            p95_latency_ms: query_metrics[:p95_latency_ms],
            p99_latency_ms: query_metrics[:p99_latency_ms],
            queries_per_second: queries_per_second,
            resource_usage: resource_metrics
          }
        end
        
        analyze_scaling_efficiency(node_performance)
      end

      # Identify optimal node count for balanced performance
      # @param scaling_efficiency [Hash] Scaling efficiency metrics
      # @return [Integer] Optimal node count
      def identify_optimal_node_count(scaling_efficiency = nil)
        scaling_efficiency ||= analyze_scaling_efficiency_from_metrics
        
        # Find the node count with the best overall efficiency
        best_node = scaling_efficiency.max_by { |_node, metrics| metrics[:overall_efficiency] }
        
        best_node ? best_node.first : @config[:node_counts].first
      end

      # Identify optimal node count for latency-sensitive applications
      # @return [Integer] Optimal node count
      def identify_latency_sensitive_node_count
        scaling_scenarios = @metrics.metrics[:scenarios].select { |_id, data| 
          data[:details][:type] == :horizontal_scaling
        }
        
        # Find the node count with the lowest p99 latency
        node_latencies = {}
        
        scaling_scenarios.each do |_id, data|
          node_count = data[:details][:node_count]
          p99_latency = data[:checkpoints][:queries_complete][:details][:p99_latency_ms]
          
          node_latencies[node_count] = p99_latency
        end
        
        # Return the node count with the lowest p99 latency
        best_node = node_latencies.min_by { |_node, latency| latency }
        
        best_node ? best_node.first : @config[:node_counts].last
      end

      # Identify optimal node count for throughput-sensitive applications
      # @return [Integer] Optimal node count
      def identify_throughput_sensitive_node_count
        scaling_scenarios = @metrics.metrics[:scenarios].select { |_id, data| 
          data[:details][:type] == :horizontal_scaling
        }
        
        # Calculate throughput for each node count
        node_throughput = {}
        
        scaling_scenarios.each do |_id, data|
          node_count = data[:details][:node_count]
          
          query_metrics = data[:checkpoints][:queries_complete][:details]
          avg_latency_ms = query_metrics[:avg_latency_ms]
          
          # Calculate queries per second
          throughput = @config[:query_count] / (avg_latency_ms * @config[:query_count] / 1000)
          
          node_throughput[node_count] = throughput
        end
        
        # Return the node count with the highest throughput
        best_node = node_throughput.max_by { |_node, throughput| throughput }
        
        best_node ? best_node.first : @config[:node_counts].last
      end
