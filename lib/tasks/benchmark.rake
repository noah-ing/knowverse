# frozen_string_literal: true

namespace :benchmark do
  desc "Run hybrid search benchmarks"
  task :hybrid_search, [:org_id, :query_count, :types, :providers] => :environment do |t, args|
    options = {
      organization_id: args[:org_id],
      query_count: args[:query_count] || 50,
      output_file: "tmp/benchmark/hybrid_search_benchmark.json",
      report_file: "tmp/benchmark/hybrid_search_report.md",
      verbose: true
    }
    
    # Parse query types if provided
    if args[:types].present?
      options[:query_types] = args[:types].split(',').map(&:to_sym)
    end
    
    # Parse providers if provided
    if args[:providers].present?
      options[:providers] = args[:providers].split(',').map(&:to_sym)
    end
    
    # Validate organization ID
    unless options[:organization_id].present?
      puts "ERROR: Organization ID is required"
      puts "Usage: rake benchmark:hybrid_search[org_id,query_count,types,providers]"
      exit 1
    end
    
    # Create output directories
    FileUtils.mkdir_p(File.dirname(options[:output_file]))
    FileUtils.mkdir_p(File.dirname(options[:report_file]))
    
    puts "Running hybrid search benchmark with options: #{options.inspect}"
    
    # Run the benchmark
    benchmark = Distributed::Benchmark::HybridSearchBenchmark.new(options)
    results = benchmark.run_all
    
    # Generate and save report
    report = benchmark.generate_report
    File.write(options[:report_file], report)
    
    puts "Benchmark complete!"
    puts "Results saved to: #{options[:output_file]}"
    puts "Report saved to: #{options[:report_file]}"
  end
  
  desc "Run all benchmarks"
  task :all => :environment do
    Rake::Task["benchmark:hybrid_search"].invoke(
      ENV['ORG_ID'],
      ENV['QUERY_COUNT'] || 50
    )
    
    # Add additional benchmarks as they are created
    # Rake::Task["benchmark:rag_performance"].invoke if defined?(Rake::Task["benchmark:rag_performance"])
  end
end

# Create a shorter alias for convenience
namespace :bench do
  desc "Run hybrid search benchmarks (alias)"
  task :hybrid, [:org_id, :query_count, :types, :providers] => "benchmark:hybrid_search"
  
  desc "Run all benchmarks (alias)"
  task :all => "benchmark:all"
end
