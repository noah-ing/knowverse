class SearchController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :ensure_organization_member
  
  # GET /search
  def index
    # Just render the search form
    @last_queries = [] # Placeholder for tracking previous searches
  end
  
  # GET /search/streaming
  def streaming
    # Render the streaming search interface
    # This interface uses the new domain-aware, lazy-loaded components
    @domains = @organization.domain_embedding_models
                           .where(active: true)
                           .pluck(:domain)
                           .uniq
    
    # Default to 'general' domain if no specific domain requested
    @current_domain = params[:domain] || 'general'
  end
  
  # POST /search/query
  def query
    @query = params[:query]
    
    if @query.blank?
      return redirect_to search_path, alert: 'Search query cannot be empty.'
    end
    
    # Prepare search options
    limit = params[:limit].to_i.positive? ? params[:limit].to_i : 10
    min_similarity = params[:min_similarity].to_f.positive? ? params[:min_similarity].to_f : 0.5
    search_provider = params[:search_method].presence
    model_name = params[:model_name].presence || 'base'
    
    search_options = {
      limit: limit,
      min_similarity: min_similarity,
      search_provider: search_provider,
      model_name: model_name,
      query: @query
    }
    
    begin
      # Use SearchRouter to perform the search
      search_response = SearchRouter.route_query(@query, @organization.id, search_options)
      
      # Extract results and metadata
      search_results = search_response[:results]
      search_metadata = search_response[:metadata]
      
      # Record the search query in the database
      search_query = SearchQuery.create(
        query_text: @query,
        search_provider: search_metadata[:provider],
        parameters: {
          model_name: search_metadata[:model],
          dimension: search_metadata[:dimension],
          min_similarity: min_similarity,
          limit: limit
        },
        latency: search_metadata[:duration_ms],
        result_count: search_results.size,
        organization: @organization,
        user: current_user
      )
      
      # Store search query ID and results in session for later retrieval
      session[:last_search_query_id] = search_query.id
      session[:last_search_results] = search_results
      session[:last_search_query] = @query
      session[:last_search_method] = search_metadata[:provider]
      session[:last_search_duration] = search_metadata[:duration_ms]
      session[:last_search_model] = search_metadata[:model]
      session[:last_search_dimension] = search_metadata[:dimension]
      
      redirect_to results_search_path(id: Time.current.to_i)
    rescue StandardError => e
      Rails.logger.error("Search error: #{e.message}")
      redirect_to search_path, alert: "Error performing search: #{e.message}"
    end
  end
  
  # GET /search/results/:id
  def results
    @query = session[:last_search_query]
    @search_results = session[:last_search_results]
    @search_method = session[:last_search_method] || 'hybrid'
    @model_name = session[:last_search_model] || 'base'
    @dimension = session[:last_search_dimension] || 1024
    @search_query_id = session[:last_search_query_id]
    
    if @search_results.blank?
      redirect_to search_path, alert: 'No search results found. Please try a new search.'
    end
    
    # Fetch document details for the search results
    @documents = {}
    document_ids = @search_results.map { |r| r['document_id'] }.uniq
    
    if document_ids.present?
      # Fetch the documents from the database
      docs = @organization.documents.where(id: document_ids)
      
      # Create a hash for quick lookup
      docs.each do |doc|
        @documents[doc.id] = doc
      end
    end
  end
  
  private
    # Set the organization from the URL parameter
    def set_organization
      if params[:organization_id].present?
        @organization = Organization.find(params[:organization_id])
      else
        # If no organization is specified, use the first organization the user belongs to
        @organization = current_user.organizations.first
        
        if @organization.nil?
          redirect_to organizations_path, alert: 'Please create or join an organization first.'
        end
      end
    end
    
    # Check if current user belongs to the organization
    def ensure_organization_member
      unless @organization.users.include?(current_user)
        redirect_to organizations_path, alert: 'You do not have access to this organization.'
      end
    end
    
    # Format pgvector search results to match the format expected by the view
    def format_pgvector_results(documents, query)
      documents.map do |doc|
        # Extract snippet text - for now, just use the first 300 chars
        # In a real implementation, we'd use a more sophisticated snippet extraction
        snippet = doc.content.present? ? doc.content.truncate(300) : "Document content unavailable"
        
        {
          'document_id' => doc.id,
          'score' => doc.respond_to?(:similarity) ? doc.similarity : 0.9, # Fallback if score not present
          'title' => doc.title,
          'snippet' => snippet,
          'relevance' => 'high', # Default for direct pgvector search
          'query' => query
        }
      end
    end
    
    # Track search metrics for performance monitoring
    def track_search_metrics(search_method)
      # Now implemented with SearchQuery model
      # This tracks:
      # - Search method used
      # - Query time
      # - Result count
      # - And stores user and organization context
      Rails.logger.info("Search performed with method: #{search_method}, query: #{@query}")
    end
end
