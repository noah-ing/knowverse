# frozen_string_literal: true

module Distributed
  module Benchmark
    # Specialized benchmark class for RAG (Retrieval-Augmented Generation) performance testing
    class RagPerformanceBenchmark
      attr_reader :results, :options
      
      # Types of queries for benchmark testing
      QUERY_TYPES = {
        factoid: 'Simple factual questions with clear answers',
        semantic: 'Questions requiring semantic understanding',
        multi_hop: 'Questions requiring information from multiple sources',
        ambiguous: 'Questions with multiple interpretations',
        complex: 'Complex multi-part questions',
        specialized: 'Domain-specific terminology questions',
        follow_up: 'Follow-up questions requiring context from previous interactions'
      }.freeze
      
      # LLM providers to benchmark
      PROVIDERS = {
        openai: 'OpenAI',
        anthropic: 'Anthropic',
        local: 'Local LLM'
      }.freeze
      
      # Context window configurations to test
      CONTEXT_WINDOW_CONFIGS = [
        { max_documents: 1, min_similarity: 0.8 },
        { max_documents: 3, min_similarity: 0.8 },
        { max_documents: 5, min_similarity: 0.8 },
        { max_documents: 8, min_similarity: 0.8 },
        { max_documents: 10, min_similarity: 0.8 },
        { max_documents: 5, min_similarity: 0.9 },
        { max_documents: 5, min_similarity: 0.7 },
        { max_documents: 5, min_similarity: 0.6 }
      ].freeze

      # Initialize a new benchmark with options
      # @param options [Hash] Benchmark configuration options
      def initialize(options = {})
        @options = {
          # Test corpus settings
          organization_id: options[:organization_id],
          query_count: options[:query_count] || 30,
          query_types: options[:query_types] || QUERY_TYPES.keys,
          
          # RAG settings
          providers: options[:providers] || PROVIDERS.keys,
          context_window_configs: options[:context_window_configs] || CONTEXT_WINDOW_CONFIGS,
          provider_models: options[:provider_models] || {},
          
          # Measurement settings
          use_labeled_data: options[:use_labeled_data] || false,
          labeled_data: options[:labeled_data] || [],
          
          # RAG specific testing options
          test_hallucination: options.key?(:test_hallucination) ? options[:test_hallucination] : true,
          test_citation_quality: options.key?(:test_citation_quality) ? options[:test_citation_quality] : true,
          test_multi_round: options.key?(:test_multi_round) ? options[:test_multi_round] : true,
          
          # Output settings
          output_file: options[:output_file],
          verbose: options[:verbose] || true
        }
        
        @results = {
          config: @options.dup,
          latency: {},
          context_window: {},
          provider_comparison: {},
          hallucination: {},
          citation_quality: {},
          multi_round: {}
        }
        
        @test_corpus = nil
      end
      
      # Run all benchmark tests
      # @return [Hash] Benchmark results
      def run_all
        load_test_corpus
        
        run_latency_benchmark
        run_context_window_benchmark
        
        if @options[:test_hallucination]
          run_hallucination_benchmark
        end
        
        if @options[:test_citation_quality]
          run_citation_quality_benchmark
        end
        
        if @options[:test_multi_round]
          run_multi_round_benchmark
        end
        
        run_provider_comparison
        
        save_results if @options[:output_file]
        
        @results
      end
      
      # Run the latency benchmark
      # @return [Hash] Latency results by query type and provider
      def run_latency_benchmark
        log "Running RAG latency benchmark with #{@test_corpus.size} queries..."
        
        latency_results = {
          by_provider: {},
          by_query_type: {}
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
        
        # Default context window configuration for this test
        default_config = @options[:context_window_configs].first
        
        # Run latency tests
        @test_corpus.each do |test_query|
          query_text = test_query[:query]
          query_type = test_query[:type]
          
          @options[:providers].each do |provider|
            log "Testing RAG latency for '#{query_text}' with provider #{provider}..." if @options[:verbose]
            
            model = get_provider_model(provider)
            
            # Time the RAG operation
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            
            execute_rag(
              query_text,
              provider,
              model,
              default_config[:max_documents],
              default_config[:min_similarity]
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
        
        @results[:latency] = latency_results
        latency_results
      end
      
      # Run context window optimization benchmark
      # @return [Hash] Context window optimization results
      def run_context_window_benchmark
        log "Running context window optimization benchmark..."
        
        context_results = {
          by_config: {},
          by_query_type: {},
          optimal: {
            overall: nil,
            by_query_type: {}
          }
        }
        
        # Select a subset of typical queries for this test
        test_queries = select_representative_queries(10)
        
        # Test each context window configuration
        @options[:context_window_configs].each do |config|
          max_documents = config[:max_documents]
          min_similarity = config[:min_similarity]
          config_key = "docs#{max_documents}-sim#{min_similarity}"
          
          context_results[:by_config][config_key] = {
            config: config,
            latency: {
              avg: 0,
              min: Float::INFINITY,
              max: 0,
              count: 0,
              total_ms: 0
            },
            quality: {
              avg_score: 0,
              count: 0
            }
          }
          
          # Select a default provider for consistency
          provider = @options[:providers].first
          model = get_provider_model(provider)
          
          test_queries.each do |test_query|
            query_text = test_query[:query]
            query_type = test_query[:type]
            
            log "Testing context config (docs:#{max_documents}/sim:#{min_similarity}) for '#{query_text}'..." if @options[:verbose]
            
            # Time the RAG operation
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            
            rag_result = execute_rag(
              query_text,
              provider,
              model,
              max_documents,
              min_similarity
            )
            
            end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            latency_ms = (end_time - start_time) * 1000
            
            # Update latency stats
            update_latency_stats(context_results[:by_config][config_key][:latency], latency_ms)
            
            # Evaluate answer quality if we have ground truth
            if test_query[:expected_answer].present?
              quality_score = evaluate_answer_quality(rag_result[:answer], test_query[:expected_answer])
              context_results[:by_config][config_key][:quality][:avg_score] += quality_score
              context_results[:by_config][config_key][:quality][:count] += 1
            end
            
            # Initialize query type data if needed
            context_results[:by_query_type][query_type] ||= {}
            context_results[:by_query_type][query_type][config_key] ||= {
              config: config,
              latency: {
                avg: 0,
                min: Float::INFINITY,
                max: 0,
                count: 0,
                total_ms: 0
              },
              quality: {
                avg_score: 0,
                count: 0
              }
            }
            
            # Update query type specific stats
            update_latency_stats(context_results[:by_query_type][query_type][config_key][:latency], latency_ms)
            
            if test_query[:expected_answer].present?
              quality_score = evaluate_answer_quality(rag_result[:answer], test_query[:expected_answer])
              context_results[:by_query_type][query_type][config_key][:quality][:avg_score] += quality_score
              context_results[:by_query_type][query_type][config_key][:quality][:count] += 1
            end
          end
          
          # Finalize config stats
          finalize_latency_stats({ config_key => context_results[:by_config][config_key][:latency] })
          
          # Finalize quality score
          quality_count = context_results[:by_config][config_key][:quality][:count]
          if quality_count > 0
            context_results[:by_config][config_key][:quality][:avg_score] /= quality_count
          end
        end
        
        # Finalize query type stats
        @options[:query_types].each do |query_type|
          next unless context_results[:by_query_type][query_type].present?
          
          context_results[:by_query_type][query_type].each do |config_key, stats|
            finalize_latency_stats({ config_key => stats[:latency] })
            
            quality_count = stats[:quality][:count]
            if quality_count > 0
              stats[:quality][:avg_score] /= quality_count
            end
          end
        end
        
        # Determine optimal context window configuration
        determine_optimal_context_configs(context_results)
        
        @results[:context_window] = context_results
        context_results
      end
      
      # Run hallucination benchmark
      # @return [Hash] Hallucination measurement results
      def run_hallucination_benchmark
        log "Running hallucination benchmark..."
        
        hallucination_results = {
          by_provider: {},
          by_query_type: {}
        }
        
        # Skip if no factual queries with expected answers
        factual_queries = @test_corpus.select { |q| q[:expected_answer].present? }
        if factual_queries.empty?
          log "Warning: No queries with expected answers available for hallucination testing"
          return hallucination_results
        end
        
        # Initialize result structure for each provider
        @options[:providers].each do |provider|
          hallucination_results[:by_provider][provider] = {
            hallucination_rate: 0,
            factual_accuracy: 0,
            queries_tested: 0
          }
        end
        
        # Initialize result structure for each query type
        @options[:query_types].each do |query_type|
          hallucination_results[:by_query_type][query_type] = {}
          
          @options[:providers].each do |provider|
            hallucination_results[:by_query_type][query_type][provider] = {
              hallucination_rate: 0,
              factual_accuracy: 0,
              queries_tested: 0
            }
          end
        end
        
        # Default context window configuration for this test
        default_config = @options[:context_window_configs].first
        
        # Test each provider with factual queries
        factual_queries.each do |test_query|
          query_text = test_query[:query]
          query_type = test_query[:type]
          expected_answer = test_query[:expected_answer]
          
          @options[:providers].each do |provider|
            log "Testing hallucination for '#{query_text}' with provider #{provider}..." if @options[:verbose]
            
            model = get_provider_model(provider)
            
            # Execute RAG
            rag_result = execute_rag(
              query_text,
              provider,
              model,
              default_config[:max_documents],
              default_config[:min_similarity]
            )
            
            # Check for hallucination
            hallucination_score = measure_hallucination(
              rag_result[:answer],
              expected_answer,
              rag_result[:context_documents]
            )
            
            # Measure factual accuracy
            factual_accuracy = evaluate_answer_quality(rag_result[:answer], expected_answer)
            
            # Update provider stats
            hallucination_results[:by_provider][provider][:hallucination_rate] += hallucination_score
            hallucination_results[:by_provider][provider][:factual_accuracy] += factual_accuracy
            hallucination_results[:by_provider][provider][:queries_tested] += 1
            
            # Update query type stats
            hallucination_results[:by_query_type][query_type][provider][:hallucination_rate] += hallucination_score
            hallucination_results[:by_query_type][query_type][provider][:factual_accuracy] += factual_accuracy
            hallucination_results[:by_query_type][query_type][provider][:queries_tested] += 1
          end
        end
        
        # Calculate average hallucination rate and factual accuracy for each provider
        @options[:providers].each do |provider|
          queries_tested = hallucination_results[:by_provider][provider][:queries_tested]
          if queries_tested > 0
            hallucination_results[:by_provider][provider][:hallucination_rate] /= queries_tested
            hallucination_results[:by_provider][provider][:factual_accuracy] /= queries_tested
          end
        end
        
        # Calculate average hallucination rate and factual accuracy for each query type
        @options[:query_types].each do |query_type|
          @options[:providers].each do |provider|
            queries_tested = hallucination_results[:by_query_type][query_type][provider][:queries_tested]
            if queries_tested > 0
              hallucination_results[:by_query_type][query_type][provider][:hallucination_rate] /= queries_tested
              hallucination_results[:by_query_type][query_type][provider][:factual_accuracy] /= queries_tested
            end
          end
        end
        
        @results[:hallucination] = hallucination_results
        hallucination_results
      end
      
      # Run citation quality benchmark
      # @return [Hash] Citation quality results
      def run_citation_quality_benchmark
        log "Running citation quality benchmark..."
        
        citation_results = {
          by_provider: {},
          by_query_type: {}
        }
        
        # Skip if no queries with expected citations
        citation_queries = @test_corpus.select { |q| q[:expected_citations].present? }
        if citation_queries.empty?
          log "Warning: No queries with expected citations available for citation testing"
          return citation_results
        end
        
        # Initialize result structure for each provider
        @options[:providers].each do |provider|
          citation_results[:by_provider][provider] = {
            citation_accuracy: 0,
            citation_coverage: 0,
            queries_tested: 0
          }
        end
        
        # Initialize result structure for each query type
        @options[:query_types].each do |query_type|
          citation_results[:by_query_type][query_type] = {}
          
          @options[:providers].each do |provider|
            citation_results[:by_query_type][query_type][provider] = {
              citation_accuracy: 0,
              citation_coverage: 0,
              queries_tested: 0
            }
          end
        end
        
        # Default context window configuration for this test
        default_config = @options[:context_window_configs].first
        
        # Test each provider with citation queries
        citation_queries.each do |test_query|
          query_text = test_query[:query]
          query_type = test_query[:type]
          expected_citations = test_query[:expected_citations]
          
          @options[:providers].each do |provider|
            log "Testing citation quality for '#{query_text}' with provider #{provider}..." if @options[:verbose]
            
            model = get_provider_model(provider)
            
            # Execute RAG
            rag_result = execute_rag(
              query_text,
              provider,
              model,
              default_config[:max_documents],
              default_config[:min_similarity]
            )
            
            # Extract cited documents from the answer
            cited_documents = extract_citations(rag_result[:answer], rag_result[:context_documents])
            
            # Evaluate citation accuracy and coverage
            citation_metrics = evaluate_citation_quality(cited_documents, expected_citations)
            
            # Update provider stats
            citation_results[:by_provider][provider][:citation_accuracy] += citation_metrics[:accuracy]
            citation_results[:by_provider][provider][:citation_coverage] += citation_metrics[:coverage]
            citation_results[:by_provider][provider][:queries_tested] += 1
            
            # Update query type stats
            citation_results[:by_query_type][query_type][provider][:citation_accuracy] += citation_metrics[:accuracy]
            citation_results[:by_query_type][query_type][provider][:citation_coverage] += citation_metrics[:coverage]
            citation_results[:by_query_type][query_type][provider][:queries_tested] += 1
          end
        end
        
        # Calculate average citation metrics for each provider
        @options[:providers].each do |provider|
          queries_tested = citation_results[:by_provider][provider][:queries_tested]
          if queries_tested > 0
            citation_results[:by_provider][provider][:citation_accuracy] /= queries_tested
            citation_results[:by_provider][provider][:citation_coverage] /= queries_tested
          end
        end
        
        # Calculate average citation metrics for each query type
        @options[:query_types].each do |query_type|
          @options[:providers].each do |provider|
            queries_tested = citation_results[:by_query_type][query_type][provider][:queries_tested]
            if queries_tested > 0
              citation_results[:by_query_type][query_type][provider][:citation_accuracy] /= queries_tested
              citation_results[:by_query_type][query_type][provider][:citation_coverage] /= queries_tested
            end
          end
        end
        
        @results[:citation_quality] = citation_results
        citation_results
      end
      
      # Run multi-round evaluation benchmark
      # @return [Hash] Multi-round evaluation results
      def run_multi_round_benchmark
        log "Running multi-round evaluation benchmark..."
        
        multi_round_results = {
          by_provider: {},
          conversations: {}
        }
        
        # Skip if no multi-round conversations
        conversation_sets = @test_corpus.select { |q| q[:conversation].present? }
        if conversation_sets.empty?
          log "Warning: No multi-round conversations available for testing"
          return multi_round_results
        end
        
        # Initialize result structure for each provider
        @options[:providers].each do |provider|
          multi_round_results[:by_provider][provider] = {
            context_retention: 0,
            answer_consistency: 0,
            conversations_tested: 0
          }
        end
        
        # Default context window configuration for this test
        default_config = @options[:context_window_configs].first
        
        # Test each conversation set with each provider
        conversation_sets.each_with_index do |conversation_set, idx|
          conversation_id = conversation_set[:id] || "conversation_#{idx}"
          conversation = conversation_set[:conversation]
          
          multi_round_results[:conversations][conversation_id] = {
            by_provider: {}
          }
          
          @options[:providers].each do |provider|
            log "Testing multi-round conversation #{conversation_id} with provider #{provider}..." if @options[:verbose]
            
            model = get_provider_model(provider)
            conversation_context = []
            
            # Track metrics for this conversation
            context_retention_scores = []
            answer_consistency_scores = []
            
            # Process each turn in the conversation
            conversation.each_with_index do |turn, turn_idx|
              query_text = turn[:query]
              expected_answer = turn[:expected_answer]
              
              log "  Turn #{turn_idx + 1}: '#{query_text}'" if @options[:verbose]
              
              # Execute RAG with conversation context
              rag_result = execute_rag_with_history(
                query_text,
                provider,
                model,
                default_config[:max_documents],
                default_config[:min_similarity],
                conversation_context
              )
              
              # Evaluate context retention
              context_retention = evaluate_context_retention(
                rag_result[:answer],
                conversation_context,
                query_text
              )
              context_retention_scores << context_retention
              
              # Evaluate answer consistency if we have an expected answer
              if expected_answer.present?
                answer_consistency = evaluate_answer_quality(rag_result[:answer], expected_answer)
                answer_consistency_scores << answer_consistency
              end
              
              # Update conversation context for next turn
              conversation_context << {
                query: query_text,
                answer: rag_result[:answer]
              }
            end
            
            # Calculate average metrics for this conversation
            avg_context_retention = context_retention_scores.sum.to_f / context_retention_scores.size
            avg_answer_consistency = answer_consistency_scores.empty? ? 0 : answer_consistency_scores.sum.to_f / answer_consistency_scores.size
            
            # Store results for this provider and conversation
            multi_round_results[:conversations][conversation_id][:by_provider][provider] = {
              context_retention: avg_context_retention,
              answer_consistency: avg_answer_consistency,
              turns: conversation.size
            }
            
            # Update provider stats
            multi_round_results[:by_provider][provider][:context_retention] += avg_context_retention
            multi_round_results[:by_provider][provider][:answer_consistency] += avg_answer_consistency
            multi_round_results[:by_provider][provider][:conversations_tested] += 1
          end
        end
        
        # Calculate average multi-round metrics for each provider
        @options[:providers].each do |provider|
          conversations_tested = multi_round_results[:by_provider][provider][:conversations_tested]
          if conversations_tested > 0
            multi_round_results[:by_provider][provider][:context_retention] /= conversations_tested
            multi_round_results[:by_provider][provider][:answer_consistency] /= conversations_tested
          end
        end
        
        @results[:multi_round] = multi_round_results
        multi_round_results
      end
      
      # Run benchmark comparing different RAG providers
      # @return [Hash] Provider comparison results
      def run_provider_comparison
        log "Running provider comparison benchmark..."
        
        comparison_results = {
          latency: {},
          quality: {},
          hallucination: {},
          citation_quality: {},
          multi_round: {},
          overall_ranking: {}
        }
        
        # Compare latency if available
        if @results[:latency].present?
          @options[:providers].each do |provider|
            comparison_results[:latency][provider] = @results[:latency][:by_provider][provider][:avg]
          end
        end
        
        # Compare answer quality from hallucination tests if available
        if @results[:hallucination].present?
          @options[:providers].each do |provider|
            comparison_results[:quality][provider] = @results[:hallucination][:by_provider][provider][:factual_accuracy]
            comparison_results[:hallucination][provider] = @results[:hallucination][:by_provider][provider][:hallucination_rate]
          end
        end
        
        # Compare citation quality if available
        if @results[:citation_quality].present?
          @options[:providers].each do |provider|
            comparison_results[:citation_quality][provider] = {
              accuracy: @results[:citation_quality][:by_provider][provider][:citation_accuracy],
              coverage: @results[:citation_quality][:by_provider][provider][:citation_coverage]
            }
          end
        end
        
        # Compare multi-round metrics if available
        if @results[:multi_round].present?
          @options[:providers].each do |provider|
            comparison_results[:multi_round][provider] = {
              context_retention: @results[:multi_round][:by_provider][provider][:context_retention],
              answer_consistency: @results[:multi_round][:by_provider][provider][:answer_consistency]
            }
          end
        end
        
        # Create overall ranking
        comparison_results[:overall_ranking] = rank_providers(comparison_results)
        
        @results[:provider_comparison] = comparison_results
        comparison_results
      end
      
      # Generate a report of benchmark results
      # @return [String] Markdown-formatted report
      def generate_report
        report = "# KnowVerse RAG Performance Benchmark Report\n\n"
        
        report += "## Configuration\n\n"
        report += "- **Query Count**: #{@options[:query_count]} queries\n"
        report += "- **Query Types**: #{@options[:query_types].join(', ')}\n"
        report += "- **Providers Tested**: #{@options[:providers].join(', ')}\n"
        report += "- **Context Window Configurations**: #{@options[:context_window_configs].size} configurations\n\n"
        
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
        end
        
        # Context Window Results
        if @results[:context_window].present?
          report += "## Context Window Optimization Results\n\n"
          
          # Optimal configurations
          if @results[:context_window][:optimal][:overall].present?
            optimal_config = @results[:context_window][:optimal][:overall][:config]
            report += "### Optimal Context Window Configuration\n\n"
            report += "- **Max Documents**: #{optimal_config[:max_documents]}\n"
            report += "- **Min Similarity**: #{optimal_config[:min_similarity]}\n\n"
          end
          
          # By configuration
          report += "### Performance by Context Window Configuration\n\n"
          report += "| Max Documents | Min Similarity | Avg Latency (ms) | Quality Score |\n"
          report += "|---------------|---------------|-----------------|---------------|\n"
          
          @results[:context_window][:by_config].each do |config_key, stats|
            config = stats[:config]
            report += "| #{config[:max_documents]} | #{config[:min_similarity]} | #{stats[:latency][:avg]&.round(2)} | #{(stats[:quality][:avg_score] * 100).round(2)}% |\n"
          end
          report += "\n"
          
          # Optimal by query type
          report += "### Optimal Configuration by Query Type\n\n"
          report += "| Query Type | Max Documents | Min Similarity | Quality Score |\n"
          report += "|------------|---------------|---------------|---------------|\n"
          
          @results[:context_window][:optimal][:by_query_type].each do |query_type, data|
            if data.present?
              config = data[:config]
              report += "| #{query_type} | #{config[:max_documents]} | #{config[:min_similarity]} | #{(data[:quality_score] * 100).round(2)}% |\n"
            end
          end
          report += "\n"
        end
        
        # Hallucination Results
        if @results[:hallucination].present?
          report += "## Hallucination Measurement Results\n\n"
          
          report += "### Hallucination by Provider\n\n"
          report += "| Provider | Hallucination Rate | Factual Accuracy |\n"
          report += "|----------|-------------------|------------------|\n"
          
          @results[:hallucination][:by_provider].each do |provider, stats|
            report += "| #{provider} | #{(stats[:hallucination_rate] * 100).round(2)}% | #{(stats[:factual_accuracy] * 100).round(2)}% |\n"
          end
          report += "\n"
          
          report += "### Hallucination by Query Type\n\n"
          
          @options[:query_types].each do |query_type|
            if @results[:hallucination][:by_query_type][query_type].present?
              report += "#### #{query_type.to_s.capitalize} Queries\n\n"
              report += "| Provider | Hallucination Rate | Factual Accuracy |\n"
              report += "|----------|-------------------|------------------|\n"
              
              @options[:providers].each do |provider|
                stats = @results[:hallucination][:by_query_type][query_type][provider]
                if stats.present? && stats[:queries_tested] > 0
                  report += "| #{provider} | #{(stats[:hallucination_rate] * 100).round(2)}% | #{(stats[:factual_accuracy] * 100).round(2)}% |\n"
                end
              end
              report += "\n"
            end
          end
        end
        
        # Citation Quality Results
        if @results[:citation_quality].present?
          report += "## Citation Quality Results\n\n"
          
          report += "### Citation Quality by Provider\n\n"
          report += "| Provider | Citation Accuracy | Citation Coverage |\n"
          report += "|----------|-------------------|------------------|\n"
          
          @results[:citation_quality][:by_provider].each do |provider, stats|
            report += "| #{provider} | #{(stats[:citation_accuracy] * 100).round(2)}% | #{(stats[:citation_coverage] * 100).round(2)}% |\n"
          end
          report += "\n"
        end
        
        # Multi-round Results
        if @results[:multi_round].present?
          report += "## Multi-round Evaluation Results\n\n"
          
          report += "### Multi-round Performance by Provider\n\n"
          report += "| Provider | Context Retention | Answer Consistency |\n"
          report += "|----------|-------------------|-------------------|\n"
          
          @results[:multi_round][:by_provider].each do |provider, stats|
            report += "| #{provider} | #{(stats[:context_retention] * 100).round(2)}% | #{(stats[:answer_consistency] * 100).round(2)}% |\n"
          end
          report += "\n"
        end
        
        # Provider Comparison
        if @results[:provider_comparison].present?
          report += "## Provider Comparison\n\n"
          
          report += "### Overall Provider Ranking\n\n"
          report += "| Rank | Provider | Composite Score |\n"
          report += "|------|----------|----------------|\n"
          
          @results[:provider_comparison][:overall_ranking].each_with_index do |item, idx|
            provider = item[:provider]
            score = item[:score]
            report += "| #{idx + 1} | #{provider} | #{score.round(2)} |\n"
          end
          report += "\n"
          
          # Provider by metric
          report += "### Provider Comparison by Metric\n\n"
          report += "| Provider | Latency (ms) | Answer Quality | Hallucination Rate | Citation Quality | Context Retention |\n"
          report += "|----------|--------------|---------------|-------------------|-----------------|------------------|\n"
          
          @options[:providers].each do |provider|
            latency = @results[:provider_comparison][:latency][provider]&.round(2) || "N/A"
            quality = @results[:provider_comparison][:quality][provider] ? "#{(@results[:provider_comparison][:quality][provider] * 100).round(2)}%" : "N/A"
            hallucination = @results[:provider_comparison][:hallucination][provider] ? "#{(@results[:provider_comparison][:hallucination][provider] * 100).round(2)}%" : "N/A"
            
            citation_quality = "N/A"
            if @results[:provider_comparison][:citation_quality][provider].present?
              citation_stats = @results[:provider_comparison][:citation_quality][provider]
              citation_avg = (citation_stats[:accuracy] + citation_stats[:coverage]) / 2
              citation_quality = "#{(citation_avg * 100).round(2)}%"
            end
            
            context_retention = "N/A"
            if @results[:provider_comparison][:multi_round][provider].present?
              context_stats = @results[:provider_comparison][:multi_round][provider]
              context_retention = "#{(context_stats[:context_retention] * 100).round(2)}%"
            end
            
            report += "| #{provider} | #{latency} | #{quality} | #{hallucination} | #{citation_quality} | #{context_retention} |\n"
          end
          report += "\n"
        end
        
        # Recommendations
        report += "## Recommendations\n\n"
        
        # Provider recommendations
        if @results[:provider_comparison].present? && @results[:provider_comparison][:overall_ranking].present?
          best_provider = @results[:provider_comparison][:overall_ranking].first[:provider]
          report += "### Provider Selection Recommendations\n\n"
          report += "- For general RAG use, the **#{best_provider}** provider delivers the best overall performance\n"
          
          # Provider recommendations by query type
          report += "\n### Provider Selection by Query Type\n\n"
          
          @options[:query_types].each do |query_type|
            best_provider_for_type = identify_best_provider_for_query_type(query_type)
            if best_provider_for_type
              report += "- For #{query_type} queries, use the **#{best_provider_for_type}** provider for best results\n"
            end
          end
          report += "\n"
        end
        
        # Context window recommendations
        if @results[:context_window].present? && @results[:context_window][:optimal][:overall].present?
          optimal_config = @results[:context_window][:optimal][:overall][:config]
          
          report += "### Context Window Recommendations\n\n"
          report += "- For general RAG use, set max_documents to **#{optimal_config[:max_documents]}** and min_similarity to **#{optimal_config[:min_similarity]}**\n"
          
          # Context window recommendations by query type
          @results[:context_window][:optimal][:by_query_type].each do |query_type, data|
            if data.present?
              config = data[:config]
              report += "- For #{query_type} queries, set max_documents to **#{config[:max_documents]}** and min_similarity to **#{config[:min_similarity]}**\n"
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
        
        # Add some multi-round conversations
        if @options[:test_multi_round] && @options[:query_types].include?(:follow_up)
          @test_corpus << generate_conversation(1)
          @test_corpus << generate_conversation(2)
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
                         "What is the maximum document size supported in KnowVerse?",
                         "How many vector dimensions are available in the system?",
                         "What is the default embedding model used?",
                         "When was the first version of KnowVerse released?",
                         "What database does KnowVerse use for vector storage?"
                       ]
                       factoid_queries[index % factoid_queries.size]
                     when :semantic
                       semantic_queries = [
                         "Explain how vector search works in the context of document retrieval",
                         "What are the benefits of using hybrid search over pure vector search?",
                         "How does the system ensure documents are properly indexed?",
                         "What techniques help improve search relevance for domain-specific queries?",
                         "How does the system handle multilingual documents?"
                       ]
                       semantic_queries[index % semantic_queries.size]
                     when :multi_hop
                       multi_hop_queries = [
                         "What embedding models are supported, and which one is best for scientific documents?",
                         "How does distributed architecture improve performance, and what are its limitations?",
                         "What's the relationship between document size and processing time, and how can performance be optimized?",
                         "How do vector projections work for visualization, and which algorithms provide the best clustering?",
                         "What techniques are used for context window optimization, and how do they affect answer quality?"
                       ]
                       multi_hop_queries[index % multi_hop_queries.size]
                     when :ambiguous
                       ambiguous_queries = [
                         "vector model",
                         "embedding support",
                         "database configuration",
                         "memory requirements",
                         "system architecture"
                       ]
                       ambiguous_queries[index % ambiguous_queries.size]
                     when :complex
                       complex_queries = [
                         "What are the tradeoffs between using higher-dimension embedding models vs. performance, and how does this impact search quality in large document collections?",
                         "How does the distributed architecture handle shard rebalancing during node failures while maintaining search functionality, and what are the recovery time expectations?",
                         "Compare the effectiveness of different context window sizes for technical vs. general content, and explain how semantic complexity affects optimal window size",
                         "What mechanisms ensure tenant isolation in multi-organization deployments while maximizing resource utilization, and how does this scale with organization size?",
                         "Analyze the impact of domain-specific fine-tuning on embedding quality for specialized fields like medicine or law, and what preprocessing steps yield the best results"
                       ]
                       complex_queries[index % complex_queries.size]
                     when :specialized
                       specialized_queries = [
                         "What SIMD optimizations are implemented in HNSW search?",
                         "How does the pgvector extension's cosine distance implementation compare to L2 distance for semantic search?",
                         "What techniques are used for reducing the dimensionality of embedding vectors?",
                         "How does the Raft consensus algorithm ensure data consistency across distributed nodes?",
                         "What methods are used for quantization of high-dimensional vectors?"
                       ]
                       specialized_queries[index % specialized_queries.size]
                     when :follow_up
                       follow_up_queries = [
                         "What are the supported embedding dimensions?",
                         "Which one has the best performance?",
                         "How much memory does it require?",
                         "Can it be used with the distributed architecture?",
                         "Does it support incremental updates?"
                       ]
                       follow_up_queries[index % follow_up_queries.size]
                     else
                       "Default query #{index}"
                     end
        
        # Create query hash
        {
          query: "#{base_query}",
          type: query_type,
          complexity: query_complexity(query_type),
          expected_answer: generate_expected_answer(base_query, query_type),
          expected_citations: generate_expected_citations(query_type)
        }
      end
      
      # Generate a synthetic test conversation
      # @param index [Integer] Index for unique conversation generation
      # @return [Hash] Conversation hash with sequence of queries and expected answers
      def generate_conversation(index)
        case index
        when 1
          {
            id: "embedding_conversation_#{index}",
            conversation: [
              {
                query: "What embedding models are available in KnowVerse?",
                expected_answer: "KnowVerse supports multiple embedding models with various dimensions: Mini (384d), Small (768d), Base (1024d), Large (1536d), and XL (2048d). Each offers different tradeoffs between performance and accuracy."
              },
              {
                query: "Which one has the best accuracy?",
                expected_answer: "The XL (2048d) model generally offers the best accuracy among KnowVerse's embedding models, followed by the Large (1536d) model. However, higher dimension models require more computational resources and memory."
              },
              {
                query: "What about performance considerations?",
                expected_answer: "For performance considerations, larger dimension models (XL and Large) require more computational resources and memory, resulting in slower query times. The Mini (384d) and Small (768d) models offer faster performance with lower memory requirements, making them suitable for applications where query speed is critical or resources are limited."
              },
              {
                query: "Are there domain-specific versions of these models?",
                expected_answer: "Yes, KnowVerse supports domain-specific fine-tuning of embedding models. The platform can create specialized versions of any base embedding model (Mini through XL) that are optimized for particular domains like medical, legal, or technical documentation. These domain-specific models typically provide better accuracy for queries within their specialized field."
              }
            ]
          }
        when 2
          {
            id: "search_architecture_conversation_#{index}",
            conversation: [
              {
                query: "How does KnowVerse's distributed architecture work?",
                expected_answer: "KnowVerse's distributed architecture uses a Raft consensus algorithm for coordination across multiple nodes. It implements sharding to distribute vector indexes across nodes, with each shard handling a subset of organizations or document collections to ensure scalability and fault tolerance."
              },
              {
                query: "What happens if a node fails?",
                expected_answer: "When a node fails in KnowVerse's distributed architecture, the system automatically detects the failure through its Raft-based health monitoring. Leader election occurs if the failed node was a leader, and the system redirects queries to available nodes. Data recovery happens automatically from replicated shards, with the recovery time depending on the shard size and network conditions."
              },
              {
                query: "Does this affect search performance?",
                expected_answer: "Yes, node failures can temporarily affect search performance. During recovery, there may be increased latency as queries are redirected to remaining nodes that take on additional load. The distributed index might operate with reduced redundancy until recovery completes, potentially causing slightly lower search quality or slower response times. However, the system prioritizes availability, so searches continue to function even during node failures."
              }
            ]
          }
        else
          {
            id: "default_conversation_#{index}",
            conversation: [
              {
                query: "What is KnowVerse?",
                expected_answer: "KnowVerse is a multi-tenant, AI-powered knowledge base platform that enables businesses to ingest, index, and search their documents with semantic search and contextual Q&A capabilities."
              },
              {
                query: "How does it handle document processing?",
                expected_answer: "KnowVerse processes documents through a pipeline that includes text extraction, embedding generation, and indexing. Documents are uploaded via the web interface, processed by background workers, and their text is embedded using various models. These embeddings are stored in a vector database (PostgreSQL with pgvector) and indexed for fast retrieval with HNSW."
              }
            ]
          }
        end
      end
      
      # Select representative queries from the corpus for detailed testing
      # @param count [Integer] Number of queries to select
      # @return [Array<Hash>] Selected queries
      def select_representative_queries(count)
        return @test_corpus.sample(count) if @test_corpus.size <= count
        
        # Try to get diverse query types
        selected = []
        
        # Select queries with expected answers first
        with_answers = @test_corpus.select { |q| q[:expected_answer].present? }
        if with_answers.present?
          # Group by query type
          by_type = with_answers.group_by { |q| q[:type] }
          
          # Select from each type
          @options[:query_types].each do |type|
            next unless by_type[type].present?
            
            # Take 1-2 queries from each type
            type_queries = by_type[type].sample([2, by_type[type].size].min)
            selected.concat(type_queries)
            
            break if selected.size >= count
          end
        end
        
        # If we still need more, take random samples
        if selected.size < count
          remaining = @test_corpus - selected
          selected.concat(remaining.sample(count - selected.size))
        end
        
        # Return at most the requested count
        selected.first(count)
      end
      
      # Generate an expected answer for a query (for synthetic test data)
      # @param query [String] The query
      # @param query_type [Symbol] Type of query
      # @return [String] Expected answer or nil if not available
      def generate_expected_answer(query, query_type)
        # Only generate for factoid and simple questions
        return nil unless [:factoid, :semantic].include?(query_type)
        
        case query
        when /maximum document size/i
          "The maximum document size supported in KnowVerse is 100MB for individual documents. However, for optimal performance, documents under 10MB are recommended."
        when /vector dimensions/i
          "KnowVerse supports multiple embedding dimensions: 384, 768, 1024, 1536, and 2048, corresponding to Mini, Small, Base, Large, and XL models respectively."
        when /default embedding model/i
          "The default embedding model used in KnowVerse is the Base model with 1024 dimensions, which provides a good balance between performance and accuracy."
        when /database/i
          "KnowVerse uses PostgreSQL with the pgvector extension for vector storage, providing both SQL capabilities and vector similarity search in a single database."
        when /vector search/i
          "Vector search works by converting documents and queries into high-dimensional vectors that represent semantic meaning. These vectors are compared using distance metrics like cosine similarity to find documents with similar meaning, even when they don't share exact keywords."
        when /hybrid search/i
          "Hybrid search combines vector-based semantic search with traditional keyword search methods. The benefits include improved accuracy for queries with specific terms, better handling of both semantic and exact matching requirements, and enhanced relevance for mixed query types."
        else
          nil
        end
      end
      
      # Generate expected citations for a query (for synthetic test data)
      # @param query_type [Symbol] Type of query
      # @return [Array<String>] Expected document citations or nil if not available
      def generate_expected_citations(query_type)
        # Only add expected citations to some query types
        return nil unless [:factoid, :semantic].include?(query_type)
        
        # This would normally contain real document IDs from the corpus
        # For synthetic data, we're just adding placeholders
        ["doc_123", "doc_456", "doc_789"].sample(rand(1..3))
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
        when :multi_hop, :complex, :specialized, :follow_up
          :complex
        else
          :medium
        end
      end
      
      # Execute RAG with the specified provider and context settings
      # @param query_text [String] Query text
      # @param provider [Symbol] LLM provider
      # @param model [String] Model name
      # @param max_documents [Integer] Maximum number of documents to retrieve
      # @param min_similarity [Float] Minimum similarity threshold
      # @return [Hash] RAG result with answer and context
      def execute_rag(query_text, provider, model, max_documents, min_similarity)
        # This would normally call the actual RAG system
        # For benchmark testing, we're simulating the call
        
        # In a real implementation, this would call:
        # haystack_client.generate_answer(query_text, @options[:organization_id], {
        #   provider: provider.to_s,
        #   model: model,
        #   max_documents: max_documents,
        #   min_similarity: min_similarity,
        #   retrieval_strategy: "auto"
        # })
        
        # Simulate latency based on provider and model
        sleep(simulate_rag_latency(provider, model))
        
        # Generate a simulated answer
        {
          answer: simulate_rag_answer(query_text, provider),
          context_documents: simulate_context_documents(max_documents),
          metadata: {
            provider: provider,
            model: model,
            context_window: {
              max_documents: max_documents,
              min_similarity: min_similarity
            }
          }
        }
      end
      
      # Execute RAG with conversation history
      # @param query_text [String] Query text
      # @param provider [Symbol] LLM provider
      # @param model [String] Model name
      # @param max_documents [Integer] Maximum number of documents to retrieve
      # @param min_similarity [Float] Minimum similarity threshold
      # @param conversation_context [Array] Previous conversation turns
      # @return [Hash] RAG result with answer and context
      def execute_rag_with_history(query_text, provider, model, max_documents, min_similarity, conversation_context)
        # This would normally call the actual RAG system with conversation history
        # For benchmark testing, we're simulating the call
        
        # Simulate increased latency for multi-turn conversations
        sleep(simulate_rag_latency(provider, model) * (1 + 0.2 * conversation_context.size))
        
        # Generate a simulated answer that considers conversation context
        {
          answer: simulate_rag_answer_with_history(query_text, provider, conversation_context),
          context_documents: simulate_context_documents(max_documents),
          metadata: {
            provider: provider,
            model: model,
            context_window: {
              max_documents: max_documents,
              min_similarity: min_similarity
            },
            conversation_turn: conversation_context.size + 1
          }
        }
      end
      
      # Simulate latency for RAG operations
      # @param provider [Symbol] LLM provider
      # @param model [String] Model name
      # @return [Float] Simulated latency in seconds
      def simulate_rag_latency(provider, model)
        base_latency = case provider
                       when :openai
                         0.8
                       when :anthropic
                         1.2
                       when :local
                         2.0
                       else
                         1.0
                       end
        
        # Add some randomness
        jitter = rand * 0.3
        
        # Model complexity factor
        model_factor = model.to_s.include?('large') ? 1.5 : 1.0
        
        base_latency * model_factor + jitter
      end
      
      # Simulate RAG answer for testing
      # @param query [String] Query text
      # @param provider [Symbol] LLM provider
      # @return [String] Simulated answer
      def simulate_rag_answer(query, provider)
        answers = [
          "Based on the provided context, KnowVerse supports multiple embedding dimensions ranging from 384 to 2048, corresponding to different model sizes from Mini to XL.",
          "The document indicates that PostgreSQL with pgvector extension is used for vector storage, allowing both traditional SQL operations and vector similarity search.",
          "According to the documentation, hybrid search combines vector-based semantic search with keyword search to improve results for mixed query types.",
          "The context information shows that KnowVerse uses a distributed architecture with Raft consensus for coordination across nodes.",
          "The documentation explains that documents are processed through a pipeline including text extraction, embedding generation, and HNSW indexing for optimal search performance."
        ]
        
        # Add some provider-specific characteristics
        prefix = case provider
                when :openai
                  "I'll answer based on the information in the context. "
                when :anthropic
                  "Based on the provided context, I can tell you that "
                when :local
                  "According to the provided documents, "
                else
                  ""
                end
        
        prefix + answers.sample
      end
      
      # Simulate RAG answer with conversation history
      # @param query [String] Query text
      # @param provider [Symbol] LLM provider
      # @param conversation_context [Array] Previous conversation turns
      # @return [String] Simulated answer considering context
      def simulate_rag_answer_with_history(query, provider, conversation_context)
        # For follow-up questions, reference previous context
        previous_topics = conversation_context.map { |turn| turn[:query] }.join(", ")
        
        "Following up on our discussion about #{previous_topics}, #{simulate_rag_answer(query, provider)}"
      end
      
      # Simulate context documents
      # @param count [Integer] Number of documents to simulate
      # @return [Array<Hash>] Simulated context documents
      def simulate_context_documents(count)
        documents = []
        
        count.times do |i|
          documents << {
            id: "doc_#{100 + i}",
            title: "KnowVerse Documentation #{i+1}",
            text: "This is simulated document content for testing RAG performance. It contains information about document processing, vector search, and distributed architecture in KnowVerse.",
            score: 0.9 - (i * 0.05)
          }
        end
        
        documents
      end
      
      # Evaluate the quality of an answer against an expected answer
      # @param answer [String] Generated answer
      # @param expected_answer [String] Expected answer
      # @return [Float] Quality score (0-1)
      def evaluate_answer_quality(answer, expected_answer)
        return 0.0 if answer.blank? || expected_answer.blank?
        
        # This would normally use a more sophisticated evaluation
        # For benchmark testing, we're using a simple token overlap approach
        
        # Tokenize both answers (simple word-based tokenization)
        answer_tokens = answer.downcase.scan(/\w+/)
        expected_tokens = expected_answer.downcase.scan(/\w+/)
        
        # Calculate overlap
        common_tokens = answer_tokens & expected_tokens
        overlap = common_tokens.size.to_f / expected_tokens.size
        
        # Limit to range 0-1
        [overlap, 1.0].min
      end
      
      # Measure hallucination in a generated answer
      # @param answer [String] Generated answer
      # @param expected_answer [String] Expected answer
      # @param context_documents [Array<Hash>] Context documents used for generation
      # @return [Float] Hallucination score (0-1, higher means more hallucination)
      def measure_hallucination(answer, expected_answer, context_documents)
        return 0.5 if answer.blank? # Assume moderate hallucination if no answer
        
        # In a real implementation, this would compare answer factuality with context
        # For benchmark testing, we're using a simple heuristic
        
        # Extract context text
        context_text = context_documents.map { |doc| doc[:text] }.join(" ")
        
        # Calculate how much the answer relies on information not in the context
        # This is a simplistic approach - real hallucination detection is more complex
        answer_tokens = answer.downcase.scan(/\w+/)
        context_tokens = context_text.downcase.scan(/\w+/)
        expected_tokens = expected_answer&.downcase&.scan(/\w+/) || []
        
        # Calculate tokens in answer not found in context or expected answer
        not_in_context = answer_tokens - context_tokens - expected_tokens
        hallucination_rate = not_in_context.size.to_f / answer_tokens.size
        
        # Limit to range 0-1
        [
# frozen_string_literal: true

module Distributed
  module Benchmark
    # Specialized benchmark class for RAG (Retrieval-Augmented Generation) performance testing
    class RagPerformanceBenchmark
      attr_reader :results, :options
      
      # Types of queries for benchmark testing
      QUERY_TYPES = {
        factoid: 'Simple factual questions with clear answers',
        semantic: 'Questions requiring semantic understanding',
        multi_hop: 'Questions requiring information from multiple sources',
        ambiguous: 'Questions with multiple interpretations',
        complex: 'Complex multi-part questions',
        specialized: 'Domain-specific terminology questions',
        follow_up: 'Follow-up questions requiring context from previous interactions'
      }.freeze
      
      # LLM providers to benchmark
      PROVIDERS = {
        openai: 'OpenAI',
        anthropic: 'Anthropic',
        local: 'Local LLM'
      }.freeze
      
      # Context window configurations to test
      CONTEXT_WINDOW_CONFIGS = [
        { max_documents: 1, min_similarity: 0.8 },
        { max_documents: 3, min_similarity: 0.8 },
        { max_documents: 5, min_similarity: 0.8 },
        { max_documents: 8, min_similarity: 0.8 },
        { max_documents: 10, min_similarity: 0.8 },
        { max_documents: 5, min_similarity: 0.9 },
        { max_documents: 5, min_similarity: 0.7 },
        { max_documents: 5, min_similarity: 0.6 }
      ].freeze

      # Initialize a new benchmark with options
      # @param options [Hash] Benchmark configuration options
      def initialize(options = {})
        @options = {
          # Test corpus settings
          organization_id: options[:organization_id],
          query_count: options[:query_count] || 30,
          query_types: options[:query_types] || QUERY_TYPES.keys,
          
          # RAG settings
          providers: options[:providers] || PROVIDERS.keys,
          context_window_configs: options[:context_window_configs] || CONTEXT_WINDOW_CONFIGS,
          provider_models: options[:provider_models] || {},
          
          # Measurement settings
          use_labeled_data: options[:use_labeled_data] || false,
          labeled_data: options[:labeled_data] || [],
          
          # RAG specific testing options
          test_hallucination: options.key?(:test_hallucination) ? options[:test_hallucination] : true,
          test_citation_quality: options.key?(:test_citation_quality) ? options[:test_citation_quality] : true,
          test_multi_round: options.key?(:test_multi_round) ? options[:test_multi_round] : true,
          
          # Output settings
          output_file: options[:output_file],
          verbose: options[:verbose] || true
        }
        
        @results = {
          config: @options.dup,
          latency: {},
          context_window: {},
          provider_comparison: {},
          hallucination: {},
          citation_quality: {},
          multi_round: {}
        }
        
        @test_corpus = nil
      end
      
      # Run all benchmark tests
      # @return [Hash] Benchmark results
      def run_all
        load_test_corpus
        
        run_latency_benchmark
        run_context_window_benchmark
        
        if @options[:test_hallucination]
          run_hallucination_benchmark
        end
        
        if @options[:test_citation_quality]
          run_citation_quality_benchmark
        end
        
        if @options[:test_multi_round]
          run_multi_round_benchmark
        end
        
        run_provider_comparison
        
        save_results if @options[:output_file]
        
        @results
      end
      
      # Run the latency benchmark
      # @return [Hash] Latency results by query type and provider
      def run_latency_benchmark
        log "Running RAG latency benchmark with #{@test_corpus.size} queries..."
        
        latency_results = {
          by_provider: {},
          by_query_type: {}
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
        
        # Default context window configuration for this test
        default_config = @options[:context_window_configs].first
        
        # Run latency tests
        @test_corpus.each do |test_query|
          query_text = test_query[:query]
          query_type = test_query[:type]
          
          @options[:providers].each do |provider|
            log "Testing RAG latency for '#{query_text}' with provider #{provider}..." if @options[:verbose]
            
            model = get_provider_model(provider)
            
            # Time the RAG operation
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            
            execute_rag(
              query_text,
              provider,
              model,
              default_config[:max_documents],
              default_config[:min_similarity]
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
        
        @results[:latency] = latency_results
        latency_results
      end
      
      # Run context window optimization benchmark
      # @return [Hash] Context window optimization results
      def run_context_window_benchmark
        log "Running context window optimization benchmark..."
        
        context_results = {
          by_config: {},
          by_query_type: {},
          optimal: {
            overall: nil,
            by_query_type: {}
          }
        }
        
        # Select a subset of typical queries for this test
        test_queries = select_representative_queries(10)
        
        # Test each context window configuration
        @options[:context_window_configs].each do |config|
          max_documents = config[:max_documents]
          min_similarity = config[:min_similarity]
          config_key = "docs#{max_documents}-sim#{min_similarity}"
          
          context_results[:by_config][config_key] = {
            config: config,
            latency: {
              avg: 0,
              min: Float::INFINITY,
              max: 0,
              count: 0,
              total_ms: 0
            },
            quality: {
              avg_score: 0,
              count: 0
            }
          }
          
          # Select a default provider for consistency
          provider = @options[:providers].first
          model = get_provider_model(provider)
          
          test_queries.each do |test_query|
            query_text = test_query[:query]
            query_type = test_query[:type]
            
            log "Testing context config (docs:#{max_documents}/sim:#{min_similarity}) for '#{query_text}'..." if @options[:verbose]
            
            # Time the RAG operation
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            
            rag_result = execute_rag(
              query_text,
              provider,
              model,
              max_documents,
              min_similarity
            )
            
            end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            latency_ms = (end_time - start_time) * 1000
            
            # Update latency stats
            update_latency_stats(context_results[:by_config][config_key][:latency], latency_ms)
            
            # Evaluate answer quality if we have ground truth
            if test_query[:expected_answer].present?
              quality_score = evaluate_answer_quality(rag_result[:answer], test_query[:expected_answer])
              context_results[:by_config][config_key][:quality][:avg_score] += quality_score
              context_results[:by_config][config_key][:quality][:count] += 1
            end
            
            # Initialize query type data if needed
            context_results[:by_query_type][query_type] ||= {}
            context_results[:by_query_type][query_type][config_key] ||= {
              config: config,
              latency: {
                avg: 0,
                min: Float::INFINITY,
                max: 0,
                count: 0,
                total_ms: 0
              },
              quality: {
                avg_score: 0,
                count: 0
              }
            }
            
            # Update query type specific stats
            update_latency_stats(context_results[:by_query_type][query_type][config_key][:latency], latency_ms)
            
            if test_query[:expected_answer].present?
              quality_score = evaluate_answer_quality(rag_result[:answer], test_query[:expected_answer])
              context_results[:by_query_type][query_type][config_key][:quality][:avg_score] += quality_score
              context_results[:by_query_type][query_type][config_key][:quality][:count] += 1
            end
          end
          
          # Finalize config stats
          finalize_latency_stats({ config_key => context_results[:by_config][config_key][:latency] })
          
          # Finalize quality score
          quality_count = context_results[:by_config][config_key][:quality][:count]
          if quality_count > 0
            context_results[:by_config][config_key][:quality][:avg_score] /= quality_count
          end
        end
        
        # Finalize query type stats
        @options[:query_types].each do |query_type|
          next unless context_results[:by_query_type][query_type].present?
          
          context_results[:by_query_type][query_type].each do |config_key, stats|
            finalize_latency_stats({ config_key => stats[:latency] })
            
            quality_count = stats[:quality][:count]
            if quality_count > 0
              stats[:quality][:avg_score] /= quality_count
            end
          end
        end
        
        # Determine optimal context window configuration
        determine_optimal_context_configs(context_results)
        
        @results[:context_window] = context_results
        context_results
      end
      
      # Run hallucination benchmark
      # @return [Hash] Hallucination measurement results
      def run_hallucination_benchmark
        log "Running hallucination benchmark..."
        
        hallucination_results = {
          by_provider: {},
          by_query_type: {}
        }
        
        # Skip if no factual queries with expected answers
        factual_queries = @test_corpus.select { |q| q[:expected_answer].present? }
        if factual_queries.empty?
          log "Warning: No queries with expected answers available for hallucination testing"
          return hallucination_results
        end
        
        # Initialize result structure for each provider
        @options[:providers].each do |provider|
          hallucination_results[:by_provider][provider] = {
            hallucination_rate: 0,
            factual_accuracy: 0,
            queries_tested: 0
          }
        end
        
        # Initialize result structure for each query type
        @options[:query_types].each do |query_type|
          hallucination_results[:by_query_type][query_type] = {}
          
          @options[:providers].each do |provider|
            hallucination_results[:by_query_type][query_type][provider] = {
              hallucination_rate: 0,
              factual_accuracy: 0,
              queries_tested: 0
            }
          end
        end
        
        # Default context window configuration for this test
        default_config = @options[:context_window_configs].first
        
        # Test each provider with factual queries
        factual_queries.each do |test_query|
          query_text = test_query[:query]
          query_type = test_query[:type]
          expected_answer = test_query[:expected_answer]
          
          @options[:providers].each do |provider|
            log "Testing hallucination for '#{query_text}' with provider #{provider}..." if @options[:verbose]
            
            model = get_provider_model(provider)
            
            # Execute RAG
            rag_result = execute_rag(
              query_text,
              provider,
              model,
              default_config[:max_documents],
              default_config[:min_similarity]
            )
            
            # Check for hallucination
            hallucination_score = measure_hallucination(
              rag_result[:answer],
              expected_answer,
              rag_result[:context_documents]
            )
            
            # Measure factual accuracy
            factual_accuracy = evaluate_answer_quality(rag_result[:answer], expected_answer)
            
            # Update provider stats
            hallucination_results[:by_provider][provider][:hallucination_rate] += hallucination_score
            hallucination_results[:by_provider][provider][:factual_accuracy] += factual_accuracy
            hallucination_results[:by_provider][provider][:queries_tested] += 1
            
            # Update query type stats
            hallucination_results[:by_query_type][query_type][provider][:hallucination_rate] += hallucination_score
            hallucination_results[:by_query_type][query_type][provider][:factual_accuracy] += factual_accuracy
            hallucination_results[:by_query_type][query_type][provider][:queries_tested] += 1
          end
        end
        
        # Calculate average hallucination rate and factual accuracy for each provider
        @options[:providers].each do |provider|
          queries_tested = hallucination_results[:by_provider][provider][:queries_tested]
          if queries_tested > 0
            hallucination_results[:by_provider][provider][:hallucination_rate] /= queries_tested
            hallucination_results[:by_provider][provider][:factual_accuracy] /= queries_tested
          end
        end
        
        # Calculate average hallucination rate and factual accuracy for each query type
        @options[:query_types].each do |query_type|
          @options[:providers].each do |provider|
            queries_tested = hallucination_results[:by_query_type][query_type][provider][:queries_tested]
            if queries_tested > 0
              hallucination_results[:by_query_type][query_type][provider][:hallucination_rate] /= queries_tested
              hallucination_results[:by_query_type][query_type][provider][:factual_accuracy] /= queries_tested
            end
          end
        end
        
        @results[:hallucination] = hallucination_results
        hallucination_results
      end
      
      # Run citation quality benchmark
      # @return [Hash] Citation quality results
      def run_citation_quality_benchmark
        log "Running citation quality benchmark..."
        
        citation_results = {
          by_provider: {},
          by_query_type: {}
        }
        
        # Skip if no queries with expected citations
        citation_queries = @test_corpus.select { |q| q[:expected_citations].present? }
        if citation_queries.empty?
          log "Warning: No queries with expected citations available for citation testing"
          return citation_results
        end
        
        # Initialize result structure for each provider
        @options[:providers].each do |provider|
          citation_results[:by_provider][provider] = {
            citation_accuracy: 0,
            citation_coverage: 0,
            queries_tested: 0
          }
        end
        
        # Initialize result structure for each query type
        @options[:query_types].each do |query_type|
          citation_results[:by_query_type][query_type] = {}
          
          @options[:providers].each do |provider|
            citation_results[:by_query_type][query_type][provider] = {
              citation_accuracy: 0,
              citation_coverage: 0,
              queries_tested: 0
            }
          end
        end
        
        # Default context window configuration for this test
        default_config = @options[:context_window_configs].first
        
        # Test each provider with citation queries
        citation_queries.each do |test_query|
          query_text = test_query[:query]
          query_type = test_query[:type]
          expected_citations = test_query[:expected_citations]
          
          @options[:providers].each do |provider|
            log "Testing citation quality for '#{query_text}' with provider #{provider}..." if @options[:verbose]
            
            model = get_provider_model(provider)
            
            # Execute RAG
            rag_result = execute_rag(
              query_text,
              provider,
              model,
              default_config[:max_documents],
              default_config[:min_similarity]
            )
            
            # Extract cited documents from the answer
            cited_documents = extract_citations(rag_result[:answer], rag_result[:context_documents])
            
            # Evaluate citation accuracy and coverage
            citation_metrics = evaluate_citation_quality(cited_documents, expected_citations)
            
            # Update provider stats
            citation_results[:by_provider][provider][:citation_accuracy] += citation_metrics[:accuracy]
            citation_results[:by_provider][provider][:citation_coverage] += citation_metrics[:coverage]
            citation_results[:by_provider][provider][:queries_tested] += 1
            
            # Update query type stats
            citation_results[:by_query_type][query_type][provider][:citation_accuracy] += citation_metrics[:accuracy]
            citation_results[:by_query_type][query_type][provider][:citation_coverage] += citation_metrics[:coverage]
            citation_results[:by_query_type][query_type][provider][:queries_tested] += 1
          end
        end
        
        # Calculate average citation metrics for each provider
        @options[:providers].each do |provider|
          queries_tested = citation_results[:by_provider][provider][:queries_tested]
          if queries_tested > 0
            citation_results[:by_provider][provider][:citation_accuracy] /= queries_tested
            citation_results[:by_provider][provider][:citation_coverage] /= queries_tested
          end
        end
        
        # Calculate average citation metrics for each query type
        @options[:query_types].each do |query_type|
          @options[:providers].each do |provider|
            queries_tested = citation_results[:by_query_type][query_type][provider][:queries_tested]
            if queries_tested > 0
              citation_results[:by_query_type][query_type][provider][:citation_accuracy] /= queries_tested
              citation_results[:by_query_type][query_type][provider][:citation_coverage] /= queries_tested
            end
          end
        end
        
        @results[:citation_quality] = citation_results
        citation_results
      end
      
      # Run multi-round evaluation benchmark
      # @return [Hash] Multi-round evaluation results
      def run_multi_round_benchmark
        log "Running multi-round evaluation benchmark..."
        
        multi_round_results = {
          by_provider: {},
          conversations: {}
        }
        
        # Skip if no multi-round conversations
        conversation_sets = @test_corpus.select { |q| q[:conversation].present? }
        if conversation_sets.empty?
          log "Warning: No multi-round conversations available for testing"
          return multi_round_results
        end
        
        # Initialize result structure for each provider
        @options[:providers].each do |provider|
          multi_round_results[:by_provider][provider] = {
            context_retention: 0,
            answer_consistency: 0,
            conversations_tested: 0
          }
        end
        
        # Default context window configuration for this test
        default_config = @options[:context_window_configs].first
        
        # Test each conversation set with each provider
        conversation_sets.each_with_index do |conversation_set, idx|
          conversation_id = conversation_set[:id] || "conversation_#{idx}"
          conversation = conversation_set[:conversation]
          
          multi_round_results[:conversations][conversation_id] = {
            by_provider: {}
          }
          
          @options[:providers].each do |provider|
            log "Testing multi-round conversation #{conversation_id} with provider #{provider}..." if @options[:verbose]
            
            model = get_provider_model(provider)
            conversation_context = []
            
            # Track metrics for this conversation
            context_retention_scores = []
            answer_consistency_scores = []
            
            # Process each turn in the conversation
            conversation.each_with_index do |turn, turn_idx|
              query_text = turn[:query]
              expected_answer = turn[:expected_answer]
              
              log "  Turn #{turn_idx + 1}: '#{query_text}'" if @options[:verbose]
              
              # Execute RAG with conversation context
              rag_result = execute_rag_with_history(
                query_text,
                provider,
                model,
                default_config[:max_documents],
                default_config[:min_similarity],
                conversation_context
              )
              
              # Evaluate context retention
              context_retention = evaluate_context_retention(
                rag_result[:answer],
                conversation_context,
                query_text
              )
              context_retention_scores << context_retention
              
              # Evaluate answer consistency if we have an expected answer
              if expected_answer.present?
                answer_consistency = evaluate_answer_quality(rag_result[:answer], expected_answer)
                answer_consistency_scores << answer_consistency
              end
              
              # Update conversation context for next turn
              conversation_context << {
                query: query_text,
                answer: rag_result[:answer]
              }
            end
            
            # Calculate average metrics for this conversation
            avg_context_retention = context_retention_scores.sum.to_f / context_retention_scores.size
            avg_answer_consistency = answer_consistency_scores.empty? ? 0 : answer_consistency_scores.sum.to_f / answer_consistency_scores.size
            
            # Store results for this provider and conversation
            multi_round_results[:conversations][conversation_id][:by_provider][provider] = {
              context_retention: avg_context_retention,
              answer_consistency: avg_answer_consistency,
              turns: conversation.size
            }
            
            # Update provider stats
            multi_round_results[:by_provider][provider][:context_retention] += avg_context_retention
            multi_round_results[:by_provider][provider][:answer_consistency] += avg_answer_consistency
            multi_round_results[:by_provider][provider][:conversations_tested] += 1
          end
        end
        
        # Calculate average multi-round metrics for each provider
        @options[:providers].each do |provider|
          conversations_tested = multi_round_results[:by_provider][provider][:conversations_tested]
          if conversations_tested > 0
            multi_round_results[:by_provider][provider][:context_retention] /= conversations_tested
            multi_round_results[:by_provider][provider][:answer_consistency] /= conversations_tested
          end
        end
        
        @results[:multi_round] = multi_round_results
        multi_round_results
      end
      
      # Run benchmark comparing different RAG providers
      # @return [Hash] Provider comparison results
      def run_provider_comparison
        log "Running provider comparison benchmark..."
        
        comparison_results = {
          latency: {},
          quality: {},
          hallucination: {},
          citation_quality: {},
          multi_round: {},
          overall_ranking: {}
        }
        
        # Compare latency if available
        if @results[:latency].present?
          @options[:providers].each do |provider|
            comparison_results[:latency][provider] = @results[:latency][:by_provider][provider][:avg]
          end
        end
        
        # Compare answer quality from hallucination tests if available
        if @results[:hallucination].present?
          @options[:providers].each do |provider|
            comparison_results[:quality][provider] = @results[:hallucination][:by_provider][provider][:factual_accuracy]
            comparison_results[:hallucination][provider] = @results[:hallucination][:by_provider][provider][:hallucination_rate]
          end
        end
        
        # Compare citation quality if available
        if @results[:citation_quality].present?
          @options[:providers].each do |provider|
            comparison_results[:citation_quality][provider] = {
              accuracy: @results[:citation_quality][:by_provider][provider][:citation_accuracy],
              coverage: @results[:citation_quality][:by_provider][provider][:citation_coverage]
            }
          end
        end
        
        # Compare multi-round metrics if available
        if @results[:multi_round].present?
          @options[:providers].each do |provider|
            comparison_results[:multi_round][provider] = {
              context_retention: @results[:multi_round][:by_provider][provider][:context_retention],
              answer_consistency: @results[:multi_round][:by_provider][provider][:answer_consistency]
            }
          end
        end
        
        # Create overall ranking
        comparison_results[:overall_ranking] = rank_providers(comparison_results)
        
        @results[:provider_comparison] = comparison_results
        comparison_results
      end
      
      # Generate a report of benchmark results
      # @return [String] Markdown-formatted report
      def generate_report
        report = "# KnowVerse RAG Performance Benchmark Report\n\n"
        
        report += "## Configuration\n\n"
        report += "- **Query Count**: #{@options[:query_count]} queries\n"
        report += "- **Query Types**: #{@options[:query_types].join(', ')}\n"
        report += "- **Providers Tested**: #{@options[:providers].join(', ')}\n"
        report += "- **Context Window Configurations**: #{@options[:context_window_configs].size} configurations\n\n"
        
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
        end
        
        # Context Window Results
        if @results[:context_window].present?
          report += "## Context Window Optimization Results\n\n"
          
          # Optimal configurations
          if @results[:context_window][:optimal][:overall].present?
            optimal_config = @results[:context_window][:optimal][:overall][:config]
            report += "### Optimal Context Window Configuration\n\n"
            report += "- **Max Documents**: #{optimal_config[:max_documents]}\n"
            report += "- **Min Similarity**: #{optimal_config[:min_similarity]}\n\n"
          end
          
          # By configuration
          report += "### Performance by Context Window Configuration\n\n"
          report += "| Max Documents | Min Similarity | Avg Latency (ms) | Quality Score |\n"
          report += "|---------------|---------------|-----------------|---------------|\n"
          
          @results[:context_window][:by_config].each do |config_key, stats|
            config = stats[:config]
            report += "| #{config[:max_documents]} | #{config[:min_similarity]} | #{stats[:latency][:avg]&.round(2)} | #{(stats[:quality][:avg_score] * 100).round(2)}% |\n"
          end
          report += "\n"
          
          # Optimal by query type
          report += "### Optimal Configuration
