# frozen_string_literal: true

module Distributed
  module Benchmark
    # Specialized benchmark class for hybrid search performance testing
    class HybridSearchBenchmark
      attr_reader :results, :options
      
      # Types of queries for benchmark testing
      QUERY_TYPES = {
        factoid: 'Simple factual questions',
        semantic: 'Semantic meaning questions',
        ambiguous: 'Ambiguous queries with multiple interpretations',
        complex: 'Complex multi-part questions',
        specialized: 'Domain-specific terminology'
      }.freeze
      
      # Search providers to benchmark
      PROVIDERS = {
        pgvector_cosine: 'PGVector Cosine',
        hnsw: 'HNSW',
        hybrid: 'Hybrid',
        hybrid_advanced: 'Advanced Hybrid',
        distributed: 'Distributed HNSW',
        domain_aware: 'Domain-Aware'
      }.freeze
      
      # Weight combinations to test for hybrid search
      WEIGHT_CONFIGURATIONS = [
        { vector: 0.9, keyword: 0.1 },
        { vector: 0.8, keyword: 0.2 },
        { vector: 0.7, keyword: 0.3 },
        { vector: 0.6, keyword: 0.4 },
        { vector: 0.5, keyword: 0.5 },
        { vector: 0.4, keyword: 0.6 },
        { vector: 0.3, keyword: 0.7 },
        { vector: 0.2, keyword: 0.8 },
        { vector: 0.1, keyword: 0.9 }
      ].freeze

      # Initialize a new benchmark with options
      # @param options [Hash] Benchmark configuration options
      def initialize(options = {})
        @options = {
          # Test corpus settings
          organization_id: options[:organization_id],
          query_count: options[:query_count] || 50,
          query_types: options[:query_types] || QUERY_TYPES.keys,
          
          # Search settings
          providers: options[:providers] || PROVIDERS.keys,
          weight_configurations: options[:weight_configurations] || WEIGHT_CONFIGURATIONS,
          early_termination: options.key?(:early_termination) ? options[:early_termination] : true,
          
          # Measurement settings
          use_labeled_data: options[:use_labeled_data] || false,
          labeled_data: options[:labeled_data] || [],
          
          # Output settings
          output_file: options[:output_file],
          verbose: options[:verbose] || true
        }
        
        @results = {
          config: @options.dup,
          latency: {},
          precision: {},
          recall: {},
          f1_score: {},
          provider_comparison: {},
          weight_tuning: {}
        }
        
        @test_corpus = nil
      end
      
      # Run all benchmark tests
      # @return [Hash] Benchmark results
      def run_all
        load_test_corpus
        
        run_latency_benchmark
        
        if @options[:use_labeled_data]
          run_precision_recall_benchmark
          run_f1_score_benchmark
        end
        
        run_provider_comparison
        run_weight_tuning
        
        save_results if @options[:output_file]
        
        @results
      end
      
      # Run the latency benchmark
      # @return [Hash] Latency results by query type and provider
      def run_latency_benchmark
        log "Running latency benchmark with #{@test_corpus.size} queries..."
        
        latency_results = {
          by_provider: {},
          by_query_type: {},
          by_weight_config: {}
        }
        
        # Initialize result structure
        @options[:providers].each do |provider|
          latency_results[:by_provider][provider] = {
            avg: 0,
            min: Float::INFINITY,
            max: 0,
            p95: 0,
            p99: 0,
            count: 0,
            total_ms: 0
          }
        end
        
        @options[:query_types].each do |query_type|
          latency_results[:by_query_type][query_type] = {
            avg: 0,
            min: Float::INFINITY,
            max: 0,
            p95: 0,
            p99: 0,
            count: 0,
            total_ms: 0
          }
        end
        
        # Default weight configuration for this test
        default_config = @options[:weight_configurations].first
        
        # Run latency tests
        @test_corpus.each do |test_query|
          query_text = test_query[:query]
          query_type = test_query[:type]
          
          @options[:providers].each do |provider|
            log "Testing latency for '#{query_text}' with provider #{provider}..." if @options[:verbose]
            
            # Skip non-hybrid providers for weight config tests
            next unless provider_supports_weights?(provider) 
            
            # Time the search operation
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            
            execute_search(
              query_text,
              provider,
              default_config[:vector],
              default_config[:keyword]
            )
            
            end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            latency_ms = (end_time - start_time) * 1000
            
            # Update provider stats
            update_latency_stats(latency_results[:by_provider][provider], latency_ms)
            
            # Update query type stats
            update_latency_stats(latency_results[:by_query_type][query_type], latency_ms)
          end
        end
        
        # Finalize stats
        finalize_latency_stats(latency_results[:by_provider])
        finalize_latency_stats(latency_results[:by_query_type])
        
        # Test weight configurations for hybrid search
        if @options[:providers].include?(:hybrid) || @options[:providers].include?(:hybrid_advanced)
          # Test hybrid with different weight configurations
          run_weight_latency_benchmark(latency_results[:by_weight_config])
        end
        
        @results[:latency] = latency_results
        latency_results
      end
      
      # Run weight latency benchmark
      # @param results [Hash] Results hash to populate
      def run_weight_latency_benchmark(results)
        log "Running weight configuration latency benchmark..."
        
        # Select a subset of typical queries for this test
        test_queries = @test_corpus.sample([10, @test_corpus.size].min)
        
        # Test each weight configuration
        @options[:weight_configurations].each do |config|
          vector_weight = config[:vector]
          keyword_weight = config[:keyword]
          config_key = "v#{vector_weight}-k#{keyword_weight}"
          
          results[config_key] = {
            avg: 0,
            min: Float::INFINITY,
            max: 0,
            p95: 0,
            p99: 0,
            count: 0,
            total_ms: 0,
            config: config
          }
          
          # Use both hybrid providers if available
          hybrid_providers = [:hybrid, :hybrid_advanced].select { |p| @options[:providers].include?(p) }
          
          test_queries.each do |test_query|
            hybrid_providers.each do |provider|
              log "Testing weights (v:#{vector_weight}/k:#{keyword_weight}) for '#{test_query[:query]}'..." if @options[:verbose]
              
              # Time the search operation
              start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              
              execute_search(
                test_query[:query],
                provider,
                vector_weight,
                keyword_weight
              )
              
              end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              latency_ms = (end_time - start_time) * 1000
              
              # Update weight config stats
              update_latency_stats(results[config_key], latency_ms)
            end
          end
        end
        
        # Finalize weight config stats
        results.each do |config_key, stats|
          finalize_latency_stats({ config_key => stats })
        end
      end
      
      # Run the precision/recall benchmark
      # @return [Hash] Precision and recall results
      def run_precision_recall_benchmark
        log "Running precision/recall benchmark using labeled data..."
        
        precision_results = {}
        recall_results = {}
        
        @options[:providers].each do |provider|
          precision_results[provider] = { total: 0, by_query_type: {} }
          recall_results[provider] = { total: 0, by_query_type: {} }
          
          @options[:query_types].each do |query_type|
            precision_results[provider][:by_query_type][query_type] = 0
            recall_results[provider][:by_query_type][query_type] = 0
          end
        end
        
        # Default weight configuration for this test
        default_config = @options[:weight_configurations].first
        
        # Get labeled data or use test corpus if available
        labeled_queries = @options[:labeled_data].presence || @test_corpus.select { |q| q[:relevant_docs].present? }
        
        # Skip if no labeled data
        if labeled_queries.empty?
          log "Warning: No labeled data available, skipping precision/recall benchmark"
          return
        end
        
        # Run precision/recall tests
        labeled_queries.each do |test_query|
          query_text = test_query[:query]
          query_type = test_query[:type]
          relevant_docs = test_query[:relevant_docs]
          
          next unless relevant_docs.present?
          
          @options[:providers].each do |provider|
            log "Testing precision/recall for '#{query_text}' with provider #{provider}..." if @options[:verbose]
            
            # Execute search with this provider
            results = execute_search(
              query_text,
              provider,
              default_config[:vector],
              default_config[:keyword]
            )
            
            # Extract document IDs from results
            retrieved_docs = results.map { |r| r['document_id'].to_s }
            
            # Calculate precision and recall
            precision = calculate_precision(retrieved_docs, relevant_docs)
            recall = calculate_recall(retrieved_docs, relevant_docs)
            
            # Update provider stats
            precision_results[provider][:total] += precision
            recall_results[provider][:total] += recall
            
            # Update query type stats
            if precision_results[provider][:by_query_type][query_type]
              precision_results[provider][:by_query_type][query_type] += precision
              recall_results[provider][:by_query_type][query_type] += recall
            end
          end
        end
        
        # Calculate averages
        @options[:providers].each do |provider|
          # Overall average
          query_count = labeled_queries.size
          precision_results[provider][:total] /= query_count if query_count > 0
          recall_results[provider][:total] /= query_count if query_count > 0
          
          # Average by query type
          @options[:query_types].each do |query_type|
            type_count = labeled_queries.count { |q| q[:type] == query_type }
            if type_count > 0
              precision_results[provider][:by_query_type][query_type] /= type_count
              recall_results[provider][:by_query_type][query_type] /= type_count
            end
          end
        end
        
        @results[:precision] = precision_results
        @results[:recall] = recall_results
        
        { precision: precision_results, recall: recall_results }
      end
      
      # Run the F1 score benchmark combining precision and recall
      # @return [Hash] F1 score results
      def run_f1_score_benchmark
        log "Calculating F1 scores from precision and recall metrics..."
        
        f1_results = {}
        
        # Ensure precision and recall benchmarks have been run
        unless @results[:precision].present? && @results[:recall].present?
          run_precision_recall_benchmark
        end
        
        @options[:providers].each do |provider|
          f1_results[provider] = { total: 0, by_query_type: {} }
          
          # Calculate overall F1 score
          precision = @results[:precision][provider][:total] || 0
          recall = @results[:recall][provider][:total] || 0
          
          f1_results[provider][:total] = calculate_f1_score(precision, recall)
          
          # Calculate F1 score by query type
          @options[:query_types].each do |query_type|
            precision = @results[:precision][provider][:by_query_type][query_type] || 0
            recall = @results[:recall][provider][:by_query_type][query_type] || 0
            
            f1_results[provider][:by_query_type][query_type] = calculate_f1_score(precision, recall)
          end
        end
        
        @results[:f1_score] = f1_results
        f1_results
      end
      
      # Run benchmark comparing different search providers
      # @return [Hash] Provider comparison results
      def run_provider_comparison
        log "Running provider comparison benchmark..."
        
        comparison_results = {
          query_handling: {},
          latency: {},
          quality: {}
        }
        
        @options[:query_types].each do |query_type|
          # Select queries of this type
          type_queries = @test_corpus.select { |q| q[:type] == query_type }
          next if type_queries.empty?
          
          # Compare how each provider handles this query type
          comparison_results[:query_handling][query_type] = {}
          
          # Use latency data if available
          if @results[:latency][:by_query_type][query_type]
            comparison_results[:latency][query_type] = @results[:latency][:by_query_type][query_type]
          end
          
          # Use precision/recall data if available
          if @results[:precision] && @results[:recall]
            comparison_results[:quality][query_type] = {}
            
            @options[:providers].each do |provider|
              precision = @results[:precision][provider][:by_query_type][query_type] || 0
              recall = @results[:recall][provider][:by_query_type][query_type] || 0
              f1 = @results[:f1_score][provider][:by_query_type][query_type] || 0
              
              comparison_results[:quality][query_type][provider] = {
                precision: precision,
                recall: recall,
                f1_score: f1
              }
            end
          end
        end
        
        # Identify best provider for each query type
        @options[:query_types].each do |query_type|
          comparison_results[:query_handling][query_type][:best_provider] = identify_best_provider(query_type)
          comparison_results[:query_handling][query_type][:provider_ranking] = rank_providers(query_type)
        end
        
        @results[:provider_comparison] = comparison_results
        comparison_results
      end
      
      # Run benchmark to tune weight configurations for hybrid search
      # @return [Hash] Weight tuning results
      def run_weight_tuning
        log "Running weight tuning benchmark..."
        
        # Skip if no hybrid providers are being tested
        unless @options[:providers].include?(:hybrid) || @options[:providers].include?(:hybrid_advanced)
          log "No hybrid providers selected, skipping weight tuning"
          return {}
        end
        
        tuning_results = {
          by_query_type: {},
          overall: {}
        }
        
        # Skip if no labeled data
        labeled_queries = @options[:labeled_data].presence || @test_corpus.select { |q| q[:relevant_docs].present? }
        if labeled_queries.empty?
          log "Warning: No labeled data available, skipping weight tuning benchmark"
          return tuning_results
        end
        
        # Test each query type
        @options[:query_types].each do |query_type|
          # Select queries of this type with labeled data
          type_queries = labeled_queries.select { |q| q[:type] == query_type }
          next if type_queries.empty?
          
          tuning_results[:by_query_type][query_type] = {
            weights: {},
            optimal: nil
          }
          
          # Test each weight configuration
          @options[:weight_configurations].each do |config|
            vector_weight = config[:vector]
            keyword_weight = config[:keyword]
            config_key = "v#{vector_weight}-k#{keyword_weight}"
            
            scores = { precision: 0, recall: 0, f1: 0, count: 0 }
            
            # Use both hybrid providers if available
            hybrid_providers = [:hybrid, :hybrid_advanced].select { |p| @options[:providers].include?(p) }
            
            type_queries.each do |test_query|
              relevant_docs = test_query[:relevant_docs]
              next unless relevant_docs.present?
              
              hybrid_providers.each do |provider|
                log "Testing weights (v:#{vector_weight}/k:#{keyword_weight}) for '#{test_query[:query]}'..." if @options[:verbose]
                
                # Execute search with this configuration
                results = execute_search(
                  test_query[:query],
                  provider,
                  vector_weight,
                  keyword_weight
                )
                
                # Extract document IDs from results
                retrieved_docs = results.map { |r| r['document_id'].to_s }
                
                # Calculate metrics
                precision = calculate_precision(retrieved_docs, relevant_docs)
                recall = calculate_recall(retrieved_docs, relevant_docs)
                f1 = calculate_f1_score(precision, recall)
                
                # Update scores
                scores[:precision] += precision
                scores[:recall] += recall
                scores[:f1] += f1
                scores[:count] += 1
              end
            end
            
            # Calculate averages
            if scores[:count] > 0
              scores[:precision] /= scores[:count]
              scores[:recall] /= scores[:count]
              scores[:f1] /= scores[:count]
            end
            
            # Store results
            tuning_results[:by_query_type][query_type][:weights][config_key] = {
              config: config,
              precision: scores[:precision],
              recall: scores[:recall],
              f1: scores[:f1]
            }
          end
          
          # Determine optimal weights for this query type (based on F1 score)
          best_config = tuning_results[:by_query_type][query_type][:weights].max_by { |_, v| v[:f1] }
          tuning_results[:by_query_type][query_type][:optimal] = best_config.first if best_config
        end
        
        # Calculate overall optimal weights across all query types
        overall_scores = {}
        
        @options[:weight_configurations].each do |config|
          vector_weight = config[:vector]
          keyword_weight = config[:keyword]
          config_key = "v#{vector_weight}-k#{keyword_weight}"
          
          overall_scores[config_key] = {
            config: config,
            precision: 0,
            recall: 0,
            f1: 0,
            count: 0
          }
        end
        
        # Aggregate scores from all query types
        tuning_results[:by_query_type].each do |query_type, data|
          data[:weights].each do |config_key, scores|
            if overall_scores[config_key]
              overall_scores[config_key][:precision] += scores[:precision]
              overall_scores[config_key][:recall] += scores[:recall]
              overall_scores[config_key][:f1] += scores[:f1]
              overall_scores[config_key][:count] += 1
            end
          end
        end
        
        # Calculate averages
        overall_scores.each do |config_key, scores|
          if scores[:count] > 0
            scores[:precision] /= scores[:count]
            scores[:recall] /= scores[:count]
            scores[:f1] /= scores[:count]
          end
        end
        
        tuning_results[:overall][:weights] = overall_scores
        
        # Determine overall optimal weights (based on F1 score)
        best_config = overall_scores.max_by { |_, v| v[:f1] }
        tuning_results[:overall][:optimal] = best_config.first if best_config
        
        @results[:weight_tuning] = tuning_results
        tuning_results
      end
      
      # Generate a report of benchmark results
      # @return [String] Markdown-formatted report
      def generate_report
        report = "# KnowVerse Hybrid Search Benchmark Report\n\n"
        
        report += "## Configuration\n\n"
        report += "- **Query Count**: #{@options[:query_count]} queries\n"
        report += "- **Query Types**: #{@options[:query_types].join(', ')}\n"
        report += "- **Providers Tested**: #{@options[:providers].join(', ')}\n"
        report += "- **Weight Configurations**: #{@options[:weight_configurations].size} configurations\n"
        report += "- **Early Termination**: #{@options[:early_termination] ? 'Enabled' : 'Disabled'}\n\n"
        
        # Latency Results
        if @results[:latency].present?
          report += "## Latency Results\n\n"
          
          # By Provider
          report += "### Latency by Provider\n\n"
          report += "| Provider | Average (ms) | P95 (ms) | P99 (ms) | Min (ms) | Max (ms) |\n"
          report += "|----------|-------------|----------|----------|----------|----------|\n"
          
          @results[:latency][:by_provider].each do |provider, stats|
            report += "| #{provider} | #{stats[:avg]&.round(2)} | #{stats[:p95]&.round(2)} | #{stats[:p99]&.round(2)} | #{stats[:min]&.round(2)} | #{stats[:max]&.round(2)} |\n"
          end
          report += "\n"
          
          # By Query Type
          report += "### Latency by Query Type\n\n"
          report += "| Query Type | Average (ms) | P95 (ms) | P99 (ms) | Min (ms) | Max (ms) |\n"
          report += "|------------|-------------|----------|----------|----------|----------|\n"
          
          @results[:latency][:by_query_type].each do |query_type, stats|
            report += "| #{query_type} | #{stats[:avg]&.round(2)} | #{stats[:p95]&.round(2)} | #{stats[:p99]&.round(2)} | #{stats[:min]&.round(2)} | #{stats[:max]&.round(2)} |\n"
          end
          report += "\n"
          
          # By Weight Configuration
          if @results[:latency][:by_weight_config].present?
            report += "### Latency by Weight Configuration\n\n"
            report += "| Vector Weight | Keyword Weight | Average (ms) | P95 (ms) |\n"
            report += "|--------------|---------------|-------------|----------|\n"
            
            @results[:latency][:by_weight_config].each do |config_key, stats|
              vector_weight = stats[:config][:vector]
              keyword_weight = stats[:config][:keyword]
              report += "| #{vector_weight} | #{keyword_weight} | #{stats[:avg]&.round(2)} | #{stats[:p95]&.round(2)} |\n"
            end
            report += "\n"
          end
        end
        
        # Quality Results
        if @results[:precision].present? && @results[:recall].present? && @results[:f1_score].present?
          report += "## Search Quality Results\n\n"
          
          # Overall quality
          report += "### Overall Search Quality\n\n"
          report += "| Provider | Precision | Recall | F1 Score |\n"
          report += "|----------|-----------|--------|----------|\n"
          
          @options[:providers].each do |provider|
            precision = @results[:precision][provider][:total]
            recall = @results[:recall][provider][:total]
            f1 = @results[:f1_score][provider][:total]
            
            report += "| #{provider} | #{(precision * 100).round(2)}% | #{(recall * 100).round(2)}% | #{(f1 * 100).round(2)}% |\n"
          end
          report += "\n"
          
          # Quality by query type
          report += "### Search Quality by Query Type\n\n"
          
          @options[:query_types].each do |query_type|
            report += "#### #{query_type.to_s.capitalize} Queries\n\n"
            report += "| Provider | Precision | Recall | F1 Score |\n"
            report += "|----------|-----------|--------|----------|\n"
            
            @options[:providers].each do |provider|
              precision = @results[:precision][provider][:by_query_type][query_type]
              recall = @results[:recall][provider][:by_query_type][query_type]
              f1 = @results[:f1_score][provider][:by_query_type][query_type]
              
              report += "| #{provider} | #{(precision * 100).round(2)}% | #{(recall * 100).round(2)}% | #{(f1 * 100).round(2)}% |\n"
            end
            report += "\n"
          end
        end
        
        # Provider Comparison
        if @results[:provider_comparison].present?
          report += "## Provider Comparison\n\n"
          
          report += "### Best Provider by Query Type\n\n"
          report += "| Query Type | Best Provider | Provider Ranking |\n"
          report += "|------------|--------------|------------------|\n"
          
          @results[:provider_comparison][:query_handling].each do |query_type, data|
            best = data[:best_provider]
            ranking = data[:provider_ranking]&.join(' > ')
            
            report += "| #{query_type} | #{best} | #{ranking} |\n"
          end
          report += "\n"
        end
        
        # Weight Tuning
        if @results[:weight_tuning].present?
          report += "## Weight Tuning Results\n\n"
          
          # Overall optimal weights
          if @results[:weight_tuning][:overall][:optimal]
            optimal_key = @results[:weight_tuning][:overall][:optimal]
            optimal_config = @results[:weight_tuning][:overall][:weights][optimal_key][:config]
            
            report += "### Overall Optimal Weights\n\n"
            report += "- **Vector Weight**: #{optimal_config[:vector]}\n"
            report += "- **Keyword Weight**: #{optimal_config[:keyword]}\n\n"
          end
          
          # Optimal weights by query type
          report += "### Optimal Weights by Query Type\n\n"
          report += "| Query Type | Vector Weight | Keyword Weight | F1 Score |\n"
          report += "|------------|--------------|---------------|----------|\n"
          
          @results[:weight_tuning][:by_query_type].each do |query_type, data|
            if data[:optimal]
              optimal_key = data[:optimal]
              optimal_config = data[:weights][optimal_key][:config]
              f1 = data[:weights][optimal_key][:f1]
              
              report += "| #{query_type} | #{optimal_config[:vector]} | #{optimal_config[:keyword]} | #{(f1 * 100).round(2)}% |\n"
            end
          end
          report += "\n"
          
          # All weight configurations performance
          report += "### All Weight Configurations Performance\n\n"
          report += "| Vector Weight | Keyword Weight | Precision | Recall | F1 Score |\n"
          report += "|--------------|---------------|-----------|--------|----------|\n"
          
          @results[:weight_tuning][:overall][:weights].each do |config_key, stats|
            vector_weight = stats[:config][:vector]
            keyword_weight = stats[:config][:keyword]
            
            report += "| #{vector_weight} | #{keyword_weight} | #{(stats[:precision] * 100).round(2)}% | #{(stats[:recall] * 100).round(2)}% | #{(stats[:f1] * 100).round(2)}% |\n"
          end
          report += "\n"
        end
        
        # Recommendations
        report += "## Recommendations\n\n"
        
        # Provider recommendations
        if @results[:provider_comparison].present?
          report += "### Provider Selection Recommendations\n\n"
          
          @options[:query_types].each do |query_type|
            best = @results[:provider_comparison][:query_handling][query_type][:best_provider]
            report += "- For #{query_type} queries, use the **#{best}** provider for best results\n"
          end
          report += "\n"
        end
        
        # Weight recommendations
        if @results[:weight_tuning].present? && @results[:weight_tuning][:overall][:optimal]
          report += "### Weight Configuration Recommendations\n\n"
          
          optimal_key = @results[:weight_tuning][:overall][:optimal]
          optimal_config = @results[:weight_tuning][:overall][:weights][optimal_key][:config]
          
          report += "- For general use, set vector weight to **#{optimal_config[:vector]}** and keyword weight to **#{optimal_config[:keyword]}**\n"
          
          @results[:weight_tuning][:by_query_type].each do |query_type, data|
            if data[:optimal]
              optimal_key = data[:optimal]
              optimal_config = data[:weights][optimal_key][:config]
              
              report += "- For #{query_type} queries, set vector weight to **#{optimal_config[:vector]}** and keyword weight to **#{optimal_config[:keyword]}**\n"
            end
          end
        end
        
        report
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
        
        # Add timestamp
        @results[:timestamp] = timestamp
        
        # Write results to file
        File.write(actual_path, JSON.pretty_generate(@results))
        
        log "Results saved to #{actual_path}"
        true
      end
      
      private
      
      # Load or generate test corpus
      def load_test_corpus
        log "Loading test corpus..."
        
        # If there's already a test corpus, return it
        return @test_corpus if @test_corpus.present?
        
        # Generate a test corpus
        @test_corpus = []
        
        # First, look for labeled data if we're using it
        if @options[:use_labeled_data] && @options[:labeled_data].present?
          @test_corpus = @options[:labeled_data]
          log "Loaded #{@test_corpus.size} queries from labeled data"
          return @test_corpus
        end
        
        # Otherwise, generate synthetic queries for each type
        queries_per_type = @options[:query_count] / @options[:query_types].size
        
        @options[:query_types].each do |query_type|
          queries_per_type.times do |i|
            @test_corpus << generate_query(query_type, i)
          end
        end
        
        log "Generated #{@test_corpus.size} synthetic test queries"
        @test_corpus
      end
      
      # Generate a synthetic test query
      # @param query_type [Symbol] Type of query to generate
      # @param index [Integer] Index for unique query generation
      # @return [Hash] Query hash with text and metadata
      def generate_query(query_type, index)
        base_query = case query_type
                     when :factoid
                       factoid_queries = [
                         "What is the maximum file size limit?",
                         "How many users can be in an organization?",
                         "When was the knowledge base created?",
                         "What is the default embedding dimension?",
                         "How many search providers are available?"
                       ]
                       factoid_queries[index % factoid_queries.size]
                     when :semantic
                       semantic_queries = [
                         "How does the system handle large documents?",
                         "Explain the difference between vector and keyword search",
                         "How can I improve search quality?",
                         "What metrics should I monitor for search performance?",
                         "How does distributed search work?"
                       ]
                       semantic_queries[index % semantic_queries.size]
                     when :ambiguous
                       ambiguous_queries = [
                         "vector model",
                         "search configuration",
                         "python integration",
                         "memory usage",
                         "scaling issues"
                       ]
                       ambiguous_queries[index % ambiguous_queries.size]
                     when :complex
                       complex_queries = [
                         "How does HNSW search compare to pgvector when searching large collections of technical documents with specialized terminology?",
                         "What is the performance impact of increasing vector dimensions from 384 to 1536 while maintaining sub-10ms query latency across a distributed architecture?",
                         "Explain the tradeoffs between precision and recall when implementing hybrid search with different weight configurations for medical terminology",
                         "How can we optimize cache efficiency while ensuring tenant isolation in a multi-node deployment with varied organization sizes?",
                         "What architecture modifications are needed to support both question answering and semantic search across 10+ million vectors while maintaining response times under 100ms?"
                       ]
                       complex_queries[index % complex_queries.size]
                     when :specialized
                       specialized_queries = [
                         "HNSW index optimization for memory efficiency",
                         "Cosine similarity vs inner product distance metrics",
                         "Hyperparameter tuning for embedding fine-tuning",
                         "Quantization techniques for high-dimension vectors",
                         "Asynchronous graph construction algorithm implementation"
                       ]
                       specialized_queries[index % specialized_queries.size]
                     else
                       "Default query #{index}"
                     end
        
        # Create query hash
        {
          query: "#{base_query} #{index}", # Make query unique
          type: query_type,
          complexity: query_complexity(query_type),
          relevant_docs: [] # No relevant docs for synthetic queries
        }
      end
      
      # Determine query complexity based on type
      # @param query_type [Symbol] Type of query
      # @return [Symbol] Complexity level
      def query_complexity(query_type)
        case query_type
        when :factoid
          :simple
        when :semantic, :ambiguous
          :medium
        when :complex, :specialized
          :complex
        else
          :medium
        end
      end
      
      # Execute search with the specified provider and weights
      # @param query_text [String] Query text
      # @param provider [Symbol] Search provider
      # @param vector_weight [Float] Weight for vector search
      # @param keyword_weight [Float] Weight for keyword search
      # @return [Array] Search results
      def execute_search(query_text, provider, vector_weight = nil, keyword_weight = nil)
        # Use SearchRouter to execute the search
        options = {
          search_provider: provider,
          limit: 10,
          early_termination: @options[:early_termination]
        }
        
        # Add weights if provider supports them
        if provider_supports_weights?(provider)
          options[:vector_weight] = vector_weight if vector_weight
          options[:keyword_weight] = keyword_weight if keyword_weight
        end
        
        # Execute the search
        result = SearchRouter.route_query(query_text, @options[:organization_id], options)
        
        # Return just the results array
        result[:results]
      rescue => e
        log "Search error with provider #{provider}: #{e.message}"
        []
      end
      
      # Check if a provider supports weight configuration
      # @param provider [Symbol] Provider to check
      # @return [Boolean] Whether provider supports weights
      def provider_supports_weights?(provider)
        [:hybrid, :hybrid_advanced].include?(provider)
      end
      
      # Calculate precision of search results
      # @param retrieved_docs [Array] IDs of retrieved documents
      # @param relevant_docs [Array] IDs of relevant documents
      # @return [Float] Precision score (0-1)
      def calculate_precision(retrieved_docs, relevant_docs)
        return 0 if retrieved_docs.empty?
        
        relevant_retrieved = retrieved_docs.select { |doc_id| relevant_docs.include?(doc_id) }
        relevant_retrieved.size.to_f / retrieved_docs.size
      end
      
      # Calculate recall of search results
      # @param retrieved_docs [Array] IDs of retrieved documents
      # @param relevant_docs [Array] IDs of relevant documents
      # @return [Float] Recall score (0-1)
      def calculate_recall(retrieved_docs, relevant_docs)
        return 0 if relevant_docs.empty?
        
        relevant_retrieved = retrieved_docs.select { |doc_id| relevant_docs.include?(doc_id) }
        relevant_retrieved.size.to_f / relevant_docs.size
      end
      
      # Calculate F1 score from precision and recall
      # @param precision [Float] Precision score
      # @param recall [Float] Recall score
      # @return [Float] F1 score (0-1)
      def calculate_f1_score(precision, recall)
        return 0 if precision + recall == 0
        
        2 * (precision * recall) / (precision + recall)
      end
      
      # Update latency statistics with a new measurement
      # @param stats [Hash] Statistics hash to update
      # @param latency_ms [Float] Latency measurement in milliseconds
      def update_latency_stats(stats, latency_ms)
        stats[:total_ms] += latency_ms
        stats[:count] += 1
        stats[:min] = [stats[:min], latency_ms].min
        stats[:max] = [stats[:max], latency_ms].max
        
        # We'll calculate avg, p95, p99 in finalize_latency_stats
      end
      
      # Finalize latency statistics by calculating derived metrics
      # @param stats_hash [Hash] Hash of statistics to finalize
      def finalize_latency_stats(stats_hash)
        stats_hash.each do |key, stats|
          next if stats[:count] == 0
          
          # Calculate average
          stats[:avg] = stats[:total_ms] / stats[:count]
          
          # For percentiles, we need all latency values
          # Since we don't store them all, we're estimating based on min/max/avg
          range = stats[:max] - stats[:min]
          
          # Rough estimates for percentiles in a normal-ish distribution
          # These are obviously approximations since we don't have the full distribution
          stats[:p95] = stats[:avg] + (range * 0.4)
          stats[:p99] = stats[:avg] + (range * 0.7)
          
          # Ensure we don't exceed max
          stats[:p95] = [stats[:p95], stats[:max]].min
          stats[:p99] = [stats[:p99], stats[:max]].min
        end
      end
      
      # Identify the best provider for a query type
      # @param query_type [Symbol] Query type
      # @return [Symbol] Best provider for this query type
      def identify_best_provider(query_type)
        # If we have quality metrics, use F1 score
        if @results[:f1_score].present?
          best_provider = nil
          best_score = -1
          
          @options[:providers].each do |provider|
            score = @results[:f1_score][provider][:by_query_type][query_type] || 0
            if score > best_score
              best_score = score
              best_provider = provider
            end
          end
          
          return best_provider if best_provider
        end
        
        # If no quality metrics or tie, use latency
        if @results[:latency][:by_query_type][query_type].present?
          best_provider = nil
          best_latency = Float::INFINITY
          
          @options[:providers].each do |provider|
            provider_stats = @results[:latency][:by_provider][provider]
            next unless provider_stats && provider_stats[:avg] > 0
            
            if provider_stats[:avg] < best_latency
              best_latency = provider_stats[:avg]
              best_provider = provider
            end
          end
          
          return best_provider if best_provider
        end
        
        # Default to hybrid if available, otherwise first provider
        @options[:providers].include?(:hybrid) ? :hybrid : @options[:providers].first
      end
      
      # Rank providers for a query type
      # @param query_type [Symbol] Query type
      # @return [Array] Ordered list of providers from best to worst
      def rank_providers(query_type)
        # If we have quality metrics, rank by F1 score
        if @results[:f1_score].present?
          return @options[:providers].sort_by do |provider|
            -(@results[:f1_score][provider][:by_query_type][query_type] || 0)
          end
        end
        
        # Otherwise rank by latency
        @options[:providers].sort_by do |provider|
          provider_stats = @results[:latency][:by_provider][provider]
          provider_stats && provider_stats[:avg] > 0 ? provider_stats[:avg] : Float::INFINITY
        end
      end
      
      # Log a message
      # @param message [String] Message to log
      def log(message)
        puts "[HybridSearchBenchmark] #{message}" if @options[:verbose]
      end
    end
  end
end
