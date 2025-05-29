# frozen_string_literal: true

namespace :benchmark do
  desc 'Run RAG performance benchmark tests'
  task :rag, [:org_id, :providers, :query_count] => :environment do |_t, args|
    # Get organization ID (required)
    org_id = args[:org_id]
    if org_id.nil?
      puts "Error: Organization ID is required"
      puts "Usage: rails benchmark:rag[org_id,providers,query_count]"
      exit 1
    end
    
    # Get optional parameters
    providers = args[:providers]&.split(',')&.map(&:to_sym)
    query_count = args[:query_count]&.to_i
    
    # Build options hash
    options = { 
      organization_id: org_id.to_i,
      output_file: "tmp/rag_benchmark_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
    }
    options[:providers] = providers if providers.present?
    options[:query_count] = query_count if query_count.present?
    
    # Display benchmark configuration
    puts "=" * 80
    puts "KnowVerse RAG Performance Benchmark"
    puts "=" * 80
    puts "Running with options:"
    puts "- Organization ID: #{options[:organization_id]}"
    puts "- Query count: #{options[:query_count] || 'default'}"
    if providers.present?
      puts "- Providers: #{providers.join(', ')}"
    else
      puts "- Providers: all available"
    end
    puts "- Output file: #{options[:output_file]}"
    puts "=" * 80
    
    # Create and run the benchmark
    benchmark = Distributed::Benchmark::RagPerformanceBenchmark.new(options)
    results = benchmark.run_all
    
    # Generate report
    report = benchmark.generate_report
    report_path = "#{options[:output_file]}_report.md"
    File.write(report_path, report)
    
    puts "Benchmark complete!"
    puts "Results saved to: #{options[:output_file]}_*.json"
    puts "Report saved to: #{report_path}"
  end
  
  desc 'List available RAG benchmark options'
  task :rag_options => :environment do
    puts "=" * 80
    puts "KnowVerse RAG Performance Benchmark Options"
    puts "=" * 80
    
    # Query types
    puts "Available query types:"
    Distributed::Benchmark::RagPerformanceBenchmark::QUERY_TYPES.each do |key, desc|
      puts "  - #{key}: #{desc}"
    end
    puts
    
    # Providers
    puts "Available LLM providers:"
    Distributed::Benchmark::RagPerformanceBenchmark::PROVIDERS.each do |key, name|
      puts "  - #{key}: #{name}"
    end
    puts
    
    # Context window configurations
    puts "Default context window configurations:"
    Distributed::Benchmark::RagPerformanceBenchmark::CONTEXT_WINDOW_CONFIGS.each do |config|
      puts "  - max_documents: #{config[:max_documents]}, min_similarity: #{config[:min_similarity]}"
    end
    puts
    
    puts "Usage examples:"
    puts "  - Basic: rails benchmark:rag[123]"
    puts "  - Specific providers: rails benchmark:rag[123,openai,anthropic]"
    puts "  - With query count: rails benchmark:rag[123,openai,50]"
    puts "  - Custom command: bin/rag_performance_benchmark -o 123 -p openai,anthropic -q 50 -t factoid,semantic"
    puts "=" * 80
  end
end
