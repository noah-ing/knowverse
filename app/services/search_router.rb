class SearchRouter
  # Supported search providers
  PROVIDERS = {
    pgvector_cosine: 'PGVector Cosine',
    pgvector_l2: 'PGVector L2',
    hnsw: 'HNSW',
    haystack: 'Haystack',
    hybrid: 'Hybrid',
    hybrid_advanced: 'Advanced Hybrid',
    distributed: 'Distributed HNSW',
    domain_aware: 'Domain-Aware',
    confidence_aware: 'Confidence-Aware'
  }.freeze
  
  # Supported embedding models and dimensions
  MODELS = {
    'mini' => 384,
    'small' => 768,
    'base' => 1024,
    'large' => 1536,
    'xl' => 2048
  }.freeze
  
  # Default domain for embeddings
  DEFAULT_DOMAIN = 'general'
  
  # Route a search query to the appropriate search provider
  def self.route_query(query_text, organization_id, options = {})
    # Extract dimension and model options
    model_name = options[:model_name] || 'base'
    dimension = options[:dimension] || MODELS[model_name] || 1024
    
    # Domain-specific options
    domain = options[:domain]
    auto_detect_domain = options.fetch(:auto_detect_domain, true)
    
    # If domain is not provided but auto-detection is enabled, try to detect domain
    if domain.blank? && auto_detect_domain && organization_id.present?
      begin
        detected_domain, confidence, fallback_domains = detect_query_domain(query_text, organization_id, options)
        
        # Store fallback domains for possible use in search methods
        options[:fallback_domains] = fallback_domains
        
        # Use organization's threshold setting to determine if confidence is sufficient
        org = Organization.find(organization_id)
        threshold = org.domain_confidence_primary_threshold || 0.7
        
        # Only use detected domain if confidence is sufficient
        domain = detected_domain if confidence >= threshold
        
        # Log the domain detection
        Rails.logger.info("Domain detection: primary '#{detected_domain}' (#{confidence}), fallbacks: #{fallback_domains.join(', ')}")
      rescue => e
        Rails.logger.warn("Domain detection failed: #{e.message}. Using default domain.")
      end
    end
    
    # Add domain to options for later use in search methods
    options[:domain] = domain || DEFAULT_DOMAIN
    
    # Analyze query to determine complexity for optimal routing
    query_metadata = analyze_query(query_text)
    query_complexity = query_metadata[:complexity]
    
    # Get feature flag settings or use defaults
    # Pass query complexity to help determine the provider
    provider = determine_provider(
      organization_id, 
      options.merge(
        dimension: dimension, 
        model_name: model_name,
        query: query_text,
        query_complexity: query_complexity,
        domain: options[:domain]
      )
    )
    
    # Options for the search
    search_options = {
      limit: options[:limit] || 10,
      min_similarity: options[:min_similarity] || 0.5,
      advanced: organization_advanced_search?(organization_id),
      model_name: model_name,
      dimension: dimension,
      query_metadata: query_metadata,
      vector_weight: options[:vector_weight],
      keyword_weight: options[:keyword_weight]
    }
    
    # Track metrics
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    
    # Execute search with the chosen provider
    result = case provider
             when :pgvector_cosine
               search_pgvector_cosine(query_text, organization_id, search_options)
             when :pgvector_l2
               search_pgvector_l2(query_text, organization_id, search_options)
             when :hnsw
               search_hnsw(query_text, organization_id, search_options)
             when :haystack
               search_haystack(query_text, organization_id, search_options)
             when :hybrid
               search_hybrid_new(query_text, organization_id, search_options)
             when :hybrid_advanced
               search_hybrid_advanced(query_text, organization_id, search_options)
             when :distributed
               search_distributed(query_text, organization_id, search_options)
             else
               search_hybrid_new(query_text, organization_id, search_options)
             end
    
    # Calculate search duration
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    duration_ms = (end_time - start_time) * 1000
    
    # Record metrics
    record_search_metrics(provider, query_text, duration_ms, result.size, search_options)
    
    # Return results with metadata
    {
      results: result,
      metadata: {
        provider: provider.to_s,
        dimension: dimension,
        model: model_name,
        duration_ms: duration_ms.round(2),
        result_count: result.size,
        query: query_text
      }
    }
  end
  
  private
  
  # Determine which search provider to use based on feature flags and parameters
  def self.determine_provider(organization_id, options = {})
    # Override from explicit parameter if present
    return options[:search_provider].to_sym if options[:search_provider].present?
    
    # Get organization
    organization = Organization.find(organization_id)
    
    # Check if organization has preferred provider
    return organization.default_search_provider.to_sym if organization.respond_to?(:default_search_provider) && 
                                                          organization.default_search_provider.present?
    
    # Check if distributed search is enabled
    distributed_enabled = distributed_search_enabled?
    
    # Check if HNSW is enabled
    # For now, simulate with a basic check on whether the service is ready
    hnsw_enabled = Wasm::WebassemblySearchService.instance.status == 'ready'
    
    # Get query complexity from options or analyze it
    complexity = options[:query_complexity] || analyze_query_complexity(options[:query]).to_s
    
    # Check dimension - higher dimensions may prefer different providers
    dimension = options[:dimension] || MODELS[options[:model_name] || 'base'] || 1024
    high_dimension = dimension >= 1536
    
    # Check vector count - large collections benefit more from distributed search
    organization_size = estimate_organization_size(organization_id)
    large_collection = organization_size >= 500_000
    
    # Make routing decision
    if distributed_enabled && (large_collection || high_dimension)
      # Large collections and high dimensions benefit from distributed search
      return :distributed
    elsif complexity == 'complex'
      # Complex queries go to advanced hybrid search for better results
      return :hybrid_advanced
    elsif complexity == 'medium'
      # Medium complexity queries benefit from standard hybrid search
      return :hybrid
    elsif high_dimension
      # High-dimensional vectors might be better with advanced hybrid
      return :hybrid_advanced  
    elsif hnsw_enabled && complexity == 'simple'
      # Simple queries with HNSW enabled go to HNSW
      return :hnsw
    else
      # Fall back to hybrid approach
      return :hybrid
    end
  end
  
  # Detect the query domain with confidence scoring and return a fallback chain
  def self.detect_query_domain(query_text, organization_id, options = {})
    # Skip domain detection if explicitly disabled
    return [DEFAULT_DOMAIN, 1.0, [DEFAULT_DOMAIN]] unless options.fetch(:auto_detect_domain, true)
    
    begin
      # Use the DomainConfidenceManager to get domains in fallback order
      domain_manager = DomainConfidenceManager.new
      domains = domain_manager.determine_domains(query_text, organization_id, options)
      
      # The first domain in the chain is the primary one with highest confidence
      primary_domain = domains.first || DEFAULT_DOMAIN
      
      # Get confidence score for the primary domain
      confidence_scorer = ConfidenceScorer.new
      confidence_result = confidence_scorer.calculate_score(
        query_text, primary_domain, organization_id, 
        skip_tracking: options[:skip_confidence_tracking]
      )
      
      Rails.logger.info("Detected domain '#{primary_domain}' for query with confidence #{confidence_result[:score]}")
      
      # Return domain, confidence score, and fallback domains
      return [primary_domain, confidence_result[:score], domains]
    rescue => e
      Rails.logger.error("Error in domain detection: #{e.message}")
      return [DEFAULT_DOMAIN, 1.0, [DEFAULT_DOMAIN]]  # Default domain with high confidence as fallback
    end
  end
  
  # Check if distributed search is enabled
  def self.distributed_search_enabled?
    # In production, this would be a feature flag or configuration setting
    # For now, check if the distributed service is ready
    begin
      Distributed::Search::DistributedSearchService.instance.status == 'ready'
    rescue
      false
    end
  end
  
  # Estimate the organization's vector collection size
  def self.estimate_organization_size(organization_id)
    # In production, this would count the actual vectors or documents
    # For now, use a simple document count
    Organization.find(organization_id).documents.count
  end
  
  # Check if the organization has advanced search enabled
  def self.organization_advanced_search?(organization_id)
    organization = Organization.find(organization_id)
    organization.respond_to?(:advanced_search) && organization.advanced_search
  end
  
  # Analyze a query string to determine optimal search strategy
  def self.analyze_query(query_text)
    return { complexity: 'simple', weights: { vector: 0.9, keyword: 0.1 } } if query_text.blank?
    
    # Use the HaystackClient to parse the query - more sophisticated than our simple heuristics
    begin
      client = HaystackClient.new
      parsed = client.parse_query(query_text)
      
      return {
        complexity: parsed['complexity'],
        weights: parsed['weights'],
        exact_phrases: parsed['exact_phrases'],
        required_terms: parsed['required_terms'],
        excluded_terms: parsed['excluded_terms'],
        boosted_terms: parsed['boosted_terms'],
        keywords: parsed['keywords']
      }
    rescue => e
      Rails.logger.error("Query parsing failed, falling back to simple analysis: #{e.message}")
      # Fall back to simple analysis
      return {
        complexity: analyze_query_complexity(query_text).to_s,
        weights: { vector: 0.7, keyword: 0.3 }
      }
    end
  end
  
  # Analyze query complexity (simplified version as fallback)
  def self.analyze_query_complexity(query)
    return :simple if query.blank?
    
    # Simple heuristics
    if query.split(/\s+/).size > 10 || query.include?(' AND ') || query.include?(' OR ') || query.include?(' NOT ') ||
       query.include?('"') || query.include?('+') || query.include?('-')
      :complex
    elsif query.split(/\s+/).size > 5
      :medium
    else
      :simple
    end
  end
  
  # Search using PGVector with cosine similarity
  def self.search_pgvector_cosine(query_text, organization_id, options)
    # Generate embedding for query with specified model/dimension
    client = HaystackClient.new
    query_embedding = client.generate_embeddings(
      query_text,
      model_name: options[:model_name],
      dimension: options[:dimension],
      organization_id: organization_id,
      domain: options[:domain],
      use_cache: true
    )
    
    # Perform direct vector search using cosine similarity
    documents = Organization.find(organization_id).documents.search_ready.similar_to(
      query_embedding,
      dimension: options[:dimension],
      model_name: options[:model_name],
      min_similarity: options[:min_similarity],
      limit: options[:limit]
    )
    
    # Format results
    format_document_results(documents, query_text, options)
  end
  
  # Search using PGVector with L2 distance
  def self.search_pgvector_l2(query_text, organization_id, options)
    # Generate embedding for query
    client = HaystackClient.new
    query_embedding = client.generate_embeddings(
      query_text,
      model_name: options[:model_name],
      dimension: options[:dimension],
      organization_id: organization_id,
      domain: options[:domain],
      use_cache: true
    )
    
    # Perform direct vector search using L2 distance
    documents = Organization.find(organization_id).documents.search_ready.nearest_neighbors(
      query_embedding,
      dimension: options[:dimension],
      model_name: options[:model_name],
      limit: options[:limit]
    )
    
    # Format results
    format_document_results(documents, query_text, options)
  end
  
  # Search using HNSW
  def self.search_hnsw(query_text, organization_id, options)
    # Generate embedding for query
    client = HaystackClient.new
    query_embedding = client.generate_embeddings(
      query_text,
      model_name: options[:model_name],
      dimension: options[:dimension],
      organization_id: organization_id,
      domain: options[:domain],
      use_cache: true
    )
    
    # Perform search using HNSW
    results = Wasm::WebassemblySearchService.instance.search(
      query_embedding,
      organization_id,
      limit: options[:limit],
      dimension: options[:dimension]
    )
    
    # Fetch document details
    document_ids = results.map { |r| r[:id] }
    documents = Organization.find(organization_id).documents.where(id: document_ids)
    
    # Create a mapping for quick lookup
    document_map = documents.index_by(&:id)
    
    # Format results
    results.map do |result|
      document = document_map[result[:id]]
      next nil unless document
      
      snippet = document.content.present? ? document.content.truncate(300) : "Document content unavailable"
      
      {
        'document_id' => document.id,
        'score' => result[:score],
        'title' => document.title,
        'snippet' => snippet,
        'relevance' => determine_relevance(result[:score]),
        'query' => query_text,
        'dimension' => options[:dimension],
        'model' => options[:model_name]
      }
    end.compact
  end
  
  # Search using Haystack
  def self.search_haystack(query_text, organization_id, options)
    # Call the Python microservice via HaystackClient
    client = HaystackClient.new
    
    # Use organization ID to scope the search
    response = client.search(
      query: query_text,
      organization_id: organization_id,
      advanced: options[:advanced],
      limit: options[:limit],
      model_name: options[:model_name],
      dimension: options[:dimension]
    )
    
    # Enrich response with model and dimension info
    if response.is_a?(Array)
      response.each do |result|
        result['dimension'] = options[:dimension]
        result['model'] = options[:model_name]
      end
    end
    
    response
  end
  
  # Hybrid search that tries multiple methods
  def self.search_hybrid(query_text, organization_id, options)
    # Try distributed search first if it's ready
    if distributed_search_enabled?
      begin
        results = search_distributed(query_text, organization_id, options)
        if results.present?
          return results
        end
      rescue => e
        Rails.logger.error("Distributed search failed, falling back: #{e.message}")
      end
    end
    
    # Try HNSW next if it's ready
    if Wasm::WebassemblySearchService.instance.status == 'ready'
      begin
        results = search_hnsw(query_text, organization_id, options)
        if results.present?
          return results
        end
      rescue => e
        Rails.logger.error("HNSW search failed, falling back: #{e.message}")
      end
    end
    
    # Try pgvector
    begin
      results = search_pgvector_cosine(query_text, organization_id, options)
      if results.present?
        return results
      end
    rescue => e
      Rails.logger.error("PGVector search failed, falling back to Haystack: #{e.message}")
    end
    
    # Fall back to Haystack
    search_haystack(query_text, organization_id, options)
  end
  
  # New hybrid search implementation using the HaystackClient's dedicated hybrid search endpoint
  def self.search_hybrid_new(query_text, organization_id, options)
    # Use the HaystackClient's dedicated hybrid search endpoint
    client = HaystackClient.new
    
    # Get query metadata for weights if not explicitly provided
    query_metadata = options[:query_metadata] || analyze_query(query_text)
    vector_weight = options[:vector_weight] || query_metadata[:weights][:vector]
    keyword_weight = options[:keyword_weight] || query_metadata[:weights][:keyword]
    
    # Call the hybrid search endpoint
    response = client.hybrid_search(
      query: query_text,
      organization_id: organization_id,
      vector_weight: vector_weight,
      keyword_weight: keyword_weight,
      early_termination: true,  # Enable performance optimization by default
      limit: options[:limit]
    )
    
    # Process results
    if response['results'].is_a?(Array)
      response['results'].each do |result|
        # Enrich with additional metadata
        result['dimension'] = options[:dimension]
        result['model'] = options[:model_name]
      end
      
      return response['results']
    else
      # Handle unexpected response format
      Rails.logger.error("Unexpected hybrid search response format: #{response.inspect}")
      return []
    end
  rescue => e
    Rails.logger.error("New hybrid search failed, falling back to legacy hybrid: #{e.message}")
    search_hybrid(query_text, organization_id, options)
  end
  
  # Advanced hybrid search with customized weights and no early termination
  def self.search_hybrid_advanced(query_text, organization_id, options)
    # Similar to search_hybrid_new but with different defaults
    client = HaystackClient.new
    
    # Get query metadata for weights if not explicitly provided
    query_metadata = options[:query_metadata] || analyze_query(query_text)
    
    # For advanced hybrid search, adjust weights to be more balanced
    # but still use query-based weights as a starting point
    vector_weight = options[:vector_weight] || query_metadata[:weights][:vector]
    keyword_weight = options[:keyword_weight] || query_metadata[:weights][:keyword]
    
    # Ensure weights are more balanced for complex queries
    if query_metadata[:complexity] == 'complex' && !options[:vector_weight] && !options[:keyword_weight]
      # Adjust to give more weight to keyword search for complex queries
      vector_weight = [vector_weight, 0.6].min
      keyword_weight = 1.0 - vector_weight
    end
    
    # Call the hybrid search endpoint with advanced settings
    response = client.hybrid_search(
      query: query_text,
      organization_id: organization_id,
      vector_weight: vector_weight,
      keyword_weight: keyword_weight,
      early_termination: false,  # Disable early termination for more thorough results
      limit: options[:limit]
    )
    
    # Process results
    if response['results'].is_a?(Array)
      response['results'].each do |result|
        # Enrich with additional metadata
        result['dimension'] = options[:dimension]
        result['model'] = options[:model_name]
      end
      
      return response['results']
    else
      # Handle unexpected response format
      Rails.logger.error("Unexpected hybrid search response format: #{response.inspect}")
      return []
    end
  rescue => e
    Rails.logger.error("Advanced hybrid search failed, falling back to legacy hybrid: #{e.message}")
    search_hybrid(query_text, organization_id, options)
  end
  
  # Legacy hybrid search that tries multiple methods (kept for backward compatibility)
  # This is the original implementation that's renamed from search_hybrid
  def self.search_hybrid_legacy(query_text, organization_id, options)
    # Try distributed search first if it's ready
    if distributed_search_enabled?
      begin
        results = search_distributed(query_text, organization_id, options)
        if results.present?
          return results
        end
      rescue => e
        Rails.logger.error("Distributed search failed, falling back: #{e.message}")
      end
    end
    
    # Try HNSW next if it's ready
    if Wasm::WebassemblySearchService.instance.status == 'ready'
      begin
        results = search_hnsw(query_text, organization_id, options)
        if results.present?
          return results
        end
      rescue => e
        Rails.logger.error("HNSW search failed, falling back: #{e.message}")
      end
    end
    
    # Try pgvector
    begin
      results = search_pgvector_cosine(query_text, organization_id, options)
      if results.present?
        return results
      end
    rescue => e
      Rails.logger.error("PGVector search failed, falling back to Haystack: #{e.message}")
    end
    
    # Fall back to Haystack
    search_haystack(query_text, organization_id, options)
  end
  
  # Search using distributed HNSW
  def self.search_distributed(query_text, organization_id, options)
    # Generate embedding for query
    client = HaystackClient.new
    query_embedding = client.generate_embeddings(
      query_text,
      model_name: options[:model_name],
      dimension: options[:dimension],
      organization_id: organization_id,
      domain: options[:domain],
      use_cache: true
    )
    
    # Perform search using distributed search service
    results = Distributed::Search::DistributedSearchService.instance.search(
      query_embedding,
      organization_id,
      options.merge(limit: options[:limit])
    )
    
    # Fetch document details if needed
    if results.any? && !results.first.key?('title')
      document_ids = results.map { |r| r[:id] }
      documents = Organization.find(organization_id).documents.where(id: document_ids)
      
      # Create a mapping for quick lookup
      document_map = documents.index_by(&:id)
      
      # Format results
      results = results.map do |result|
        document = document_map[result[:id]]
        next nil unless document
        
        snippet = document.content.present? ? document.content.truncate(300) : "Document content unavailable"
        
        {
          'document_id' => document.id,
          'score' => result[:score],
          'title' => document.title,
          'snippet' => snippet,
          'relevance' => determine_relevance(result[:score]),
          'query' => query_text,
          'dimension' => options[:dimension],
          'model' => options[:model_name]
        }
      end.compact
    end
    
    results
  end
  
  # Format document results to match the expected format
  def self.format_document_results(documents, query, options = {})
    model_name = options[:model_name] || 'base'
    dimension = options[:dimension] || MODELS[model_name] || 1024
    
    documents.map do |doc|
      # Extract snippet text - for now, just use the first 300 chars
      snippet = doc.content.present? ? doc.content.truncate(300) : "Document content unavailable"
      
      # Convert similarity to a score if available
      score = doc.respond_to?(:similarity) ? doc.similarity : 0.9 # Fallback
      
      {
        'document_id' => doc.id,
        'score' => score,
        'title' => doc.title,
        'snippet' => snippet,
        'relevance' => determine_relevance(score),
        'query' => query,
        'dimension' => dimension,
        'model' => model_name
      }
    end
  end
  
  # Determine relevance category based on score
  def self.determine_relevance(score)
    if score >= 0.85
      'high'
    elsif score >= 0.7
      'medium'
    else
      'low'
    end
  end
  
  # Record search metrics for performance monitoring
  def self.record_search_metrics(provider, query, duration_ms, result_count, options = {})
    # In a real implementation, we would record:
    # - Provider used
    # - Query text
    # - Dimension/model used
    # - Duration
    # - Result count
    # - Timestamp
    
    model_name = options[:model_name] || 'base'
    dimension = options[:dimension] || MODELS[model_name] || 1024
    
    Rails.logger.info("Search performed with provider: #{provider}, " +
                     "query: #{query}, dimension: #{dimension}, model: #{model_name}, " +
                     "duration: #{duration_ms.round(2)}ms, " +
                     "results: #{result_count}")
    
    # In production, this would be stored in the database
    # SearchMetric.create!(
    #   provider: provider.to_s,
    #   query: query,
    #   duration_ms: duration_ms,
    #   result_count: result_count,
    #   created_at: Time.current
    # )
  end
end
