class DomainConfidenceManager
  # Default fallback chain size
  DEFAULT_MAX_DOMAINS = 3
  
  # Initialize with optional configuration
  def initialize(options = {})
    @confidence_scorer = options[:confidence_scorer] || ConfidenceScorer.new
    @max_domains = options[:max_domains] || DEFAULT_MAX_DOMAINS
  end
  
  # Main method to determine domain fallback chain for a query
  def determine_domains(query, organization_id, options = {})
    # Get available domains for this organization
    available_domains = get_available_domains(organization_id)
    
    # Skip if no domains available or if only the general domain exists
    general_domain = VectorEmbedding::DEFAULT_DOMAIN
    return [general_domain] if available_domains.blank? || 
      (available_domains.size == 1 && available_domains.first == general_domain)
    
    # Get organization threshold settings
    threshold_settings = get_org_threshold_settings(organization_id)
    
    # If domain fallback is disabled, only use initial domain detection
    unless threshold_settings[:enable_fallback]
      initial_domain, confidence = get_initial_domain(query, organization_id)
      return [initial_domain, general_domain].uniq
    end
    
    # Get initial domain detection for optimized scoring
    initial_domain, initial_confidence = get_initial_domain(query, organization_id)
    
    # Calculate comprehensive confidence score for initial domain
    initial_score = @confidence_scorer.calculate_score(
      query, initial_domain, organization_id, options
    )
    
    results = [{ domain: initial_domain, confidence: initial_score }]
    
    # If initial confidence is below the primary threshold, score other domains
    if initial_score[:score] < threshold_settings[:primary_threshold]
      # Score other available domains (excluding the already scored initial domain)
      other_domains = available_domains.reject { |d| d == initial_domain }
      
      other_domains.each do |domain|
        score = @confidence_scorer.calculate_score(query, domain, organization_id, options)
        results << { domain: domain, confidence: score }
      end
      
      # Sort by confidence score
      results.sort_by! { |r| -r[:confidence][:score] }
    end
    
    # Build fallback chain based on thresholds
    build_fallback_chain(results, threshold_settings, general_domain)
  end
  
  # Update success status for a domain in the confidence history
  def update_success_status(query, domain, organization_id, was_successful)
    # Find the most recent confidence score for this query/domain pair
    score = DomainConfidenceScore.where(
      query_text: query,
      domain: domain,
      organization_id: organization_id
    ).order(created_at: :desc).first
    
    # Update success status if found
    score.update(was_successful: was_successful) if score.present?
  end
  
  private
  
  # Get available domains for an organization
  def get_available_domains(organization_id)
    Organization.find(organization_id).vector_domains
  end
  
  # Get organization's threshold settings
  def get_org_threshold_settings(organization_id)
    org = Organization.find(organization_id)
    
    {
      primary_threshold: org.domain_confidence_primary_threshold || 0.7,
      secondary_threshold: org.domain_confidence_secondary_threshold || 0.4,
      enable_fallback: org.enable_domain_fallback.nil? ? true : org.enable_domain_fallback
    }
  end
  
  # Get initial domain detection from HaystackClient
  def get_initial_domain(query, organization_id)
    client = HaystackClient.new
    
    begin
      response = client.detect_domain(query, organization_id)
      
      if response.success? && response.data.present?
        domain = response.data['domain']
        confidence = response.data['confidence'].to_f
        
        return [domain, confidence]
      else
        Rails.logger.warn("Domain detection failed or returned no results")
        return [VectorEmbedding::DEFAULT_DOMAIN, 1.0]  # Default domain with high confidence as fallback
      end
    rescue => e
      Rails.logger.error("Error in domain detection: #{e.message}")
      return [VectorEmbedding::DEFAULT_DOMAIN, 1.0]  # Default domain with high confidence as fallback
    end
  end
  
  # Build the domain fallback chain based on confidence thresholds
  def build_fallback_chain(results, threshold_settings, general_domain)
    # Primary domains are those that exceed the primary threshold
    primary_domains = results
      .select { |r| r[:confidence][:score] >= threshold_settings[:primary_threshold] }
      .map { |r| r[:domain] }
    
    # Secondary domains are those that meet the secondary threshold
    secondary_domains = results
      .select do |r| 
        r[:confidence][:score] >= threshold_settings[:secondary_threshold] &&
        r[:confidence][:score] < threshold_settings[:primary_threshold]
      end
      .map { |r| r[:domain] }
    
    # Build fallback chain
    fallback_chain = primary_domains + secondary_domains
    
    # Always include the general domain as a last resort if it's not already in the chain
    fallback_chain << general_domain unless fallback_chain.include?(general_domain)
    
    # Limit chain length and ensure uniqueness
    fallback_chain.uniq.take(@max_domains)
  end
end
