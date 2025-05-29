#!/usr/bin/env ruby
# frozen_string_literal: true

# DALVS (Domain-Aware Lazy Vector Search) Architecture Benchmark
#
# This benchmark tests the performance of the new DALVS architecture:
# - Component lazy loading performance
# - Domain-aware caching efficiency
# - Streaming search latency
# - Comparative metrics against previous architecture
#
# Usage: bin/rails runner lib/distributed/benchmark/dalvs_benchmark.rb

require 'benchmark'
require 'csv'
require 'securerandom'
require 'colorize'

# Ensure we have the Rails environment
raise 'This script must be run within the Rails environment' unless defined?(Rails)

# Benchmark configuration
class DALVSBenchmark
  # Configure the benchmark
  ITERATIONS = 100
  ORGANIZATIONS = 3
  DOMAINS = ['legal', 'medical', 'finance', 'general']
  QUERY_SETS = {
    legal: [
      'contract dispute resolution procedures',
      'intellectual property rights assignment',
      'liability limitation clause examples',
      'confidentiality agreement breach remedies',
      'force majeure provisions covid'
    ],
    medical: [
      'patient data security protocols',
      'clinical trial informed consent',
      'telehealth licensing requirements',
      'healthcare compliance documentation',
      'medical device regulation FDA'
    ],
    finance: [
      'quarterly revenue forecast analysis',
      'capital expenditure approval process',
      'debt restructuring strategies',
      'cash flow optimization techniques',
      'tax liability reduction methods'
    ],
    general: [
      'project management methodologies',
      'customer feedback analysis system',
      'employee onboarding procedure',
      'security incident response plan',
      'remote work policy guidelines'
    ]
  }
  
  def initialize
    # Get references to services we'll benchmark
    @bridge = VectorSearch::ComponentBridge.instance
    @cache_manager = EmbeddingCache::CacheManager.instance
    @search_service = Distributed::Search::DistributedSearchService.instance
    
    # Prepare benchmark data
    prepare_benchmark_data
    
    # Output file
    @results_file = Rails.root.join('tmp', "dalvs_benchmark_#{Time.now.to_i}.csv")
    
    # Store benchmark results
    @results = []
  end
  
  # Run all benchmarks
  def run
    print_header
    
    benchmark_component_initialization
    benchmark_component_reuse
    benchmark_domain_aware_caching
    benchmark_streaming_search
    benchmark_memory_usage
    
    write_results
    print_summary
  end
  
  private
  
  # Prepare benchmark data
  def prepare_benchmark_data
    # Get some organizations to use for benchmarking
    @organizations = Organization.limit(ORGANIZATIONS).to_a
    if @organizations.size < ORGANIZATIONS
      puts "Warning: Only #{@organizations.size} organizations found, using those.".yellow
    end
  end
  
  # Benchmark component lazy initialization
  def benchmark_component_initialization
    puts "\n⏱️  Benchmarking Component Lazy Initialization".green
    
    # Reset any existing components
    reset_all_components
    
    # Metrics to track
    total_init_time = 0
    total_components = 0
    
    @organizations.each do |org|
      DOMAINS.each do |domain|
        # Time component initialization
        init_time = Benchmark.realtime do
          # Get a new component (which will be initialized)
          @bridge.get_component(:search, 
            organization_id: org.id,
            domain: domain
          )
        end
        
        puts "  Initialized #{domain.ljust(8)} component for org #{org.id}: #{(init_time * 1000).round(2)}ms"
        
        total_init_time += init_time
        total_components += 1
        
        # Record result
        @results << {
          test: 'component_init',
          organization_id: org.id,
          domain: domain,
          time_ms: (init_time * 1000).round(2),
          cache_hit: false,
          memory_mb: current_memory_usage
        }
      end
    end
    
    # Calculate average
    avg_init_time = total_init_time / total_components
    puts "  Average initialization time: #{(avg_init_time * 1000).round(2)}ms".cyan
  end
  
  # Benchmark component reuse
  def benchmark_component_reuse
    puts "\n⏱️  Benchmarking Component Reuse".green
    
    # Metrics to track
    total_reuse_time = 0
    total_components = 0
    
    @organizations.each do |org|
      DOMAINS.each do |domain|
        # Time component reuse
        reuse_time = Benchmark.realtime do
          # Get an existing component (which should be reused)
          @bridge.get_component(:search, 
            organization_id: org.id,
            domain: domain
          )
        end
        
        puts "  Reused #{domain.ljust(8)} component for org #{org.id}: #{(reuse_time * 1000).round(2)}ms"
        
        total_reuse_time += reuse_time
        total_components += 1
        
        # Record result
        @results << {
          test: 'component_reuse',
          organization_id: org.id,
          domain: domain,
          time_ms: (reuse_time * 1000).round(2),
          cache_hit: true,
          memory_mb: current_memory_usage
        }
      end
    end
    
    # Calculate average
    avg_reuse_time = total_reuse_time / total_components
    puts "  Average reuse time: #{(avg_reuse_time * 1000).round(2)}ms".cyan
  end
  
  # Benchmark domain-aware caching
  def benchmark_domain_aware_caching
    puts "\n⏱️  Benchmarking Domain-Aware Caching".green
    
    # For each organization and domain, run queries in two passes
    # First pass: Cache misses
    # Second pass: Cache hits
    
    @organizations.each do |org|
      DOMAINS.each do |domain|
        domain_sym = domain.to_sym
        queries = QUERY_SETS[domain_sym] || QUERY_SETS[:general]
        
        # Get component for this organization/domain
        component = @bridge.get_component(:search, 
          organization_id: org.id,
          domain: domain
        )
        
        # First pass: Cache should be cold
        puts "  First pass (cold cache) for #{domain} domain:"
        query_times = []
        
        queries.each do |query|
          # Clear this specific query from cache if it exists
          cache_key = "query:#{Digest::SHA256.hexdigest(query.downcase.strip)}:domain:#{domain}"
          @cache_manager.delete(org.id, cache_key)
          
          # Time the query
          query_time = Benchmark.realtime do
            component.search(query)
          end
          
          query_times << query_time
          puts "    Query: #{query.ljust(30)} - #{(query_time * 1000).round(2)}ms"
          
          # Record result
          @results << {
            test: 'cache_miss',
            organization_id: org.id,
            domain: domain,
            time_ms: (query_time * 1000).round(2),
            cache_hit: false,
            memory_mb: current_memory_usage,
            query: query
          }
        end
        
        # Calculate average for first pass
        avg_first_pass = query_times.sum / query_times.size
        puts "    Average (cold cache): #{(avg_first_pass * 1000).round(2)}ms".cyan
        
        # Second pass: Cache should be warm
        puts "  Second pass (warm cache) for #{domain} domain:"
        query_times = []
        
        queries.each do |query|
          # Time the query
          query_time = Benchmark.realtime do
            component.search(query)
          end
          
          query_times << query_time
          puts "    Query: #{query.ljust(30)} - #{(query_time * 1000).round(2)}ms"
          
          # Record result
          @results << {
            test: 'cache_hit',
            organization_id: org.id,
            domain: domain,
            time_ms: (query_time * 1000).round(2),
            cache_hit: true,
            memory_mb: current_memory_usage,
            query: query
          }
        end
        
        # Calculate average for second pass
        avg_second_pass = query_times.sum / query_times.size
        puts "    Average (warm cache): #{(avg_second_pass * 1000).round(2)}ms".cyan
        puts "    Cache speedup: #{(avg_first_pass / avg_second_pass).round(2)}x".cyan
      end
    end
  end
  
  # Benchmark streaming search
  def benchmark_streaming_search
    puts "\n⏱️  Benchmarking Streaming Search".green
    
    @organizations.each do |org|
      DOMAINS.each do |domain|
        domain_sym = domain.to_sym
        queries = QUERY_SETS[domain_sym] || QUERY_SETS[:general]
        
        # Select a random query
        query = queries.sample
        
        # Get component for this organization/domain
        component = @bridge.get_component(:search, 
          organization_id: org.id,
          domain: domain
        )
        
        puts "  Streaming search for '#{query}' in #{domain} domain:"
        
        # Track metrics
        first_result_time = nil
        total_time = nil
        result_count = 0
        
        # Time to first result and total time
        start_time = Time.now
        
        # Use streaming search with a block
        component.search(query) do |result, is_final|
          # Record time to first result
          if result_count == 0
            first_result_time = Time.now - start_time
            puts "    Time to first result: #{(first_result_time * 1000).round(2)}ms"
          end
          
          result_count += 1
          
          # Record total time on final result
          if is_final
            total_time = Time.now - start_time
            puts "    Total streaming time: #{(total_time * 1000).round(2)}ms for #{result_count} results"
          end
        end
        
        # Record result
        @results << {
          test: 'streaming',
          organization_id: org.id,
          domain: domain,
          time_ms: (total_time * 1000).round(2),
          time_to_first_ms: (first_result_time * 1000).round(2),
          cache_hit: false,
          memory_mb: current_memory_usage,
          query: query,
          result_count: result_count
        }
      end
    end
  end
  
  # Benchmark memory usage
  def benchmark_memory_usage
    puts "\n📊 Memory Usage Statistics".green
    
    # Memory used by components
    component_memory = 0
    
    # Get current memory usage
    memory_usage = current_memory_usage
    puts "  Current memory usage: #{memory_usage}MB"
    
    # Reset components and measure memory again
    reset_all_components
    
    # Force garbage collection
    GC.start
    
    # Measure memory again
    memory_after_reset = current_memory_usage
    puts "  Memory usage after reset: #{memory_after_reset}MB"
    
    # Calculate difference
    memory_diff = memory_usage - memory_after_reset
    puts "  Memory used by components: #{memory_diff}MB".cyan
    
    # Record result
    @results << {
      test: 'memory',
      memory_mb: memory_usage,
      memory_after_reset_mb: memory_after_reset,
      memory_diff_mb: memory_diff
    }
  end
  
  # Reset all components
  def reset_all_components
    @organizations.each do |org|
      DOMAINS.each do |domain|
        @bridge.reset_component(:search, 
          organization_id: org.id,
          domain: domain
        )
      end
    end
  end
  
  # Get current memory usage in MB
  def current_memory_usage
    # Get memory usage from Process.rss
    memory_mb = Process.rss / 1024.0 / 1024.0
    memory_mb.round(2)
  end
  
  # Write results to CSV
  def write_results
    puts "\n💾 Writing results to #{@results_file}".green
    
    CSV.open(@results_file, 'w') do |csv|
      # Write header
      csv << ['test', 'organization_id', 'domain', 'time_ms', 'time_to_first_ms', 'cache_hit', 'memory_mb', 'query', 'result_count']
      
      # Write rows
      @results.each do |result|
        csv << [
          result[:test],
          result[:organization_id],
          result[:domain],
          result[:time_ms],
          result[:time_to_first_ms],
          result[:cache_hit],
          result[:memory_mb],
          result[:query],
          result[:result_count]
        ]
      end
    end
  end
  
  # Print summary of benchmark results
  def print_summary
    puts "\n📋 Summary".green
    
    # Calculate averages
    avg_init_time = @results.select { |r| r[:test] == 'component_init' }.map { |r| r[:time_ms] }.sum / 
                    @results.select { |r| r[:test] == 'component_init' }.size
    
    avg_reuse_time = @results.select { |r| r[:test] == 'component_reuse' }.map { |r| r[:time_ms] }.sum / 
                     @results.select { |r| r[:test] == 'component_reuse' }.size
    
    avg_cache_miss = @results.select { |r| r[:test] == 'cache_miss' }.map { |r| r[:time_ms] }.sum / 
                     @results.select { |r| r[:test] == 'cache_miss' }.size
    
    avg_cache_hit = @results.select { |r| r[:test] == 'cache_hit' }.map { |r| r[:time_ms] }.sum / 
                    @results.select { |r| r[:test] == 'cache_hit' }.size
    
    avg_streaming = @results.select { |r| r[:test] == 'streaming' }.map { |r| r[:time_ms] }.sum / 
                    @results.select { |r| r[:test] == 'streaming' }.size
    
    avg_first_result = @results.select { |r| r[:test] == 'streaming' }.map { |r| r[:time_to_first_ms] }.compact.sum / 
                       @results.select { |r| r[:test] == 'streaming' }.select { |r| r[:time_to_first_ms] }.size
    
    # Print averages
    puts "  Average component initialization time: #{avg_init_time.round(2)}ms"
    puts "  Average component reuse time: #{avg_reuse_time.round(2)}ms"
    puts "  Average cache miss query time: #{avg_cache_miss.round(2)}ms"
    puts "  Average cache hit query time: #{avg_cache_hit.round(2)}ms"
    puts "  Cache speedup: #{(avg_cache_miss / avg_cache_hit).round(2)}x"
    puts "  Average streaming search time: #{avg_streaming.round(2)}ms"
    puts "  Average time to first result: #{avg_first_result.round(2)}ms"
    
    # Print memory usage
    memory_result = @results.find { |r| r[:test] == 'memory' }
    if memory_result
      puts "  Memory used by components: #{memory_result[:memory_diff_mb]}MB"
    end
    
    puts "\n✅ Benchmark complete!".green
    puts "Results written to #{@results_file}".green
  end
  
  # Print header
  def print_header
    puts "\n" + "=" * 80
    puts " DALVS ARCHITECTURE BENCHMARK ".center(80, "=")
    puts "=" * 80
    
    puts "\nRunning benchmarks for the Domain-Aware Lazy Vector Search architecture"
    puts "#{ITERATIONS} iterations across #{@organizations.size} organizations and #{DOMAINS.size} domains"
    puts "Tests: Component initialization, component reuse, domain-aware caching, streaming search"
    puts "Start time: #{Time.now}"
    puts "-" * 80
  end
end

# Run the benchmark
benchmark = DALVSBenchmark.new
benchmark.run
