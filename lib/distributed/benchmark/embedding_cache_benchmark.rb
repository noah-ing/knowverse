#!/usr/bin/env ruby
# Benchmark script for measuring the performance impact of the Two-Tier Embedding Cache
#
# Usage: bin/rails runner lib/distributed/benchmark/embedding_cache_benchmark.rb [options]
#
# Options:
#   --organization=ID   Organization ID to use for testing
#   --iterations=N      Number of iterations for each test (default: 100)
#   --queries=N         Number of unique queries to test (default: 20)
#   --clear-cache       Clear cache before running tests
#   --cache-only        Test only with cache enabled
#   --no-cache-only     Test only with cache disabled
#   --domain=NAME       Specific domain to test with
#   --debug             Show detailed debug information
#
# Example:
#   bin/rails runner lib/distributed/benchmark/embedding_cache_benchmark.rb --organization=1 --iterations=50

require 'benchmark'
require 'optparse'
require 'csv'
require 'securerandom'

# Parse command line options
options = {
  organization_id: nil,
  iterations: 100,
  queries: 20,
  clear_cache: false,
  cache_only: false,
  no_cache_only: false,
  domain: nil,
  debug: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: bin/rails runner lib/distributed/benchmark/embedding_cache_benchmark.rb [options]"
  
  opts.on("--organization=ID", Integer, "Organization ID to use for testing") do |id|
    options[:organization_id] = id
  end
  
  opts.on("--iterations=N", Integer, "Number of iterations for each test") do |n|
    options[:iterations] = n
  end
  
  opts.on("--queries=N", Integer, "Number of unique queries to test") do |n|
    options[:queries] = n
  end
  
  opts.on("--clear-cache", "Clear cache before running tests") do
    options[:clear_cache] = true
  end
  
  opts.on("--cache-only", "Test only with cache enabled") do
    options[:cache_only] = true
  end
  
  opts.on("--no-cache-only", "Test only with cache disabled") do
    options[:no_cache_only] = true
  end
  
  opts.on("--domain=NAME", String, "Specific domain to test with") do |domain|
    options[:domain] = domain
  end
  
  opts.on("--debug", "Show detailed debug information") do
    options[:debug] = true
  end
  
  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Validate options
if options[:organization_id].nil?
  # Try to get a random organization if not specified
  organization = Organization.first
  if organization
    options[:organization_id] = organization.id
    puts "Using organization: #{organization.name} (ID: #{organization.id})"
  else
    puts "Error: No organization ID specified and no organizations found"
    exit 1
  end
end

# Check for conflicting options
if options[:cache_only] && options[:no_cache_only]
  puts "Error: Cannot specify both --cache-only and --no-cache-only"
  exit 1
end

# Initialize the cache manager
cache_manager = EmbeddingCache::CacheManager.instance

# Clear cache if requested
if options[:clear_cache]
  puts "Clearing cache for organization #{options[:organization_id]}..."
  cache_manager.clear_organization(options[:organization_id])
  sleep 1 # Give Redis a moment
end

# Generate test queries
puts "Generating #{options[:queries]} test queries..."
test_queries = if options[:domain].present?
  # Use domain-specific queries if domain is specified
  queries = []
  organization = Organization.find(options[:organization_id])
  
  # Try to get real queries for this domain from search history
  domain_queries = SearchQuery.joins(:search_feedbacks)
                            .where(organization_id: options[:organization_id])
                            .where("text LIKE ?", "%#{options[:domain]}%")
                            .limit(options[:queries])
                            .pluck(:text)
                            .uniq
  
  if domain_queries.size >= options[:queries]
    queries = domain_queries.sample(options[:queries])
  else
    # Generate some synthetic queries if not enough real ones
    domain_words = options[:domain].split(/[_\s-]/).map(&:downcase)
    
    # Add some real queries if available
    queries = domain_queries
    
    # Fill in with synthetic queries
    while queries.size < options[:queries]
      # Generate a query with domain-specific terms
      word_count = rand(1..5)
      words = []
      word_count.times do
        if rand < 0.7 && domain_words.any?
          words << domain_words.sample
        else
          words << ['what', 'how', 'why', 'when', 'explain', 'describe', 'find', 'tell', 'show'].sample
        end
      end
      
      queries << words.join(' ')
    end
  end
  
  queries
else
  # Use general queries if no domain specified
  recent_queries = SearchQuery.where(organization_id: options[:organization_id])
                           .order(created_at: :desc)
                           .limit(options[:queries] * 2)
                           .pluck(:text)
                           .uniq
  
  if recent_queries.size >= options[:queries]
    recent_queries.sample(options[:queries])
  else
    # Generate random queries if not enough real ones
    queries = recent_queries
    
    # Fill in with random queries
    while queries.size < options[:queries]
      queries << "benchmark test query #{SecureRandom.hex(4)}"
    end
    
    queries
  end
end

puts "Test queries ready. Starting benchmark..."

# Run benchmarks
results = {
  with_cache: [],
  without_cache: []
}

# Array to store detailed timing information if debug is enabled
debug_info = []

# Test with cache enabled (unless --no-cache-only specified)
unless options[:no_cache_only]
  puts "\nRunning benchmark with cache enabled:"
  puts "-" * 40
  
  # Warm up cache first
  puts "  Warming cache..."
  test_queries.each do |query|
    # Warm cache with each query
    client = HaystackClient.new
    client.generate_embeddings(
      query,
      organization_id: options[:organization_id],
      domain: options[:domain],
      use_cache: true
    )
  end
  
  # Run actual benchmark with cache
  puts "  Running #{options[:iterations]} iterations of #{options[:queries]} queries..."
  results[:with_cache] = Benchmark.measure do
    options[:iterations].times do |i|
      test_queries.each_with_index do |query, q|
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        # Use cache for this test
        client = HaystackClient.new
        embedding = client.generate_embeddings(
          query,
          organization_id: options[:organization_id],
          domain: options[:domain],
          use_cache: true
        )
        
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration_ms = (end_time - start_time) * 1000
        
        if options[:debug]
          debug_info << {
            iteration: i,
            query_idx: q,
            query: query,
            cache: 'enabled',
            duration_ms: duration_ms
          }
        end
      end
      
      print "." if i % 10 == 0
    end
  end
  puts "\n  Done."
end

# Test with cache disabled (unless --cache-only specified)
unless options[:cache_only]
  puts "\nRunning benchmark with cache disabled:"
  puts "-" * 40
  
  # Run benchmark without cache
  puts "  Running #{options[:iterations]} iterations of #{options[:queries]} queries..."
  results[:without_cache] = Benchmark.measure do
    options[:iterations].times do |i|
      test_queries.each_with_index do |query, q|
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        # Disable cache for this test
        client = HaystackClient.new
        embedding = client.generate_embeddings(
          query,
          organization_id: options[:organization_id],
          domain: options[:domain],
          use_cache: false
        )
        
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration_ms = (end_time - start_time) * 1000
        
        if options[:debug]
          debug_info << {
            iteration: i,
            query_idx: q,
            query: query,
            cache: 'disabled',
            duration_ms: duration_ms
          }
        end
      end
      
      print "." if i % 10 == 0
    end
  end
  puts "\n  Done."
end

# Display results
puts "\nBenchmark Results:"
puts "=" * 60

total_tests = options[:iterations] * options[:queries]

if results[:with_cache].present? && results[:without_cache].present?
  cache_time = results[:with_cache].real
  no_cache_time = results[:without_cache].real
  
  cache_per_query = cache_time / total_tests * 1000
  no_cache_per_query = no_cache_time / total_tests * 1000
  
  speedup = no_cache_time / cache_time
  savings_percent = (1 - (cache_time / no_cache_time)) * 100
  
  puts "Total tests run: #{total_tests} queries"
  puts "-" * 60
  puts "With cache enabled:"
  puts "  Total time: #{cache_time.round(3)} seconds"
  puts "  Average time per query: #{cache_per_query.round(3)} ms"
  puts
  puts "With cache disabled:"
  puts "  Total time: #{no_cache_time.round(3)} seconds"
  puts "  Average time per query: #{no_cache_per_query.round(3)} ms"
  puts
  puts "Performance improvement:"
  puts "  Speedup factor: #{speedup.round(2)}x"
  puts "  Time savings: #{savings_percent.round(2)}%"
  puts "  Absolute time saved: #{(no_cache_time - cache_time).round(3)} seconds"
elsif results[:with_cache].present?
  cache_time = results[:with_cache].real
  cache_per_query = cache_time / total_tests * 1000
  
  puts "Total tests run: #{total_tests} queries"
  puts "-" * 60
  puts "With cache enabled:"
  puts "  Total time: #{cache_time.round(3)} seconds"
  puts "  Average time per query: #{cache_per_query.round(3)} ms"
else
  no_cache_time = results[:without_cache].real
  no_cache_per_query = no_cache_time / total_tests * 1000
  
  puts "Total tests run: #{total_tests} queries"
  puts "-" * 60
  puts "With cache disabled:"
  puts "  Total time: #{no_cache_time.round(3)} seconds"
  puts "  Average time per query: #{no_cache_per_query.round(3)} ms"
end

# Get cache statistics after benchmark (only if cache was used)
unless options[:no_cache_only]
  puts "\nCache Statistics:"
  puts "-" * 60
  
  stats = cache_manager.stats
  org_stats = cache_manager.organization_stats(options[:organization_id])
  
  # Overall cache stats
  puts "Overall hit rate: #{(stats[:analytics][:hit_rate] * 100).round(2)}%"
  puts "Memory tier hit rate: #{(stats[:analytics][:memory_hit_rate] * 100).round(2)}%"
  puts "Redis tier hit rate: #{(stats[:analytics][:redis_hit_rate] * 100).round(2)}%"
  puts
  
  # Organization-specific stats
  puts "Organization hit rate: #{(org_stats[:analytics][:hit_rate] * 100).round(2)}%"
  puts "Memory entries: #{org_stats[:memory][:size]}"
  puts "Redis entries: #{org_stats[:redis][:size]}"
  
  # Domain-specific stats if applicable
  if options[:domain].present? && org_stats[:analytics][:domains].present? && 
     org_stats[:analytics][:domains][options[:domain]].present?
    
    domain_stats = org_stats[:analytics][:domains][options[:domain]]
    puts "\nDomain '#{options[:domain]}' hit rate: #{(domain_stats[:hit_rate] * 100).round(2)}%"
    puts "Domain entries: #{domain_stats[:total_requests]}"
  end
end

# Save debug information to CSV if requested
if options[:debug]
  csv_filename = "embedding_cache_benchmark_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
  puts "\nSaving detailed debug information to: #{csv_filename}"
  
  CSV.open(csv_filename, "w") do |csv|
    # Write header
    csv << ["iteration", "query_index", "query", "cache", "duration_ms"]
    
    # Write data
    debug_info.each do |info|
      csv << [info[:iteration], info[:query_idx], info[:query], info[:cache], info[:duration_ms]]
    end
  end
end

puts "\nBenchmark completed."
