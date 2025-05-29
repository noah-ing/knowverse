class ConfidenceScorer
  # Default weights for each confidence factor
  DEFAULT_WEIGHTS = {
    semantic: 0.4,
    corpus: 0.25,
    query_chars: 0.15,
    historical: 0.2
  }.freeze
  
  # Initialize with optional configuration
  def initialize(options = {})
    @weights = options[:weights] || DEFAULT_WEIGHTS
    normalize_weights
  end
  
  # Calculate comprehensive confidence score for a domain given a query
  def calculate_score(query, domain, organization_id, options = {})
    scores = {}
    
    # 1. Semantic similarity score (from HaystackClient domain detection)
    scores[:semantic] = fetch_semantic_similarity(query, domain, organization_id)
    
    # 2. Corpus coverage analysis
    scores[:corpus] = calculate_corpus_coverage(query, domain, organization_id)
    
    # 3. Query characteristics evaluation
    scores[:query_chars] = evaluate_query_characteristics(query, domain)
    
    # 4. Historical performance (if available)
    scores[:historical] = fetch_historical_performance(query, domain, organization_id)
    
    # Calculate weighted aggregate score
    weighted_score = calculate_weighted_score(scores)
    
    # Track this score for future analysis (unless disabled)
    unless options[:skip_tracking]
      track_confidence_score(query, domain, organization_id, scores, weighted_score, options[:tracking_metadata])
    end
    
    {
      score: weighted_score,
      factors: scores,
      domain: domain
    }
  end
  
  private
  
  # Ensure weights sum to 1.0
  def normalize_weights
    total = @weights.values.sum
    @weights.each_key { |k| @weights[k] = @weights[k] / total } if total > 0
  end
  
  # Get semantic similarity from the HaystackClient
  def fetch_semantic_similarity(query, domain, organization_id)
    client = HaystackClient.new
    response = client.detect_domain_similarity(query, domain, organization_id)
    
    if response.success? && response.data.present?
      similarity = response.data['similarity'].to_f
      # Clamp between 0 and 1 to ensure valid score
      [0.0, [similarity, 1.0].min].max
    else
      # Default to a neutral score if we couldn't get similarity
      0.5
    end
  rescue => e
    Rails.logger.error("Error fetching semantic similarity: #{e.message}")
    0.5 # Default neutral score on error
  end
  
  # Calculate corpus coverage for given domain and query
  def calculate_corpus_coverage(query, domain, organization_id)
    # Split query into terms for analysis
    terms = query.downcase.split(/\W+/).reject(&:empty?)
    return 0.5 if terms.empty? # Default score for empty query
    
    # Get domain vectors count
    org = Organization.find(organization_id)
    domain_vectors_count = count_domain_vectors(org, domain)
    total_vectors_count = count_all_vectors(org)
    
    # Calculate domain vector density
    domain_density = total_vectors_count > 0 ? domain_vectors_count.to_f / total_vectors_count : 0
    
    # Adjust based on domain size relative to corpus
    if domain_density >= 0.25
      # Large domains get higher confidence
      0.7 + (domain_density * 0.3) # Maps 0.25 -> 0.775, 1.0 -> 1.0
    elsif domain_density >= 0.1
      # Medium domains get moderate confidence
      0.5 + (domain_density * 0.8) # Maps 0.1 -> 0.58, 0.25 -> 0.7
    else
      # Small domains get lower baseline confidence
      0.3 + (domain_density * 2.0) # Maps 0.0 -> 0.3, 0.1 -> 0.5
    end
  rescue => e
    Rails.logger.error("Error calculating corpus coverage: #{e.message}")
    0.5 # Default neutral score on error
  end
  
  # Count vectors for a specific domain
  def count_domain_vectors(organization, domain)
    organization.documents
      .joins(:vector_embeddings)
      .where(vector_embeddings: { domain: domain })
      .count
  end
  
  # Count all vectors for this organization
  def count_all_vectors(organization)
    organization.documents
      .joins(:vector_embeddings)
      .count
  end
  
  # Evaluate query characteristics for domain fit
  def evaluate_query_characteristics(query, domain)
    # Get domain keywords if available
    domain_keywords = fetch_domain_keywords(domain)
    
    # If we don't have domain keywords, use a neutral score
    return 0.5 if domain_keywords.blank?
    
    # Tokenize query
    query_tokens = query.downcase.split(/\W+/).reject(&:empty?)
    return 0.5 if query_tokens.empty?
    
    # Count matches with domain keywords
    matches = query_tokens.count { |token| domain_keywords.include?(token) }
    
    # Calculate match percentage with a length factor
    # This rewards longer queries with more matches
    length_factor = [1.0, query_tokens.size / 3.0].min # Cap at 1.0
    match_percentage = query_tokens.size > 0 ? matches.to_f / query_tokens.size : 0
    
    # Combine factors for final score
    [0.3 + (match_percentage * 0.5) + (length_factor * 0.2), 1.0].min
  rescue => e
    Rails.logger.error("Error evaluating query characteristics: #{e.message}")
    0.5 # Default neutral score on error
  end
  
  # Fetch domain-specific keywords
  def fetch_domain_keywords(domain)
    DomainKeywordCache.keywords_for(domain) || []
  end
  
  # Cache class for domain keywords to avoid repeated calculation
  class DomainKeywordCache
    @cache = {}
    @cache_expiry = 30.minutes
    @last_updated = {}
    
    def self.keywords_for(domain)
      # Refresh cache if needed
      if @cache[domain].nil? || @last_updated[domain].nil? || @last_updated[domain] < Time.now - @cache_expiry
        @cache[domain] = calculate_keywords_for_domain(domain)
        @last_updated[domain] = Time.now
      end
      
      @cache[domain]
    end
    
    def self.calculate_keywords_for_domain(domain)
      # In a real implementation, this would extract keywords from domain documents
      # For now, return an empty array
      []
    end
    
    def self.clear_cache
      @cache = {}
      @last_updated = {}
    end
  end
  
  # Get historical performance data for this domain
  def fetch_historical_performance(query, domain, organization_id)
    # Check similar historical queries
    similar_scores = DomainConfidenceScore.where(
      domain: domain,
      organization_id: organization_id
    ).where('created_at > ?', 7.days.ago).order(created_at: :desc).limit(20)
    
    # Not enough historical data
    return 0.5 if similar_scores.count < 5
    
    # Calculate success rate for this domain
    success_count = similar_scores.count { |s| s.was_successful }
    success_rate = similar_scores.size > 0 ? success_count.to_f / similar_scores.size : 0
    
    # Calculate average historical score
    avg_score = similar_scores.map(&:total_score).sum.to_f / similar_scores.size
    
    # Combine metrics with preference for recent success rate
    (success_rate * 0.6) + (avg_score * 0.4)
  rescue => e
    Rails.logger.error("Error fetching historical performance: #{e.message}")
    0.5 # Default neutral score on error
  end
  
  # Calculate weighted score from individual factor scores
  def calculate_weighted_score(scores)
    # Apply weights to each factor
    weighted_sum = 0.0
    @weights.each do |factor, weight|
      weighted_sum += (scores[factor] || 0.5) * weight
    end
    
    # Ensure score is between 0 and 1
    [0.0, [weighted_sum, 1.0].min].max
  end
  
  # Track confidence score for future analysis
  def track_confidence_score(query, domain, organization_id, scores, weighted_score, metadata = {})
    DomainConfidenceScore.create!(
      organization_id: organization_id,
      query_text: query,
      domain: domain,
      total_score: weighted_score,
      semantic_similarity: scores[:semantic],
      corpus_coverage: scores[:corpus],
      query_characteristics: scores[:query_chars],
      historical_performance: scores[:historical],
      factor_scores: {
        semantic_factor: @weights[:semantic],
        corpus_factor: @weights[:corpus],
        query_factor: @weights[:query_chars],
        historical_factor: @weights[:historical]
      },
      was_successful: metadata[:was_successful] # May be nil initially
    )
  rescue => e
    Rails.logger.error("Error tracking confidence score: #{e.message}")
    # Non-critical error, don't raise exception
  end
end
