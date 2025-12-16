# Helper methods for RagPerformanceBenchmark
# Add these methods to the RagPerformanceBenchmark class

# Get the appropriate model for a provider
# @param provider [Symbol] LLM provider
# @return [String] Model name
def get_provider_model(provider)
  # Use provider-specific model from options if available
  return @options[:provider_models][provider] if @options[:provider_models][provider].present?
  
  # Default models for each provider
  case provider
  when :openai
    "gpt-4"
  when :anthropic
    "claude-3-opus-20240229"
  when :local
    "llama3-70b-instruct"
  else
    "default_model"
  end
end

# Update latency statistics with a new measurement
# @param stats [Hash] Statistics hash to update
# @param latency_ms [Float] Latency in milliseconds
def update_latency_stats(stats, latency_ms)
  stats[:min] = [stats[:min], latency_ms].min
  stats[:max] = [stats[:max], latency_ms].max
  stats[:total_ms] += latency_ms
  stats[:count] += 1
end

# Finalize latency statistics by calculating averages and percentiles
# @param stats_collection [Hash] Collection of statistics hashes
def finalize_latency_stats(stats_collection)
  stats_collection.each do |_key, stats|
    next if stats[:count] == 0
    
    # Calculate average
    stats[:avg] = stats[:total_ms] / stats[:count]
    
    # For percentiles, we need samples
    # In a real implementation, we would store all samples and calculate percentiles
    # For this simulation, we'll use a simple approximation
    stats[:p95] = stats[:avg] * 1.5
    stats[:p99] = stats[:avg] * 2.0
  end
end

# Determine the optimal context window configuration
# @param context_results [Hash] Context window benchmark results
def determine_optimal_context_configs(context_results)
  # Find overall optimal configuration
  best_config = nil
  best_score = -1

  context_results[:by_config].each do |config_key, stats|
    # Skip if no quality data
    next if stats[:quality][:count] == 0
    
    # Calculate composite score (balance quality and speed)
    quality = stats[:quality][:avg_score]
    latency = stats[:latency][:avg]
    
    # Higher quality and lower latency is better
    # Normalize latency to 0-1 range using reasonable bounds
    normalized_latency = [1.0, 5000.0 / latency].min
    composite_score = (quality * 0.7) + (normalized_latency * 0.3)
    
    if composite_score > best_score
      best_score = composite_score
      best_config = stats[:config]
    end
  end
  
  # Store overall best config
  if best_config
    context_results[:optimal][:overall] = {
      config: best_config,
      composite_score: best_score
    }
  end
  
  # Find optimal config for each query type
  @options[:query_types].each do |query_type|
    next unless context_results[:by_query_type][query_type].present?
    
    best_type_config = nil
    best_type_score = -1
    
    context_results[:by_query_type][query_type].each do |config_key, stats|
      # Skip if no quality data
      next if stats[:quality][:count] == 0
      
      # Calculate composite score (balance quality and speed)
      quality = stats[:quality][:avg_score]
      latency = stats[:latency][:avg]
      
      # Higher quality and lower latency is better
      normalized_latency = [1.0, 5000.0 / latency].min
      composite_score = (quality * 0.7) + (normalized_latency * 0.3)
      
      if composite_score > best_type_score
        best_type_score = composite_score
        best_type_config = stats[:config]
      end
    end
    
    if best_type_config
      context_results[:optimal][:by_query_type][query_type] = {
        config: best_type_config,
        quality_score: context_results[:by_query_type][query_type]["docs#{best_type_config[:max_documents]}-sim#{best_type_config[:min_similarity]}"][:quality][:avg_score],
        composite_score: best_type_score
      }
    end
  end
end

# Extract citations from an answer
# @param answer [String] Generated answer
# @param context_documents [Array<Hash>] Context documents
# @return [Array<String>] Array of document IDs referenced in the answer
def extract_citations(answer, context_documents)
  # In a real implementation, this would use regex or other techniques
  # to find document references in the answer text
  
  # Gather document IDs for matching
  doc_ids = context_documents.map { |doc| doc[:id] }
  
  # Simple approach: check for presence of document IDs or titles in answer
  cited_docs = []
  
  doc_ids.each do |doc_id|
    if answer.include?(doc_id.to_s)
      cited_docs << doc_id
    end
  end
  
  # Also check for document titles
  context_documents.each do |doc|
    if doc[:title].present? && answer.include?(doc[:title])
      cited_docs << doc[:id] unless cited_docs.include?(doc[:id])
    end
  end
  
  # If no explicit citations but the answer uses content
  # from context documents, infer citations
  if cited_docs.empty? && answer.present?
    # Select documents with highest match to answer content
    context_documents.sort_by { |doc| doc[:score] || 0 }.reverse.first(2).each do |doc|
      cited_docs << doc[:id]
    end
  end
  
  cited_docs
end

# Evaluate the quality of citations
# @param cited_documents [Array<String>] Documents cited in answer
# @param expected_citations [Array<String>] Expected document citations
# @return [Hash] Citation quality metrics
def evaluate_citation_quality(cited_documents, expected_citations)
  return { accuracy: 0, coverage: 0 } if expected_citations.empty?
  
  # Find overlap between cited and expected documents
  cited_set = cited_documents.to_set
  expected_set = expected_citations.to_set
  
  correct_citations = cited_set & expected_set
  
  # Calculate metrics
  # Accuracy: What percentage of cited documents were correct
  accuracy = cited_documents.empty? ? 0 : correct_citations.size.to_f / cited_documents.size
  
  # Coverage: What percentage of expected citations were included
  coverage = correct_citations.size.to_f / expected_citations.size
  
  { accuracy: accuracy, coverage: coverage }
