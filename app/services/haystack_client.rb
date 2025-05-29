require 'net/http'
require 'uri'
require 'json'

class HaystackClient
  # Response class for consistent API responses
  class Response
    attr_reader :success, :data, :error
    
    def initialize(success, data, error)
      @success = success
      @data = data
      @error = error
    end
    
    def success?
      @success
    end
  end
  
  # Default configuration
  DEFAULT_CONFIG = {
    base_url: ENV.fetch('HAYSTACK_SERVICE_URL', 'http://localhost:8000'),
    timeout: 30,
    max_retries: 3,
    backoff_factor: 0.5
  }.freeze

  # Initialize with optional configuration override
  def initialize(config = {})
    @config = self.class.config.merge(config)
  end
  
  # Search documents with query
  def search(options = {})
    query = options[:query]
    organization_id = options[:organization_id]
    advanced = options[:advanced] || false
    limit = options[:limit] || 10
    
    payload = {
      query: query,
      filters: { organization_id: organization_id },
      top_k: limit,
      advanced: advanced
    }
    
    response = post_request('/search', payload)
    parse_response(response)
  end
  
  # Hybrid search combining vector and keyword approaches
  # @param query [String] The search query
  # @param organization_id [Integer] Organization ID for filtering
  # @param vector_weight [Float] Weight for vector search (0.0-1.0)
  # @param keyword_weight [Float] Weight for keyword search (0.0-1.0)
  # @param early_termination [Boolean] Whether to use early termination optimization
  # @param limit [Integer] Number of results to return
  # @return [Hash] Search results and metadata
  def hybrid_search(options = {})
    query = options[:query]
    organization_id = options[:organization_id]
    vector_weight = options[:vector_weight]
    keyword_weight = options[:keyword_weight]
    early_termination = options.key?(:early_termination) ? options[:early_termination] : true
    limit = options[:limit] || 10
    
    payload = {
      query: query,
      filters: { organization_id: organization_id },
      top_k: limit,
      early_termination: early_termination
    }
    
    # Add optional weights if provided
    payload[:vector_weight] = vector_weight if vector_weight
    payload[:keyword_weight] = keyword_weight if keyword_weight
    
    response = post_request('/hybrid-search', payload)
    parse_response(response)
  end
  
  # Parse a query to analyze its components for different search methods
  # @param query [String] The query to parse
  # @return [Hash] Parsed query components
  def parse_query(query)
    payload = { query: query }
    response = post_request('/parse-query', payload)
    parse_response(response)
  end
  
  # Generate embeddings for a given text
  # @param text [String] The text to generate embeddings for
  # @param model_name [String] The name of the embedding model to use (mini, small, base, large, xl)
  # @param dimension [Integer] The dimension of the embeddings to generate (384, 768, 1024, 1536, 2048)
  # @param organization_id [Integer] Optional organization ID for cache scoping
  # @param domain [String] Optional domain for domain-specific embeddings
  # @param use_cache [Boolean] Whether to use the embedding cache (default: true)
  # @return [Array] The embedding vector
  def generate_embeddings(text, model_name: 'base', dimension: nil, organization_id: nil, domain: nil, use_cache: true)
    # Prepare parameters
    model = model_name || 'base'
    dim = dimension || SearchRouter::MODELS[model] || 1024
    
    # Check cache if enabled and organization_id is provided
    if use_cache && organization_id.present?
      cache_options = { 
        model_name: model, 
        dimension: dim,
        domain: domain || 'general'
      }
      
      # Get cache manager
      cache_manager = EmbeddingCache::CacheManager.instance
      
      # Try to get from cache or compute if not found
      return cache_manager.fetch(organization_id, text, cache_options) do
        # Cache miss - generate embedding via API
        # Prepare payload
        payload = { text: text }
        payload[:model_name] = model
        payload[:dimension] = dim if dim
        
        response = post_request('/embeddings/generate', payload)
        result = parse_response(response)
        
        # Return the embedding vector from the response
        result['embedding']
      end
    end
    
    # If cache is disabled or organization_id is not provided, generate directly
    # Prepare payload
    payload = { text: text }
    payload[:model_name] = model
    payload[:dimension] = dim if dim
    
    response = post_request('/embeddings/generate', payload)
    result = parse_response(response)
    
    # Return the embedding vector from the response
    result['embedding']
  end
  
  # Answer a question based on the documents
  def answer_question(question, options = {})
    organization_id = options[:organization_id]
    
    payload = {
      question: question,
      filters: { organization_id: organization_id }
    }
    
    response = post_request('/question-answering', payload)
    parse_response(response)
  end
  
  # Document indexing endpoint
  def index_document(document_content, metadata = {})
    payload = {
      content: document_content,
      metadata: metadata
    }

    response = post_request('/documents/index', payload)
    parse_response(response)
  end
  
  # Dimension reduction endpoint
  # @param vectors [Array] Array of vector embeddings to reduce
  # @param algorithm [String] The algorithm to use (tsne, umap)
  # @param params [Hash] Algorithm-specific parameters
  # @return [Array] Array of reduced vectors
  def dimension_reduction(options = {})
    vectors = options[:vectors]
    algorithm = options[:algorithm] || 'tsne'
    params = options[:params] || {}
    
    payload = {
      vectors: vectors,
      algorithm: algorithm,
      params: params
    }
    
    response = post_request('/visualization/dimension-reduction', payload)
    result = parse_response(response)
    
    # Create a response object similar to our other API methods
    Response.new(true, result['reduced_vectors'], nil)
  rescue => e
    Rails.logger.error("Dimension reduction failed: #{e.message}")
    Response.new(false, nil, e.message)
  end
  
  # Document clustering endpoint
  # @param vectors [Array] Array of vector embeddings to cluster
  # @param document_ids [Array] Array of document IDs corresponding to the vectors
  # @param algorithm [String] The algorithm to use (kmeans, hierarchical, dbscan)
  # @param params [Hash] Algorithm-specific parameters
  # @return [Hash] Cluster assignments and metadata
  def cluster_documents(options = {})
    vectors = options[:vectors]
    document_ids = options[:document_ids]
    algorithm = options[:algorithm] || 'kmeans'
    params = options[:params] || {}
    
    payload = {
      vectors: vectors,
      document_ids: document_ids,
      algorithm: algorithm,
      params: params
    }
    
    response = post_request('/visualization/clustering', payload)
    result = parse_response(response)
    
    # Create a response object similar to our other API methods
    Response.new(true, result, nil)
  rescue => e
    Rails.logger.error("Document clustering failed: #{e.message}")
    Response.new(false, nil, e.message)
  end
  
  # Domain-specific methods
  
  # Generate embeddings using a domain-specific model
  # @param text [String] The text to generate embeddings for
  # @param model_name [String] The base model name (mini, small, base, large, xl)
  # @param domain [String] The domain name
  # @param organization_id [Integer] The organization ID for tenant isolation
  # @param use_cache [Boolean] Whether to use the embedding cache (default: true)
  # @return [Hash] The embedding vector and metadata
  def generate_domain_embedding(options = {})
    text = options[:text]
    model_name = options[:model_name] || 'base'
    domain = options[:domain] || 'general'
    organization_id = options[:organization_id]
    use_cache = options.fetch(:use_cache, true)
    
    # Check cache if enabled and organization_id is provided
    if use_cache && organization_id.present? && text.present?
      dimension = SearchRouter::MODELS[model_name] || 1024
      cache_options = { 
        model_name: model_name, 
        dimension: dimension,
        domain: domain
      }
      
      # Get cache manager
      cache_manager = EmbeddingCache::CacheManager.instance
      
      # Try to get from cache or compute if not found
      cached_embedding = cache_manager.fetch(organization_id, text, cache_options) do
        # Cache miss - generate domain embedding via API
        payload = {
          text: text,
          model_name: model_name,
          domain: domain,
          organization_id: organization_id
        }
        
        response = post_request('/domains/embedding/generate', payload)
        result = parse_response(response)
        
        # Only cache the embedding vector
        result['embedding']
      end
      
      # If we got a cached result, wrap it in a domain embedding response format
      if cached_embedding
        return Response.new(true, {
          'embedding' => cached_embedding,
          'model' => model_name,
          'domain' => domain,
          'dimension' => dimension,
          'cached' => true
        }, nil)
      end
    end
    
    # If cache is disabled, not applicable, or cache miss
    payload = {
      text: text,
      model_name: model_name,
      domain: domain,
      organization_id: organization_id
    }
    
    response = post_request('/domains/embedding/generate', payload)
    result = parse_response(response)
    
    # Create a response object
    Response.new(true, result, nil)
  rescue => e
    Rails.logger.error("Domain embedding generation failed: #{e.message}")
    Response.new(false, nil, e.message)
  end
  
  # Detect the appropriate domain for a query
  # @param query [String] The query text
  # @param organization_id [Integer] The organization ID for tenant isolation
  # @return [Hash] The detected domain and confidence score
  def detect_domain(query, organization_id)
    payload = {
      query: query,
      organization_id: organization_id
    }
    
    response = post_request('/domains/detect', payload)
    result = parse_response(response)
    
    Response.new(true, result, nil)
  rescue => e
    Rails.logger.error("Domain detection failed: #{e.message}")
    Response.new(false, nil, e.message)
  end
  
  # Get the similarity score between a query and a specific domain
  # @param query [String] The query text
  # @param domain [String] The domain to check similarity against
  # @param organization_id [Integer] The organization ID for tenant isolation
  # @return [Hash] The similarity score and related details
  def detect_domain_similarity(query, domain, organization_id)
    payload = {
      query: query,
      domain: domain,
      organization_id: organization_id
    }
    
    response = post_request('/domains/similarity', payload)
    result = parse_response(response)
    
    Response.new(true, result, nil)
  rescue => e
    Rails.logger.error("Domain similarity detection failed: #{e.message}")
    Response.new(false, nil, e.message)
  end
  
  # Get enhanced domain detection with multi-factor scoring
  # @param query [String] The query text
  # @param organization_id [Integer] The organization ID for tenant isolation
  # @param options [Hash] Additional options like include_factors
  # @return [Hash] Comprehensive domain detection results with confidence factors
  def enhanced_domain_detection(query, organization_id, options = {})
    payload = {
      query: query,
      organization_id: organization_id,
      include_factors: options[:include_factors] || true
    }
    
    response = post_request('/domains/enhanced-detect', payload)
    result = parse_response(response)
    
    Response.new(true, result, nil)
  rescue => e
    Rails.logger.error("Enhanced domain detection failed: #{e.message}")
    Response.new(false, nil, e.message)
  end
  
  # List available domains for an organization
  # @param organization_id [Integer] The organization ID
  # @return [Array] List of available domains
  def list_domains(organization_id)
    response = get_request('/domains/available', { organization_id: organization_id })
    result = parse_response(response)
    
    Response.new(true, result, nil)
  rescue => e
    Rails.logger.error("Listing domains failed: #{e.message}")
    Response.new(false, nil, e.message)
  end
  
  # List models for a specific domain
  # @param domain [String] The domain name
  # @param organization_id [Integer] The organization ID
  # @return [Array] List of domain models
  def list_domain_models(domain, organization_id)
    response = get_request('/domains/models', { domain: domain, organization_id: organization_id })
    result = parse_response(response)
    
    Response.new(true, result, nil)
  rescue => e
    Rails.logger.error("Listing domain models failed: #{e.message}")
    Response.new(false, nil, e.message)
  end
  
  # Fine-tune a domain-specific embedding model
  # @param domain [String] The domain name
  # @param base_model [String] The base model to fine-tune
  # @param training_data [Array] List of tuples (text1, text2, similarity_score)
  # @param organization_id [Integer] The organization ID
  # @param name [String] The model name
  # @param description [String] The model description
  # @return [Hash] Fine-tuning result and metrics
  def fine_tune_domain_model(options = {})
    domain = options[:domain]
    base_model = options[:base_model] || 'base'
    training_data = options[:training_data]
    organization_id = options[:organization_id]
    name = options[:name]
    description = options[:description]
    
    payload = {
      domain: domain,
      base_model: base_model,
      training_data: training_data,
      organization_id: organization_id,
      name: name,
      description: description
    }
    
    response = post_request('/domains/models/fine-tune', payload)
    result = parse_response(response)
    
    Response.new(true, result, nil)
  rescue => e
    Rails.logger.error("Domain model fine-tuning failed: #{e.message}")
    Response.new(false, nil, e.message)
  end
  
  # Generate an answer using RAG (Retrieval-Augmented Generation)
  # @param query [String] The question or query
  # @param organization_id [Integer] Organization ID for tenant isolation
  # @param options [Hash] Additional options for retrieval and generation
  # @return [Hash] Generated answer, source context, and metadata
  def generate_answer(query, organization_id, options = {})
    # Get options
    provider = options[:provider]
    max_documents = options[:max_documents] || 5
    similarity_threshold = options[:similarity_threshold] || 0.75
    retrieval_strategy = options[:retrieval_strategy] || "auto"
    temperature = options[:temperature] || 0.7
    max_tokens = options[:max_tokens] || 500
    
    # Add domain detection if enabled
    domain = options[:domain]
    auto_detect_domain = options[:auto_detect_domain]
    
    # Prepare the payload
    payload = {
      query: query,
      org_id: organization_id,
      provider: provider,
      retrieval_options: {
        max_documents: max_documents,
        min_similarity: similarity_threshold,
        strategy: retrieval_strategy,
        deduplicate: options[:deduplicate].nil? ? true : options[:deduplicate],
        domain: domain,
        auto_detect_domain: auto_detect_domain
      },
      generation_options: {
        temperature: temperature,
        max_tokens: max_tokens,
        model: options[:model],
        system_prompt: options[:system_prompt]
      }
    }
    
    # Make the request
    response = post_request('/rag/answer', payload)
    result = parse_response(response)
    
    # Process the response
    Response.new(true, result, nil)
  rescue => e
    Rails.logger.error("RAG answer generation failed: #{e.message}")
    Response.new(false, nil, e.message)
  end
  
  # Generate a streaming answer using RAG with SSE (Server-Sent Events)
  # @param query [String] The question or query
  # @param organization_id [Integer] Organization ID for tenant isolation
  # @param options [Hash] Additional options for retrieval and generation
  # @yield [event] Yields each streamed event with type and data
  # @return [void] This method doesn't return a value but yields events to the block
  def generate_answer_stream(query, organization_id, options = {})
    raise ArgumentError, "Block is required for streaming" unless block_given?
    
    # Get options
    provider = options[:provider]
    max_documents = options[:max_documents] || 5
    similarity_threshold = options[:similarity_threshold] || 0.75
    retrieval_strategy = options[:retrieval_strategy] || "auto"
    temperature = options[:temperature] || 0.7
    max_tokens = options[:max_tokens] || 500
    timeout = options[:timeout] || 300 # 5 minutes default for streaming
    
    # Add domain detection if enabled
    domain = options[:domain]
    auto_detect_domain = options[:auto_detect_domain]
    
    # Prepare the payload
    payload = {
      query: query,
      org_id: organization_id,
      provider: provider,
      retrieval_options: {
        max_documents: max_documents,
        min_similarity: similarity_threshold,
        strategy: retrieval_strategy,
        deduplicate: options[:deduplicate].nil? ? true : options[:deduplicate],
        domain: domain,
        auto_detect_domain: auto_detect_domain
      },
      generation_options: {
        temperature: temperature,
        max_tokens: max_tokens,
        model: options[:model],
        system_prompt: options[:system_prompt]
      }
    }
    
    # Set up the streaming request
    uri = URI.parse("#{@config[:base_url]}/rag/stream")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = timeout
    
    # Create the POST request
    request = Net::HTTP::Post.new(uri.path)
    request.content_type = 'application/json'
    request['Accept'] = 'text/event-stream'
    request.body = payload.to_json
    
    # Make the streaming request
    begin
      http.request(request) do |response|
        # Check for errors
        if response.code.to_i >= 400
          error = JSON.parse(response.body) rescue {"error" => "Unknown error"}
          yield({type: :error, data: {error: error["detail"] || "Error streaming RAG response"}})
          return
        end
        
        # Process the SSE stream
        buffer = ""
        response.read_body do |chunk|
          buffer += chunk
          
          # Process each complete event (separated by double newlines)
          while buffer.include?("\n\n")
            event_data, buffer = buffer.split("\n\n", 2)
            event_lines = event_data.split("\n")
            
            # Default event type is 'message'
            event_type = "message"
            event_data = nil
            
            # Parse the event
            event_lines.each do |line|
              if line.start_with?("event:")
                event_type = line.sub("event:", "").strip
              elsif line.start_with?("data:")
                event_data = line.sub("data:", "").strip
              end
            end
            
            # Skip if no data
            next if event_data.nil?
            
            # Parse JSON data
            begin
              parsed_data = JSON.parse(event_data)
              
              # Map event types to Ruby symbols
              case event_type
              when "metadata"
                yield({type: :metadata, data: parsed_data})
              when "token"
                yield({type: :token, data: parsed_data})
              when "metric"
                yield({type: :metric, data: parsed_data})
              when "error"
                yield({type: :error, data: parsed_data})
              when "complete"
                yield({type: :complete, data: parsed_data})
              when "fallback"
                yield({type: :fallback, data: parsed_data})
              else
                # Generic event handler
                yield({type: event_type.to_sym, data: parsed_data})
              end
            rescue JSON::ParserError => e
              Rails.logger.error("Failed to parse SSE event: #{e.message}")
              yield({type: :error, data: {error: "Failed to parse event data"}})
            end
          end
        end
      end
    rescue Timeout::Error => e
      Rails.logger.error("Streaming request timed out: #{e.message}")
      yield({type: :error, data: {error: "Streaming request timed out after #{timeout} seconds"}})
    rescue => e
      Rails.logger.error("Streaming request failed: #{e.message}")
      yield({type: :error, data: {error: "Streaming request failed: #{e.message}"}})
    end
  end
  
  # Get a list of available LLM providers for RAG
  # @return [Array] List of provider information
  def list_llm_providers
    response = get_request('/rag/providers')
    result = parse_response(response)
    
    Response.new(true, result, nil)
  rescue => e
    Rails.logger.error("Failed to get LLM providers: #{e.message}")
    Response.new(false, nil, e.message)
  end
  
  # Check health/status of the Haystack service
  def health_check
    response = get_request('/health')
    parse_response(response)
  rescue => e
    { status: 'error', message: e.message }
  end
  
  private
  
  # Helper for POST requests
  def post_request(endpoint, payload)
    uri = URI.parse("#{@config[:base_url]}#{endpoint}")
    http = setup_http_client(uri)
    
    request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
    request.body = payload.to_json
    
    with_retries do
      http.request(request)
    end
  end

  # Helper for GET requests
  def get_request(endpoint, params = {})
    uri = URI.parse("#{@config[:base_url]}#{endpoint}")
    uri.query = URI.encode_www_form(params) unless params.empty?
    http = setup_http_client(uri)
    
    with_retries do
      http.get(uri.request_uri)
    end
  end

  # Set up HTTP client with timeout
  def setup_http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = @config[:timeout]
    http.open_timeout = @config[:timeout]
    http
  end

  # Implement exponential backoff for retries
  def with_retries
    retries = 0
    begin
      response = yield
      handle_response(response)
    rescue => e
      retries += 1
      if retries <= @config[:max_retries]
        sleep_time = @config[:backoff_factor] * (2 ** (retries - 1))
        Rails.logger.warn("HaystackClient retry #{retries}/#{@config[:max_retries]} after #{sleep_time}s: #{e.message}")
        sleep(sleep_time)
        retry
      else
        Rails.logger.error("HaystackClient failed after #{@config[:max_retries]} retries: #{e.message}")
        raise e
      end
    end
  end

  # Handle HTTP responses
  def handle_response(response)
    case response
    when Net::HTTPSuccess
      response
    when Net::HTTPRedirection
      raise "Redirect not supported"
    else
      error_message = "HTTP Error: #{response.code} - #{response.message}"
      begin
        error_details = JSON.parse(response.body)
        error_message += " | Details: #{error_details['detail'] || error_details['message']}"
      rescue JSON::ParserError
        # If response body isn't valid JSON, just use the response message
      end
      
      Rails.logger.error(error_message)
      raise error_message
    end
  end

  # Parse JSON response
  def parse_response(response)
    JSON.parse(response.body)
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse JSON response: #{e.message}")
    Rails.logger.error("Response body: #{response.body}")
    raise "Invalid JSON response from Haystack service"
  end

  class << self
    # Initialize with configuration
    def configure(config = {})
      @config = DEFAULT_CONFIG.merge(config)
    end

    # Get current configuration
    def config
      @config ||= DEFAULT_CONFIG.dup
    end

  end
end
