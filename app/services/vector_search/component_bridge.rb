# frozen_string_literal: true

module VectorSearch
  # ComponentBridge provides a high-level interface between frontend components
  # and the distributed vector search backend. It manages caching, streaming,
  # and domain-awareness for search operations.
  #
  # The bridge is responsible for:
  # 1. Managing component lifecycle and dependencies
  # 2. Providing a unified interface for search operations
  # 3. Handling domain-specific embeddings and confidence scoring
  # 4. Managing caching and performance optimizations
  # 5. Supporting streaming search results with backpressure handling
  #
  class ComponentBridge
    include ActiveSupport::Callbacks
    
    define_callbacks :search, :stream_search
    
    attr_reader :domain_model, :organization, :user, :components, :options
    
    # Initialize a new component bridge
    # @param domain_model [DomainEmbeddingModel] The domain embedding model to use
    # @param organization [Organization] The organization context
    # @param user [User] The user context
    # @param options [Hash] Additional options
    def initialize(domain_model: nil, organization: nil, user: nil, options: {})
      @domain_model = domain_model
      @organization = organization
      @user = user
      @options = default_options.merge(options)
      @components = {}
      @search_service = initialize_search_service
    end
    
    # Get or create a component of the specified type
    # @param type [Symbol] The component type
    # @param options [Hash] Component-specific options
    # @return [BaseComponent] The component instance
    def component(type, options = {})
      key = component_key(type, options)
      
      @components[key] ||= initialize_component(type, options)
    end
    
    # Search for documents matching the query
    # @param query [String] The search query
    # @param options [Hash] Search options
    # @return [Array<Hash>] Search results
    def search(query, options = {})
      return [] if query.blank?
      
      options = search_options(options)
      results = nil
      
      # Execute callbacks before search
      run_callbacks :search do
        # Check cache first if enabled
        cache_key = cache_key_for_query(query, options)
        results = fetch_from_cache(cache_key) if options[:use_cache]
        
        unless results
          # Perform search if not in cache
          results = execute_search(query, options)
          
          # Store in cache if cacheable
          store_in_cache(cache_key, results) if options[:use_cache] && results.present?
        end
      end
      
      # Record search query for analytics
      record_search_query(query, results, options) if options[:record_analytics]
      
      results
    end
    
    # Stream search results to a callback
    # @param query [String] The search query
    # @param callback [Proc] Callback to receive results
    # @param options [Hash] Search options
    def stream_search(query, callback, options = {})
      return if query.blank? || !callback.respond_to?(:call)
      
      options = streaming_options(options)
      
      # Execute callbacks before streaming search
      run_callbacks :stream_search do
        # Get streaming search service
        service = streaming_search_service
        
        # Stream results
        service.stream_results(query, callback, options)
      end
      
      # Record streaming search query for analytics
      record_streaming_search(query, options) if options[:record_analytics]
      
      true
    end
    
    # Clean up idle components
    # @param max_idle_time [ActiveSupport::Duration] Maximum idle time
    # @param current_time [Time] Current time (for testing)
    def cleanup_idle_components(max_idle_time = 30.minutes, current_time = Time.current)
      @components.delete_if do |key, component|
        if component.respond_to?(:idle?) && component.idle?(max_idle_time, current_time)
          component.cleanup if component.respond_to?(:cleanup)
          true
        else
          false
        end
      end
    end
    
    private
    
    # Default options for the bridge
    def default_options
      {
        prefetch_enabled: false,
        cache_ttl: 30.minutes,
        confidence_threshold: 0.7,
        result_limit: 20,
        use_distributed: true,
        use_cache: true,
        record_analytics: true
      }
    end
    
    # Initialize the search service based on configuration
    def initialize_search_service
      if options[:use_distributed] && defined?(Distributed::Search::DistributedSearchService)
        Distributed::Search::DistributedSearchService.instance
      else
        # Fallback to standard search service
        defined?(SearchService) ? SearchService.new : nil
      end
    end
    
    # Initialize the streaming search service
    def streaming_search_service
      @streaming_search_service ||= begin
        if defined?(Distributed::Search::StreamingSearchAdapter)
          Distributed::Search::StreamingSearchAdapter.new
        else
          # Create a basic streaming adapter if not available
          create_basic_streaming_adapter
        end
      end
    end
    
    # Create a basic streaming adapter if the distributed one is not available
    def create_basic_streaming_adapter
      # Simple adapter that calls the callback with each result
      Class.new do
        def initialize(search_service)
          @search_service = search_service
        end
        
        def stream_results(query, callback, options = {})
          results = @search_service.search(query, options) || []
          
          # Stream each result with a small delay to simulate streaming
          results.each do |result|
            callback.call(result)
            sleep(0.05) # Small delay to simulate streaming
          end
          
          results.length
        end
      end.new(@search_service)
    end
    
    # Generate a unique key for a component based on type and options
    def component_key(type, options)
      options_hash = options.hash.to_s(36)
      "#{type}_#{options_hash}"
    end
    
    # Initialize a component of the specified type
    def initialize_component(type, options = {})
      component_class = component_class_for_type(type)
      
      if component_class
        component_class.new(self, options)
      else
        raise ArgumentError, "Unknown component type: #{type}"
      end
    end
    
    # Get the component class for the specified type
    def component_class_for_type(type)
      manager = SearchComponentManager.instance
      registry = manager.instance_variable_get(:@component_registry)
      
      registry[type.to_sym] if registry
    end
    
    # Default search options merged with provided options
    def search_options(options)
      {
        confidence_threshold: self.options[:confidence_threshold],
        limit: self.options[:result_limit],
        use_cache: self.options[:use_cache],
        record_analytics: self.options[:record_analytics],
        domain_model: domain_model,
        organization: organization,
        user: user
      }.merge(options)
    end
    
    # Default streaming options merged with provided options
    def streaming_options(options)
      search_options(options).merge(
        streaming: true
      )
    end
    
    # Generate a cache key for a search query
    def cache_key_for_query(query, options)
      domain_id = domain_model&.id || 'default'
      org_id = organization&.id || 'global'
      
      # Create a deterministic hash for the query with relevant options
      query_hash = [
        query.downcase,
        options[:confidence_threshold],
        options[:limit],
        domain_id,
        org_id
      ].join(':').hash
      
      "vector_search:#{domain_id}:#{query_hash}"
    end
    
    # Fetch results from cache
    def fetch_from_cache(cache_key)
      return nil unless defined?(EmbeddingCache::CacheManager)
      
      EmbeddingCache::CacheManager.instance.get(cache_key)
    end
    
    # Store results in cache
    def store_in_cache(cache_key, results)
      return unless defined?(EmbeddingCache::CacheManager)
      
      EmbeddingCache::CacheManager.instance.set(
        cache_key, 
        results, 
        expires_in: options[:cache_ttl]
      )
    end
    
    # Execute search against the service
    def execute_search(query, options)
      return [] unless @search_service
      
      search_params = {
        query: query,
        limit: options[:limit],
        domain_model: domain_model,
        confidence_threshold: options[:confidence_threshold]
      }
      
      if organization
        search_params[:organization_id] = organization.id
      end
      
      @search_service.search(search_params)
    end
    
    # Record search query for analytics
    def record_search_query(query, results, options)
      return unless defined?(SearchQuery) && user.present?
      
      begin
        SearchQuery.create(
          query_text: query,
          user: user,
          organization: organization,
          domain_embedding_model: domain_model,
          result_count: results&.length || 0,
          response_time_ms: nil, # Not tracked here
          successful: results.present?
        )
      rescue => e
        Rails.logger.error "Error recording search query: #{e.message}"
      end
    end
    
    # Record streaming search for analytics
    def record_streaming_search(query, options)
      return unless defined?(SearchQuery) && user.present?
      
      begin
        SearchQuery.create(
          query_text: query,
          user: user,
          organization: organization,
          domain_embedding_model: domain_model,
          result_count: nil, # Not known in advance for streaming
          response_time_ms: nil, # Not tracked here
          streaming: true,
          successful: true # Assumed successful at start
        )
      rescue => e
        Rails.logger.error "Error recording streaming search: #{e.message}"
      end
    end
  end
end