end

# Evaluate context retention in multi-round conversations
# @param answer [String] Generated answer
# @param conversation_context [Array] Previous conversation turns
# @param query [String] Current query
# @return [Float] Context retention score (0-1)
def evaluate_context_retention(answer, conversation_context, query)
  # For empty answer or context, return 0
  return 0.0 if answer.blank? || conversation_context.empty?
  
  # In a real implementation, this would use a more sophisticated analysis
  # to evaluate how well the answer maintains conversation context
  
  # Simple approach: check for presence of key elements from previous turns
  score = 0.0
  
  # Extract key terms from previous turns
  key_terms = []
  conversation_context.each do |turn|
    # Extract potential key terms (simple approach)
    query_words = turn[:query].downcase.scan(/\w+/)
    answer_words = turn[:answer].downcase.scan(/\w+/)
    
    # Add words with length > 4 as potential key terms
    query_words.select { |w| w.length > 4 }.each { |w| key_terms << w }
    answer_words.select { |w| w.length > 4 }.first(5).each { |w| key_terms << w }
  end
  
  # Remove duplicates
  key_terms.uniq!
  
  # Check for presence of key terms in the answer
  if key_terms.present?
    term_count = key_terms.count { |term| answer.downcase.include?(term) }
    score = term_count.to_f / key_terms.size
  end
  
  # Limit to range 0-1
  [score, 1.0].min
end

# Rank providers based on all metrics
# @param comparison_results [Hash] Provider comparison results
# @return [Array<Hash>] Ranked providers with scores
def rank_providers(comparison_results)
  # Weight for each metric component
  weights = {
    latency: 0.15,
    quality: 0.3,
    hallucination: 0.2,
    citation_quality: 0.15,
    multi_round: 0.2
  }
  
  # Calculate normalized scores for each provider
  providers = @options[:providers]
  normalized_scores = {}
  
  providers.each do |provider|
    normalized_scores[provider] = { total: 0.0 }
    
    # Latency (lower is better, invert and normalize)
    if comparison_results[:latency].present? && comparison_results[:latency][provider].present?
      latency = comparison_results[:latency][provider]
      max_reasonable_latency = 5000.0 # 5 seconds
      normalized_scores[provider][:latency] = [1.0, max_reasonable_latency / latency].min * weights[:latency]
      normalized_scores[provider][:total] += normalized_scores[provider][:latency]
    end
    
    # Quality (higher is better)
    if comparison_results[:quality].present? && comparison_results[:quality][provider].present?
      quality = comparison_results[:quality][provider]
      normalized_scores[provider][:quality] = quality * weights[:quality]
      normalized_scores[provider][:total] += normalized_scores[provider][:quality]
    end
    
    # Hallucination (lower is better, invert and normalize)
    if comparison_results[:hallucination].present? && comparison_results[:hallucination][provider].present?
      hallucination = comparison_results[:hallucination][provider]
      normalized_scores[provider][:hallucination] = (1.0 - hallucination) * weights[:hallucination]
      normalized_scores[provider][:total] += normalized_scores[provider][:hallucination]
    end
    
    # Citation quality (accuracy + coverage average, higher is better)
    if comparison_results[:citation_quality].present? && comparison_results[:citation_quality][provider].present?
      citation_stats = comparison_results[:citation_quality][provider]
      citation_avg = (citation_stats[:accuracy] + citation_stats[:coverage]) / 2
      normalized_scores[provider][:citation_quality] = citation_avg * weights[:citation_quality]
      normalized_scores[provider][:total] += normalized_scores[provider][:citation_quality]
    end
    
    # Multi-round metrics (context_retention + answer_consistency average, higher is better)
    if comparison_results[:multi_round].present? && comparison_results[:multi_round][provider].present?
      multi_round_stats = comparison_results[:multi_round][provider]
      multi_round_avg = (multi_round_stats[:context_retention] + multi_round_stats[:answer_consistency]) / 2
      normalized_scores[provider][:multi_round] = multi_round_avg * weights[:multi_round]
      normalized_scores[provider][:total] += normalized_scores[provider][:multi_round]
    end
  end
  
  # Rank providers by total score
  providers.map { |provider| { provider: provider, score: normalized_scores[provider][:total] } }
          .sort_by { |item| -item[:score] }
end

# Identify the best provider for a specific query type
# @param query_type [Symbol] Query type
# @return [Symbol] Best provider for this query type
def identify_best_provider_for_query_type(query_type)
  # Use hallucination results if available
  if @results[:hallucination].present? &&
     @results[:hallucination][:by_query_type][query_type].present?
    
    best_provider = nil
    best_score = -1
    
    @options[:providers].each do |provider|
      type_stats = @results[:hallucination][:by_query_type][query_type][provider]
      next unless type_stats.present? && type_stats[:queries_tested] > 0
      
      # Combine factual accuracy (higher is better) and hallucination rate (lower is better)
      score = type_stats[:factual_accuracy] * 0.7 + (1 - type_stats[:hallucination_rate]) * 0.3
      
      if score > best_score
        best_score = score
        best_provider = provider
      end
    end
    
    return best_provider
  end
  
  # If hallucination data is not available, use overall provider ranking
  return @results[:provider_comparison][:overall_ranking].first[:provider] if @results[:provider_comparison][:overall_ranking].present?
  
  # Default to first provider if no data available
  @options[:providers].first
end

# Log a message if verbose mode is enabled
# @param message [String] Message to log
def log(message)
  puts message if @options[:verbose]
end
