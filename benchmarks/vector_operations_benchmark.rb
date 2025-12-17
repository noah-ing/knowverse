#!/usr/bin/env ruby
# frozen_string_literal: true

# Vector Operations Benchmark Suite
#
# This benchmark compares:
# 1. Pure Ruby implementation (baseline)
# 2. Rust SIMD extension (when available)
# 3. Reference performance targets
#
# Run: bundle exec ruby benchmarks/vector_operations_benchmark.rb

require 'bundler/setup'
require 'benchmark'
require 'json'

# Load the application (for access to services)
ENV['RAILS_ENV'] ||= 'test'

# Pure Ruby baseline for comparison
module RubyBaseline
  class Distance
    def self.euclidean(a, b)
      squared_sum = 0.0
      a.length.times do |i|
        diff = a[i] - b[i]
        squared_sum += diff * diff
      end
      Math.sqrt(squared_sum)
    end

    def self.cosine_similarity(a, b)
      dot = 0.0
      norm_a = 0.0
      norm_b = 0.0

      a.length.times do |i|
        dot += a[i] * b[i]
        norm_a += a[i] * a[i]
        norm_b += b[i] * b[i]
      end

      dot / Math.sqrt(norm_a * norm_b)
    end
  end
end

class VectorBenchmark
  DIMENSIONS = [384, 768, 1024, 1536, 2048]
  ITERATIONS = 10_000

  def initialize
    @results = {}
  end

  def run_all
    puts "=" * 70
    puts "KNOWVERSE VECTOR OPERATIONS BENCHMARK"
    puts "=" * 70
    puts
    puts "Testing #{ITERATIONS} iterations per dimension"
    puts "Dimensions: #{DIMENSIONS.join(', ')}"
    puts

    check_rust_availability

    DIMENSIONS.each do |dim|
      benchmark_dimension(dim)
    end

    print_summary
    save_results
  end

  private

  def check_rust_availability
    begin
      require_relative '../lib/knowverse_vector'
      @rust_available = KnowverseVector.rust_available?
    rescue LoadError
      @rust_available = false
    end

    if @rust_available
      puts "[OK] Rust SIMD extension loaded"
    else
      puts "[WARN] Rust extension not available - benchmarking Ruby only"
    end
    puts
  end

  def benchmark_dimension(dim)
    puts "-" * 70
    puts "Dimension: #{dim}"
    puts "-" * 70

    # Generate random test vectors
    vec_a = Array.new(dim) { rand(-1.0..1.0) }
    vec_b = Array.new(dim) { rand(-1.0..1.0) }

    results = { dimension: dim }

    # Benchmark Ruby baseline
    ruby_euclidean = benchmark_operation("Ruby Euclidean") do
      RubyBaseline::Distance.euclidean(vec_a, vec_b)
    end
    results[:ruby_euclidean_ms] = ruby_euclidean

    ruby_cosine = benchmark_operation("Ruby Cosine") do
      RubyBaseline::Distance.cosine_similarity(vec_a, vec_b)
    end
    results[:ruby_cosine_ms] = ruby_cosine

    if @rust_available
      rust_euclidean = benchmark_operation("Rust Euclidean") do
        KnowverseVector::Distance.euclidean(vec_a, vec_b)
      end
      results[:rust_euclidean_ms] = rust_euclidean

      rust_cosine = benchmark_operation("Rust Cosine") do
        KnowverseVector::Distance.cosine_similarity(vec_a, vec_b)
      end
      results[:rust_cosine_ms] = rust_cosine

      # Calculate speedup
      euclidean_speedup = ruby_euclidean / rust_euclidean
      cosine_speedup = ruby_cosine / rust_cosine

      puts "  Euclidean speedup: #{euclidean_speedup.round(1)}x"
      puts "  Cosine speedup: #{cosine_speedup.round(1)}x"

      results[:euclidean_speedup] = euclidean_speedup
      results[:cosine_speedup] = cosine_speedup
    end

    # Benchmark batch operations
    benchmark_batch_operations(dim, results)

    puts

    @results[dim] = results
  end

  def benchmark_operation(name)
    times = []

    # Warmup
    10.times { yield }

    # Actual benchmark
    ITERATIONS.times do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      times << elapsed
    end

    avg_ms = (times.sum / times.length) * 1000
    p99_ms = times.sort[(times.length * 0.99).to_i] * 1000

    puts "  #{name.ljust(20)} avg: #{format('%.4f', avg_ms)}ms  p99: #{format('%.4f', p99_ms)}ms"

    avg_ms
  end

  def benchmark_batch_operations(dim, results)
    # Generate candidate vectors for batch search
    num_candidates = 1000
    candidates = Array.new(num_candidates) { Array.new(dim) { rand(-1.0..1.0) } }
    query = Array.new(dim) { rand(-1.0..1.0) }
    k = 10

    puts "  Batch find_nearest (#{num_candidates} candidates, k=#{k}):"

    # Ruby batch (brute force)
    ruby_batch = benchmark_batch("Ruby batch") do
      distances = candidates.each_with_index.map do |c, i|
        [i, RubyBaseline::Distance.euclidean(query, c)]
      end
      distances.sort_by(&:last).first(k)
    end
    results[:ruby_batch_ms] = ruby_batch

    if @rust_available
      rust_batch = benchmark_batch("Rust batch") do
        KnowverseVector::Batch.find_nearest(query, candidates, k, 'euclidean')
      end
      results[:rust_batch_ms] = rust_batch
      results[:batch_speedup] = ruby_batch / rust_batch
      puts "    Batch speedup: #{(ruby_batch / rust_batch).round(1)}x"
    end
  end

  def benchmark_batch(name)
    times = []

    # Fewer iterations for batch operations
    100.times do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      times << elapsed
    end

    avg_ms = (times.sum / times.length) * 1000
    puts "    #{name.ljust(18)} avg: #{format('%.2f', avg_ms)}ms"

    avg_ms
  end

  def print_summary
    puts
    puts "=" * 70
    puts "SUMMARY"
    puts "=" * 70
    puts

    if @rust_available
      puts "Rust Extension Performance:"
      puts
      puts "| Dimension | Euclidean Speedup | Cosine Speedup | Batch Speedup |"
      puts "|-----------|-------------------|----------------|---------------|"

      @results.each do |dim, data|
        puts "| #{dim.to_s.ljust(9)} | #{format('%.1fx', data[:euclidean_speedup]).ljust(17)} | #{format('%.1fx', data[:cosine_speedup]).ljust(14)} | #{format('%.1fx', data[:batch_speedup] || 0).ljust(13)} |"
      end
    else
      puts "Ruby-only results (compile Rust extension for 50-100x speedup):"
      puts
      puts "| Dimension | Euclidean (ms) | Cosine (ms) |"
      puts "|-----------|----------------|-------------|"

      @results.each do |dim, data|
        puts "| #{dim.to_s.ljust(9)} | #{format('%.4f', data[:ruby_euclidean_ms]).ljust(14)} | #{format('%.4f', data[:ruby_cosine_ms]).ljust(11)} |"
      end
    end

    puts
    puts "Reference: At 768 dimensions, Rust should be 50-100x faster than Ruby"
    puts
  end

  def save_results
    results_file = File.join(__dir__, 'results', "benchmark_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json")
    FileUtils.mkdir_p(File.dirname(results_file))

    File.write(results_file, JSON.pretty_generate({
      timestamp: Time.now.iso8601,
      rust_available: @rust_available,
      iterations: ITERATIONS,
      dimensions: DIMENSIONS,
      results: @results
    }))

    puts "Results saved to: #{results_file}"
  end
end

# Run the benchmark
if __FILE__ == $0
  require 'fileutils'
  VectorBenchmark.new.run_all
end
