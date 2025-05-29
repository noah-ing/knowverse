# frozen_string_literal: true

module Distributed
  module Benchmark
    # Performance benchmarking framework for the distributed system
    class PerformanceBenchmark
      attr_reader :results, :options
      
      # Initialize a new benchmark with options
      # @param options [Hash] Benchmark configuration options
      def initialize(options = {})
        @options = {
          cluster_size: options[:cluster_size] || 3,
          vector_count: options[:vector_count] || 100_000,
          query_count: options[:query_count] || 1_000,
          organization_count: options[:organization_count] || 5,
          dimensions: options[:dimensions] || [384, 1536],
          output_file: options[:output_file],
          verbose: options[:verbose] || true
        }
        
        @results = {
          config: @options.dup,
          latency: {},
          throughput: {},
          memory: {},
          sharding: {}
        }
        
        @test_data = nil
      end
      
      # Run all benchmark tests
      # @return [Hash] Benchmark results
      def run_all
        setup_test_data
        
        run_latency_benchmark
        run_throughput_benchmark
        run_memory_benchmark
        run_sharding_benchmark
        
        save_results if @options[:output_file]
        
        @results
      end
      
      # Run latency benchmark tests
      # @return [Hash] Latency benchmark results
      def run_latency_benchmark
        log "Running latency benchmark with #{@options[:query_count]} queries..."
        
        latency_results = {
          single_node: {},
          distributed: {},
          dimensions: {}
        }
        
        # Generate random query vectors
        query_vectors = generate_query_vectors
        
        # Measure single node latency
        latency_results[:single_node] = measure_single_node_latency(query_vectors)
        
        # Measure distributed latency
        latency_results[:distributed] = measure_distributed_latency(query_vectors)
        
        # Measure latency for different dimensions
        @options[:dimensions].each do |dim|
          latency_results[:dimensions][dim] = measure_dimension_latency(dim, query_vectors)
        end
        
        @results[:latency] = latency_results
        latency_results
      end
      
      # Run throughput benchmark tests
      # @return [Hash] Throughput benchmark results
      def run_throughput_benchmark
        log "Running throughput benchmark..."
        
        throughput_results = {
          single_node: {},
          distributed: {},
          concurrent_users: {}
        }
        
        # Measure maximum single node throughput
        throughput_results[:single_node] = measure_single_node_throughput
        
        # Measure maximum distributed throughput
        throughput_results[:distributed] = measure_distributed_throughput
        
        # Measure throughput with concurrent users
        [1, 5, 10, 25, 50, 100].each do |concurrent|
          throughput_results[:concurrent_users][concurrent] = measure_concurrent_throughput(concurrent)
        end
        
        @results[:throughput] = throughput_results
        throughput_results
      end
      
      # Run memory usage benchmark tests
      # @return [Hash] Memory usage benchmark results
      def run_memory_benchmark
        log "Running memory usage benchmark..."
        
        memory_results = {
          per_vector: {},
          per_organization: {},
          total_usage: {}
        }
        
        # Measure memory per vector
        @options[:dimensions].each do |dim|
          memory_results[:per_vector][dim] = measure_memory_per_vector(dim)
        end
        
        # Measure memory per organization
        test_organizations.each do |org|
          memory_results[:per_organization][org.id] = measure_organization_memory(org)
        end
        
        # Measure total memory usage
        memory_results[:total_usage] = measure_total_memory
        
        @results[:memory] = memory_results
        memory_results
      end
      
      # Run sharding benchmark tests
      # @return [Hash] Sharding benchmark results
      def run_sharding_benchmark
        log "Running sharding benchmark..."
        
        sharding_results = {
          distribution: {},
          rebalancing: {},
          hot_spots: {}
        }
        
        # Measure shard distribution
        sharding_results[:distribution] = measure_shard_distribution
        
        # Measure rebalancing time
        sharding_results[:rebalancing] = measure_rebalancing_time
        
        # Identify hot spots
        sharding_results[:hot_spots] = identify_hot_spots
        
        @results[:sharding] = sharding_results
        sharding_results
      end
      
      # Save benchmark results to file
      # @param file_path [String] Path to save results (defaults to options[:output_file])
      # @return [Boolean] Success status
      def save_results(file_path = nil)
        file_path ||= @options[:output_file]
        return false unless file_path
        
        # Format timestamp
        timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
        
        # Use the provided path or generate one with timestamp
        actual_path = file_path.include?('.json') ? file_path : "#{file_path}_#{timestamp}.json"
        
        # Ensure directory exists
        FileUtils.mkdir_p(File.dirname(actual_path))
        
        # Add summary metrics
        @results[:summary] = {
          avg_latency_ms: average_latency,
          max_throughput_qps: max_throughput,
          memory_per_1m_vectors_mb: memory_per_million,
          p95_latency_ms: percentile_latency(95),
          p99_latency_ms: percentile_latency(99),
          sharding_balance_score: sharding_balance_score,
          rebalancing_time_ms: avg_rebalancing_time
        }
        
        # Add timestamp
        @results[:timestamp] = timestamp
        
        # Write results to file
        File.write(actual_path, JSON.pretty_generate(@results))
        
        log "Results saved to #{actual_path}"
        true
      end
      
      # Generate a report of benchmark results
      # @return [String] Markdown-formatted report
      def generate_report
        report = "# KnowVerse Distributed System Performance Report\n\n"
        report += "## Configuration\n\n"
        
        report += "- **Cluster Size**: #{@options[:cluster_size]} nodes\n"
        report += "- **Vector Count**: #{@options[:vector_count]} vectors\n"
        report += "- **Query Count**: #{@options[:query_count]} queries\n"
        report += "- **Organization Count**: #{@options[:organization_count]} organizations\n"
        report += "- **Dimensions Tested**: #{@options[:dimensions].join(', ')}\n\n"
        
        report += "## Summary\n\n"
        
        if @results[:summary]
          report += "- **Average Query Latency**: #{@results[:summary][:avg_latency_ms].round(2)}ms\n"
          report += "- **P95 Latency**: #{@results[:summary][:p95_latency_ms].round(2)}ms\n"
          report += "- **P99 Latency**: #{@results[:summary][:p99_latency_ms].round(2)}ms\n"
          report += "- **Maximum Throughput**: #{@results[:summary][:max_throughput_qps].round(2)} queries per second\n"
          report += "- **Memory per Million Vectors**: #{@results[:summary][:memory_per_1m_vectors_mb].round(2)} MB\n"
          report += "- **Sharding Balance Score**: #{(@results[:summary][:sharding_balance_score] * 100).round(2)}%\n"
          report += "- **Average Rebalancing Time**: #{@results[:summary][:rebalancing_time_ms].round(2)}ms\n\n"
        end
        
        report += "## Latency Results\n\n"
        
        if @results[:latency][:distributed]
          report += "### Distributed vs Single-Node Latency\n\n"
          report += "| Configuration | Average (ms) | P95 (ms) | P99 (ms) | Min (ms) | Max (ms) |\n"
          report += "|--------------|-------------|----------|----------|----------|----------|\n"
          
          single = @results[:latency][:single_node]
          dist = @results[:latency][:distributed]
          
          report += "| Single Node | #{single[:avg]&.round(2)} | #{single[:p95]&.round(2)} | #{single[:p99]&.round(2)} | #{single[:min]&.round(2)} | #{single[:max]&.round(2)} |\n"
          report += "| Distributed | #{dist[:avg]&.round(2)} | #{dist[:p95]&.round(2)} | #{dist[:p99]&.round(2)} | #{dist[:min]&.round(2)} | #{dist[:max]&.round(2)} |\n\n"
        end
        
        if @results[:latency][:dimensions] && !@results[:latency][:dimensions].empty?
          report += "### Latency by Vector Dimensions\n\n"
          report += "| Dimensions | Average (ms) | P95 (ms) | P99 (ms) |\n"
          report += "|-----------|-------------|----------|----------|\n"
          
          @results[:latency][:dimensions].each do |dim, metrics|
            report += "| #{dim} | #{metrics[:avg]&.round(2)} | #{metrics[:p95]&.round(2)} | #{metrics[:p99]&.round(2)} |\n"
          end
          report += "\n"
        end
        
        report += "## Throughput Results\n\n"
        
        if @results[:throughput][:concurrent_users] && !@results[:throughput][:concurrent_users].empty?
          report += "### Throughput by Concurrent Users\n\n"
          report += "| Concurrent Users | Queries per Second | Latency (ms) |\n"
          report += "|------------------|-------------------|-------------|\n"
          
          @results[:throughput][:concurrent_users].each do |users, metrics|
            report += "| #{users} | #{metrics[:qps]&.round(2)} | #{metrics[:latency_ms]&.round(2)} |\n"
          end
          report += "\n"
        end
        
        report += "## Memory Usage\n\n"
        
        if @results[:memory][:per_vector] && !@results[:memory][:per_vector].empty?
          report += "### Memory Usage by Vector Dimensions\n\n"
          report += "| Dimensions | Memory per Vector (bytes) | Memory per 1M Vectors (MB) |\n"
          report += "|-----------|--------------------------|----------------------------|\n"
          
          @results[:memory][:per_vector].each do |dim, bytes|
            mb_per_million = (bytes * 1_000_000) / (1024 * 1024)
            report += "| #{dim} | #{bytes.round(2)} | #{mb_per_million.round(2)} |\n"
          end
          report += "\n"
        end
        
        report += "## Sharding Metrics\n\n"
        
        if @results[:sharding][:distribution] && !@results[:sharding][:distribution].empty?
          report += "### Shard Distribution\n\n"
          report += "| Node | Organizations | Vectors | Memory (MB) |\n"
          report += "|------|---------------|---------|-------------|\n"
          
          @results[:sharding][:distribution].each do |node, metrics|
            report += "| #{node} | #{metrics[:organization_count]} | #{metrics[:vector_count]} | #{metrics[:memory_mb]&.round(2)} |\n"
          end
          report += "\n"
        end
        
        if @results[:sharding][:rebalancing] && !@results[:sharding][:rebalancing].empty?
          report += "### Rebalancing Performance\n\n"
          report += "| Scenario | Time (ms) | Vectors Moved | Final Balance Score |\n"
          report += "|----------|-----------|--------------|---------------------|\n"
          
          @results[:sharding][:rebalancing].each do |scenario, metrics|
            report += "| #{scenario} | #{metrics[:time_ms]&.round(2)} | #{metrics[:vectors_moved]} | #{(metrics[:balance_score] * 100).round(2)}% |\n"
          end
          report += "\n"
        end
        
        report
      end
      
      private
      
      # Set up test data for benchmarking
      def setup_test_data
        return @test_data if @test_data
        
        log "Setting up test data with #{@options[:vector_count]} vectors across #{@options[:organization_count]} organizations..."
        
        # Calculate vectors per organization
        vectors_per_org = @options[:vector_count] / @options[:organization_count]
        
        # Generate test cluster with specified configuration
        @test_data = VectorGenerator.generate_test_cluster(
          @options[:cluster_size],
          @options[:organization_count],
          vectors_per_org
        )
        
        log "Test data setup complete. Generated #{@test_data[:total_documents]} documents across #{@test_data[:organizations].size} organizations."
        
        @test_data
      end
      
      # Generate random query vectors for benchmarking
      def generate_query_vectors
        dim = @options[:dimensions].max
        VectorGenerator.random_vectors(@options[:query_count], dim)
      end
      
      # Get test organizations
      def test_organizations
        setup_test_data[:organizations]
      end
      
      # Measure latency for single node queries
      def measure_single_node_latency(query_vectors)
        log "Measuring single node latency..."
        
        # Configure system for single node operation
        original_config = toggle_distributed_mode(false)
        
        latencies = []
        organization = test_organizations.first
        dimension = @options[:dimensions].first
        
        # Measure query latency
        query_vectors.each_with_index do |vector, i|
          log "Running single node query #{i + 1}/#{query_vectors.size}..." if (i % 100 == 0)
          
          start_time = Time.now
          
          # Execute search using non-distributed mode
          results = search_single_node(vector, organization.id, dimension)
          
          end_time = Time.now
          latency_ms = (end_time - start_time) * 1000
          
          latencies << latency_ms
        end
        
        # Restore original configuration
        restore_configuration(original_config)
        
        # Calculate statistics
        calculate_latency_stats(latencies)
      end
      
      # Measure latency for distributed queries
      def measure_distributed_latency(query_vectors)
        log "Measuring distributed latency..."
        
        # Configure system for distributed operation
        original_config = toggle_distributed_mode(true)
        
        latencies = []
        organization = test_organizations.first
        dimension = @options[:dimensions].first
        
        # Measure query latency
        query_vectors.each_with_index do |vector, i|
          log "Running distributed query #{i + 1}/#{query_vectors.size}..." if (i % 100 == 0)
          
          start_time = Time.now
          
          # Execute search using distributed mode
          results = search_distributed(vector, organization.id, dimension)
          
          end_time = Time.now
          latency_ms = (end_time - start_time) * 1000
          
          latencies << latency_ms
        end
        
        # Restore original configuration
        restore_configuration(original_config)
        
        # Calculate statistics
        calculate_latency_stats(latencies)
      end
      
      # Measure latency for specific dimension
      def measure_dimension_latency(dimension, query_vectors)
        log "Measuring latency for #{dimension} dimensions..."
        
        # Configure system for distributed operation
        original_config = toggle_distributed_mode(true)
        
        latencies = []
        organization = test_organizations.first
        
        # Use appropriate number of dimensions from query vectors
        dim_vectors = query_vectors.map { |v| v.take(dimension) }
        
        # Measure query latency
        dim_vectors.each_with_index do |vector, i|
          log "Running #{dimension}d query #{i + 1}/#{dim_vectors.size}..." if (i % 100 == 0)
          
          start_time = Time.now
          
          # Execute search using distributed mode
          results = search_distributed(vector, organization.id, dimension)
          
          end_time = Time.now
          latency_ms = (end_time - start_time) * 1000
          
          latencies << latency_ms
        end
        
        # Restore original configuration
        restore_configuration(original_config)
        
        # Calculate statistics
        calculate_latency_stats(latencies)
      end
      
      # Measure single node throughput
      def measure_single_node_throughput
        log "Measuring single node throughput..."
        
        # Configure system for single node operation
        original_config = toggle_distributed_mode(false)
        
        organization = test_organizations.first
        dimension = @options[:dimensions].first
        
        # Generate test queries
        query_vectors = VectorGenerator.random_vectors(100, dimension)
        
        # Measure maximum throughput
        throughput_result = measure_max_throughput(query_vectors, organization.id, dimension, false)
        
        # Restore original configuration
        restore_configuration(original_config)
        
        throughput_result
      end
      
      # Measure distributed throughput
      def measure_distributed_throughput
        log "Measuring distributed throughput..."
        
        # Configure system for distributed operation
        original_config = toggle_distributed_mode(true)
        
        organization = test_organizations.first
        dimension = @options[:dimensions].first
        
        # Generate test queries
        query_vectors = VectorGenerator.random_vectors(100, dimension)
        
        # Measure maximum throughput
        throughput_result = measure_max_throughput(query_vectors, organization.id, dimension, true)
        
        # Restore original configuration
        restore_configuration(original_config)
        
        throughput_result
      end
      
      # Measure throughput with concurrent users
      def measure_concurrent_throughput(concurrent_users)
        log "Measuring throughput with #{concurrent_users} concurrent users..."
        
        # Configure system for distributed operation
        original_config = toggle_distributed_mode(true)
        
        organizations = test_organizations.take([concurrent_users, test_organizations.size].min)
        dimension = @options[:dimensions].first
        
        # Generate test queries (one per user)
        query_vectors = VectorGenerator.random_vectors(concurrent_users * 10, dimension)
        
        # Measure throughput with concurrent users
        result = measure_concurrent_performance(query_vectors, organizations, dimension, concurrent_users)
        
        # Restore original configuration
        restore_configuration(original_config)
        
        result
      end
      
      # Measure memory usage per vector for a specific dimension
      def measure_memory_per_vector(dimension)
        log "Measuring memory usage for #{dimension}-dimension vectors..."
        
        # Generate a small test set
        test_vectors = VectorGenerator.random_vectors(1000, dimension)
        
        # Create a memory allocation for these vectors
        memory_before = measure_current_memory
        
        # Add vectors to a test index
        vectors_memory = create_test_index(test_vectors, dimension)
        
        # Measure memory after
        memory_after = measure_current_memory
        
        # Calculate memory per vector
        memory_delta = memory_after - memory_before
        bytes_per_vector = memory_delta / test_vectors.size
        
        log "Memory usage: #{bytes_per_vector.round(2)} bytes per #{dimension}d vector"
        
        bytes_per_vector
      end
      
      # Measure memory usage for an organization
      def measure_organization_memory(organization)
        log "Measuring memory usage for organization #{organization.id}..."
        
        # Configure system to load this organization's vectors
        service = Distributed::DistributedService.instance
        
        # Measure memory before loading
        memory_before = measure_current_memory
        
        # Load vectors for this organization
        service.distributed_index_store.load_organization(organization.id)
        
        # Measure memory after loading
        memory_after = measure_current_memory
        
        # Calculate memory usage
        memory_usage = memory_after - memory_before
        vector_count = organization.documents.count * @options[:dimensions].size
        
        {
          total_mb: memory_usage / (1024 * 1024),
          vector_count: vector_count,
          bytes_per_vector: vector_count > 0 ? (memory_usage / vector_count) : 0
        }
      end
      
      # Measure total memory usage
      def measure_total_memory
        log "Measuring total memory usage..."
        
        service = Distributed::DistributedService.instance
        
        # Unload all organizations
        service.distributed_index_store.unload_all_organizations
        
        # Measure base memory
        base_memory = measure_current_memory
        
        # Load all organizations
        test_organizations.each do |org|
          service.distributed_index_store.load_organization(org.id)
        end
        
        # Measure memory with all vectors loaded
        loaded_memory = measure_current_memory
        
        # Calculate total memory usage
        total_usage = loaded_memory - base_memory
        total_vectors = test_organizations.sum { |org| org.documents.count * @options[:dimensions].size }
        
        {
          base_mb: base_memory / (1024 * 1024),
          total_mb: total_usage / (1024 * 1024),
          vector_count: total_vectors,
          bytes_per_vector: total_vectors > 0 ? (total_usage / total_vectors) : 0
        }
      end
      
      # Measure shard distribution
      def measure_shard_distribution
        log "Measuring shard distribution..."
        
        service = Distributed::DistributedService.instance
        distribution = {}
        
        # Collect distribution data for each node
        service.cluster_nodes.each do |node|
          node_id = node.node_id
          
          # Get organizations assigned to this node
          orgs = service.sharding_manager.get_node_organizations(node_id)
          
          # Get vector count for these organizations
          vector_count = orgs.sum do |org_id|
            org = Organization.find_by(id: org_id)
            org ? org.documents.count * @options[:dimensions].size : 0
          end
          
          # Estimate memory usage
          memory_mb = (vector_count * 4 * @options[:dimensions].max) / (1024 * 1024)
          
          distribution[node_id] = {
            organization_count: orgs.size,
            vector_count: vector_count,
            memory_mb: memory_mb
          }
        end
        
        distribution
      end
      
      # Measure rebalancing time
      def measure_rebalancing_time
        log "Measuring rebalancing time..."
        
        service = Distributed::DistributedService.instance
        results = {}
        
        # Measure time to add a node
        start_time = Time.now
        service.add_node("benchmark-node-#{Time.now.to_i}")
        end_time = Time.now
        
        # Calculate rebalancing statistics
        results[:add_node] = {
          time_ms: (end_time - start_time) * 1000,
          vectors_moved: estimate_vectors_moved,
          balance_score: calculate_balance_score
        }
        
        # Measure time to remove a node
        node_to_remove = service.cluster_nodes.last.node_id
        
        start_time = Time.now
        service.remove_node(node_to_remove)
        end_time = Time.now
        
        # Calculate rebalancing statistics
        results[:remove_node] = {
          time_ms: (end_time - start_time) * 1000,
          vectors_moved: estimate_vectors_moved,
          balance_score: calculate_balance_score
        }
        
        results
      end
      
      # Identify hot spots in the cluster
      def identify_hot_spots
        log "Identifying hot spots..."
        
        service = Distributed::DistributedService.instance
        hot_spots = {}
        
        # Generate test queries that target specific organizations
        organization_queries = {}
        
        test_organizations.each do |org|
          organization_queries[org.id] = VectorGenerator.random_vectors(50, @options[:dimensions].first)
        end
        
        # Track query distribution per node
        node_query_count = Hash.new(0)
        node_processing_time = Hash.new(0)
        
        # Run queries and track which nodes handle them
        organization_queries.each do |org_id, queries|
          queries.each do |query|
            # Record which node handled this query
            node_id, processing_time = track_query_node(query, org_id)
            
            node_query_count[node_id] += 1
            node_processing_time[node_id] += processing_time
          end
        end
        
        # Calculate load distribution
        total_queries = node_query_count.values.sum
        total_time = node_processing_time.values.sum
        
        service.cluster_nodes.each do |node|
          node_id = node.node_id
          query_percentage = total_queries > 0 ? (node_query_count[node_id] * 100.0 / total_queries) : 0
          time_percentage = total_time > 0 ? (node_processing_time[node_id] * 100.0 / total_time) : 0
          
          hot_spots[node_id] = {
            query_count: node_query_count[node_id],
            query_percentage: query_percentage,
            processing_time_ms: node_processing_time[node_id],
            processing_percentage: time_percentage,
            is_hot_spot: query_percentage > (100.0 / service.cluster_nodes.size * 1.5)
          }
        end
        
        hot_spots
      end
      
      # Toggle distributed mode
      def toggle_distributed_mode(enabled)
        service = Distributed::DistributedService.instance
        original_config = {
          distributed_enabled: service.distributed_enabled?
        }
        
        if enabled
          service.enable_distributed_mode if !service.distributed_enabled?
        else
          service.disable_distributed_mode if service.distributed_enabled?
        end
        
        original_config
      end
      
      # Restore previous configuration
      def restore_configuration(config)
        service = Distributed::DistributedService.instance
        
        if config[:distributed_enabled]
          service.enable_distributed_mode
        else
          service.disable_distributed_mode
        end
      end
      
      # Execute search on single node
      def search_single_node(vector, organization_id, dimension)
        service = Distributed::WebassemblySearchService.instance
        service.search(vector, organization_id, 10)
      end
      
      # Execute search on distributed system
      def search_distributed(vector, organization_id, dimension)
        service = Distributed::DistributedSearchService.instance
        service.search(vector, organization_id, 10)
      end
      
      # Calculate latency statistics
      def calculate_latency_stats(latencies)
        return { count: 0 } if latencies.empty?
        
        sorted = latencies.sort
        
        {
          count: latencies.size,
          min: latencies.min,
          max: latencies.max,
          avg: latencies.sum / latencies.size,
          median: sorted[sorted.size / 2],
          p95: sorted[(sorted.size * 0.95).floor],
          p99: sorted[(sorted.size * 0.99).floor],
          stddev: standard_deviation(latencies)
        }
      end
      
      # Calculate standard deviation
      def standard_deviation(values)
        return 0 if values.empty?
        
        mean = values.sum / values.size
        sum_squares = values.sum { |x| (x - mean) ** 2 }
        Math.sqrt(sum_squares / values.size)
      end
      
      # Measure maximum throughput
      def measure_max_throughput(query_vectors, organization_id, dimension, distributed)
        search_fn = distributed ? method(:search_distributed) : method(:search_single_node)
        
        # Start with 1 QPS and double until latency exceeds threshold
        qps = 1
        max_qps = 0
        max_latency_ms = 0
        
        loop do
          # Calculate delay between queries for desired QPS
          delay_seconds = 1.0 / qps
          
          # Run queries at this rate
          latencies = []
          
          10.times do |i|
            vector = query_vectors[i % query_vectors.size]
            
            start_time = Time.now
            search_fn.call(vector, organization_id, dimension)
            end_time = Time.now
            
            latency_ms = (end_time - start_time) * 1000
            latencies << latency_ms
            
            # Sleep to maintain desired QPS
            elapsed = Time.now - start_time
            sleep([delay_seconds - elapsed, 0].max)
          end
          
          # Calculate average latency
          avg_latency = latencies.sum / latencies.size
          
          log "Tested #{qps} QPS with average latency of #{avg_latency.round(2)}ms"
          
          # If latency is too high, we've found the limit
          if avg_latency > 100 # 100ms threshold
            break
          end
          
          # Update maximum QPS
          max_qps = qps
          max_latency_ms = avg_latency
          
          # Double QPS for next iteration
          qps *= 2
        end
        
        # Fine-tune by binary search
        low_qps = max_qps
        high_qps = max_qps * 2
        
        5.times do
          mid_qps = (low_qps + high_qps) / 2
          
          # Calculate delay between queries for desired QPS
          delay_seconds = 1.0 / mid_qps
          
          # Run queries at this rate
          latencies = []
          
          10.times do |i|
            vector = query_vectors[i % query_vectors.size]
            
            start_time = Time.now
            search_fn.call(vector, organization_id, dimension)
            end_time = Time.now
            
            latency_ms = (end_time - start_time) * 1000
            lat
