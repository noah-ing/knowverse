# frozen_string_literal: true

require 'fileutils'

namespace :distributed do
  namespace :test do
    desc "Run load tests for distributed architecture"
    task load: :environment do
      puts "Starting load tests for distributed architecture..."
      
      # Configure load test options from ENV variables
      options = {
        node_counts: ENV['DISTRIBUTED_NODE_COUNT'] ? ENV['DISTRIBUTED_NODE_COUNT'].split(',').map(&:to_i) : [2, 4, 8, 16],
        vector_count: (ENV['VECTOR_COUNT'] || 10_000).to_i,
        query_count: (ENV['QUERY_COUNT'] || 1000).to_i,
        test_scenarios: ENV['TEST_SCENARIOS'] ? ENV['TEST_SCENARIOS'].split(',').map(&:to_sym) : 
                         [:horizontal_scaling, :node_failure_recovery, :cross_node_query_performance, :multi_tenant_isolation],
        organization_count: (ENV['ORG_COUNT'] || 5).to_i,
        verbose: ENV['VERBOSE'] == 'true',
        output_file: ENV['OUTPUT_FILE']
      }
      
      # Create the reports directory if it doesn't exist
      FileUtils.mkdir_p(Rails.root.join('tmp', 'reports'))
      
      # Set default output file if not specified
      options[:output_file] ||= Rails.root.join('tmp', 'reports', "load_test_report_#{Time.now.strftime('%Y%m%d_%H%M%S')}.md")
      
      puts "Running load test with options:"
      puts "- Node counts: #{options[:node_counts].join(', ')}"
      puts "- Vector count: #{options[:vector_count]}"
      puts "- Query count: #{options[:query_count]}"
      puts "- Test scenarios: #{options[:test_scenarios].join(', ')}"
      puts "- Organization count: #{options[:organization_count]}"
      puts "- Output file: #{options[:output_file]}"
      
      # Run load test
      test = Distributed::Testing::DistributedLoadTest.new(options)
      results = test.run
      
      # Generate and save report
      report = test.generate_report
      File.write(options[:output_file], report)
      
      puts "\nLoad test completed."
      puts "Report generated at: #{options[:output_file]}"
      
      if ENV['DISPLAY_REPORT'] == 'true'
        puts "\n--- LOAD TEST REPORT ---\n\n"
        puts report
      end
    end
    
    desc "Run horizontal scaling tests only"
    task scaling: :environment do
      ENV['TEST_SCENARIOS'] = 'horizontal_scaling'
      Rake::Task['distributed:test:load'].invoke
    end
    
    desc "Run failure recovery tests only"
    task recovery: :environment do
      ENV['TEST_SCENARIOS'] = 'node_failure_recovery'
      Rake::Task['distributed:test:load'].invoke
    end
    
    desc "Run multi-tenant isolation tests only"
    task multi_tenant: :environment do
      ENV['TEST_SCENARIOS'] = 'multi_tenant_isolation'
      Rake::Task['distributed:test:load'].invoke
    end
    
    desc "Run cross-node query performance tests only"
    task cross_node: :environment do
      ENV['TEST_SCENARIOS'] = 'cross_node_query_performance'
      Rake::Task['distributed:test:load'].invoke
    end
    
    desc "Run a quick load test with minimal settings"
    task quick_load: :environment do
      ENV['VECTOR_COUNT'] = '1000'
      ENV['QUERY_COUNT'] = '100'
      ENV['DISTRIBUTED_NODE_COUNT'] = '2,4'
      Rake::Task['distributed:test:load'].invoke
    end
    
    desc "Run fault tolerance tests for the distributed architecture"
    task fault_tolerance: :environment do
      puts "Starting fault tolerance tests for distributed architecture..."
      
      ENV['RAILS_ENV'] = 'test' unless ENV['RAILS_ENV']
      ENV['SKIP_ACTIVE_RECORD_SCHEMA_CHECK'] = 'true'
      
      # Run the RSpec tests
      require 'rspec/core'
      
      puts "Running tests with #{ENV['DISTRIBUTED_NODE_COUNT'] || 5} nodes"
      result = RSpec::Core::Runner.run(['spec/services/distributed/fault_tolerance_spec.rb'])
      
      # Generate report path
      report_path = Rails.root.join('tmp', 'fault_tolerance_report.md')
      
      if File.exist?(report_path)
        puts "Fault tolerance report generated at: #{report_path}"
        
        # Optionally, display the report
        if ENV['DISPLAY_REPORT']
          puts "\n--- FAULT TOLERANCE REPORT ---\n\n"
          puts File.read(report_path)
        end
      end
      
      exit result unless result.zero?
    end
    
    desc "Run performance benchmarks for the distributed architecture"
    task performance: :environment do
      puts "Starting performance benchmarks for distributed architecture..."
      
      # Create the benchmark directory
      FileUtils.mkdir_p(Rails.root.join('tmp', 'benchmarks'))
      
      # Configure benchmark options
      options = {
        cluster_size: (ENV['DISTRIBUTED_NODE_COUNT'] || 3).to_i,
        vector_count: (ENV['VECTOR_COUNT'] || 10_000).to_i,
        query_count: (ENV['QUERY_COUNT'] || 100).to_i,
        organization_count: (ENV['ORG_COUNT'] || 3).to_i,
        dimensions: ENV['DIMENSIONS'] ? ENV['DIMENSIONS'].split(',').map(&:to_i) : [384, 1536],
        output_file: Rails.root.join('tmp', 'benchmarks', 'performance_results.json')
      }
      
      puts "Running performance benchmark with options:"
      puts "- Cluster size: #{options[:cluster_size]} nodes"
      puts "- Vector count: #{options[:vector_count]} vectors"
      puts "- Query count: #{options[:query_count]} queries"
      puts "- Organization count: #{options[:organization_count]} organizations"
      puts "- Dimensions: #{options[:dimensions].join(', ')}"
      
      # Run benchmarks
      benchmark = Distributed::Benchmark::PerformanceBenchmark.new(options)
      
      # Run specific benchmark based on parameter
      case ENV['BENCHMARK_TYPE']
      when 'latency'
        puts "Running latency benchmark..."
        results = benchmark.run_latency_benchmark
      when 'throughput'
        puts "Running throughput benchmark..."
        results = benchmark.run_throughput_benchmark
      when 'memory'
        puts "Running memory usage benchmark..."
        results = benchmark.run_memory_benchmark
      when 'sharding'
        puts "Running sharding benchmark..."
        results = benchmark.run_sharding_benchmark
      else
        puts "Running all benchmarks..."
        results = benchmark.run_all
      end
      
      # Generate and display report
      report = benchmark.generate_report
      report_path = Rails.root.join('tmp', 'benchmarks', 'performance_report.md')
      File.write(report_path, report)
      
      puts "\nPerformance benchmark completed."
      puts "Results saved to: #{options[:output_file]}"
      puts "Report generated at: #{report_path}"
      
      if ENV['DISPLAY_REPORT']
        puts "\n--- PERFORMANCE BENCHMARK REPORT ---\n\n"
        puts report
      end
    end
  end
  
  namespace :simulate do
    desc "Simulate a network partition between nodes"
    task :network_partition, [:node_ids] => [:environment] do |t, args|
      require 'distributed/testing/network_simulator'
      
      node_ids = args[:node_ids]&.split(',') || []
      if node_ids.empty?
        puts "Please specify node IDs to partition, e.g. rake distributed:simulate:network_partition[node1,node2]"
        exit 1
      end
      
      puts "Simulating network partition for nodes: #{node_ids.join(', ')}"
      heal_partition = Distributed::Testing::NetworkSimulator.create_partition(node_ids)
      
      puts "Network partition created. Press Enter to heal the partition..."
      STDIN.gets
      
      heal_partition.call
      puts "Network partition healed."
    end
    
    desc "Simulate a node crash"
    task :node_crash, [:node_id] => [:environment] do |t, args|
      require 'distributed/testing/network_simulator'
      
      node_id = args[:node_id]
      if node_id.nil? || node_id.empty?
        puts "Please specify a node ID to crash, e.g. rake distributed:simulate:node_crash[node1]"
        exit 1
      end
      
      puts "Simulating crash for node: #{node_id}"
      recover_node = Distributed::Testing::NetworkSimulator.crash_node(node_id)
      
      puts "Node crashed. Press Enter to recover the node..."
      STDIN.gets
      
      recover_node.call
      puts "Node recovered."
    end
    
    desc "Simulate log corruption"
    task :log_corruption, [:node_id, :severity] => [:environment] do |t, args|
      require 'distributed/testing/network_simulator'
      
      node_id = args[:node_id]
      severity = (args[:severity] || 'moderate').to_sym
      
      if node_id.nil? || node_id.empty?
        puts "Please specify a node ID, e.g. rake distributed:simulate:log_corruption[node1,severe]"
        exit 1
      end
      
      unless [:minor, :moderate, :severe].include?(severity)
        puts "Invalid severity: #{severity}. Must be one of: minor, moderate, severe"
        exit 1
      end
      
      puts "Simulating #{severity} log corruption for node: #{node_id}"
      Distributed::Testing::NetworkSimulator.corrupt_logs(node_id, severity)
      
      puts "Logs corrupted. You may need to restart the node to see effects."
    end
    
    desc "Generate test data for benchmarking"
    task :generate_data, [:organization_count, :documents_per_org] => [:environment] do |t, args|
      require 'distributed/benchmark/vector_generator'
      
      org_count = (args[:organization_count] || 3).to_i
      docs_per_org = (args[:documents_per_org] || 1000).to_i
      
      puts "Generating test data: #{org_count} organizations with #{docs_per_org} documents each"
      
      org_count.times do |i|
        org_name = "Benchmark Org #{i + 1}"
        puts "Creating organization: #{org_name}"
        org = Distributed::Benchmark::VectorGenerator.generate_test_organization(
          org_name, 
          docs_per_org
        )
        puts "Created organization #{org.id} with #{docs_per_org} documents"
      end
      
      puts "Test data generation complete"
    end
  end
end
