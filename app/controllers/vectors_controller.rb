class VectorsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :check_access_permission
  
  # GET /organizations/:organization_id/vectors
  # List all vector projections for this organization
  def index
    # Check if vector_projections table exists
    if table_exists?("vector_projections")
      @vector_projections = VectorProjection
        .where(organization: @organization)
        .includes(:vector_embedding)
        .page(params[:page] || 1)
        .per(params[:per_page] || 1000)
        
      # Filter by algorithm if provided
      if params[:algorithm].present?
        @vector_projections = @vector_projections.where(algorithm: params[:algorithm])
      end
      
      # Filter by embedding model if provided
      if params[:model].present?
        @vector_projections = @vector_projections
          .joins(:vector_embedding)
          .where(vector_embeddings: { model_name: params[:model] })
      end
      
      # Filter by dimension if provided
      if params[:dimension].present?
        @vector_projections = @vector_projections
          .joins(:vector_embedding)
          .where(vector_embeddings: { dimension: params[:dimension] })
      end
      
      # Filter by LOD level if provided
      if params[:lod_level].present?
        @vector_projections = @vector_projections.where(lod_level: params[:lod_level])
      end
    else
      # Table doesn't exist, provide empty collection
      @vector_projections = []
      @table_missing = true
      @missing_table = "vector_projections"
    end
    
    respond_to do |format|
      format.html
      format.json do
        render json: {
          vector_projections: @vector_projections.as_json(include: { 
            vector_embedding: { 
              only: [:id, :dimensions, :model_name],
              include: { document: { only: [:id, :title] } }
            }
          }),
          total_count: @vector_projections.total_count,
          current_page: @vector_projections.current_page,
          total_pages: @vector_projections.total_pages
        }
      end
    end
  end
  
  # GET /organizations/:organization_id/vectors/projections
  # Get projections with visualization-friendly format
  def projections
    # Get a specific projection by ID
    if params[:id].present?
      @projection = VectorProjection.find(params[:id])
      authorize_projection(@projection)
      
      return render json: format_projection_for_visualization(@projection)
    end
    
    # Otherwise, get filtered projections
    @vector_projections = filter_projections
    
    # Format data for visualization
    @visualization_data = {
      points: @vector_projections.map { |vp| format_projection_for_visualization(vp) },
      algorithm: params[:algorithm] || 'tsne',
      lod_level: params[:lod_level] || 0,
      total_count: @vector_projections.count
    }
    
    render json: @visualization_data
  end
  
  # POST /organizations/:organization_id/vectors/reduce
  # Trigger dimension reduction for selected embeddings
  def reduce
    # Validate parameters
    unless params[:algorithm].present? && %w[tsne umap].include?(params[:algorithm])
      return render json: { error: "Invalid algorithm. Must be 'tsne' or 'umap'" }, status: :bad_request
    end
    
    # Get embeddings to process
    embedding_ids = get_embeddings_for_reduction
    
    # Return error if no embeddings found
    if embedding_ids.empty?
      return render json: { error: "No embeddings found matching criteria" }, status: :not_found
    end
    
    # Prepare algorithm parameters
    algorithm_params = {}
    
    # Add parameters based on algorithm
    if params[:algorithm] == 'tsne'
      algorithm_params['perplexity'] = params[:perplexity].to_i if params[:perplexity].present?
      algorithm_params['learning_rate'] = params[:learning_rate].to_f if params[:learning_rate].present?
      algorithm_params['iterations'] = params[:iterations].to_i if params[:iterations].present?
    elsif params[:algorithm] == 'umap'
      algorithm_params['n_neighbors'] = params[:n_neighbors].to_i if params[:n_neighbors].present?
      algorithm_params['min_dist'] = params[:min_dist].to_f if params[:min_dist].present?
    end
    
    # Add common parameters
    algorithm_params['dimensions'] = params[:dimensions].to_i if params[:dimensions].present?
    
    # Start a background job for dimension reduction
    job_id = DocumentProcessing::DimensionReductionWorker.perform_async(
      @organization.id,
      embedding_ids,
      params[:algorithm],
      algorithm_params,
      params[:lod_level].present? ? params[:lod_level].to_i : 0
    )
    
    # Return job ID
    render json: { job_id: job_id, embedding_count: embedding_ids.size, message: "Dimension reduction started" }
  end
  
  # GET /organizations/:organization_id/vectors/clusters
  # List clusters for organization
  def clusters
    @clusters = DocumentCluster
      .where(organization: @organization)
      
    # Filter by algorithm if provided
    if params[:algorithm].present?
      @clusters = @clusters.where(algorithm: params[:algorithm])
    end
    
    # Filter by parent cluster for hierarchical view
    if params[:parent_cluster_id].present?
      @clusters = @clusters.where(parent_cluster_id: params[:parent_cluster_id])
    else
      # Top-level clusters only by default
      @clusters = @clusters.roots
    end
    
    # Get only clusters with minimum document count
    if params[:min_documents].present?
      @clusters = @clusters.with_documents_min(params[:min_documents].to_i)
    end
    
    # Include a sample of documents for each cluster
    document_sample_size = [params[:document_sample_size].to_i, 10].min
    document_sample_size = 3 if document_sample_size <= 0
    
    respond_to do |format|
      format.html
      format.json do
        render json: {
          clusters: @clusters.map do |cluster|
            cluster.as_json(
              except: [:created_at, :updated_at],
              include: {
                documents: { 
                  only: [:id, :title],
                  limit: document_sample_size
                }
              }
            )
          end,
          total_count: @clusters.count
        }
      end
    end
  end
  
  # POST /organizations/:organization_id/vectors/cluster
  # Trigger clustering for selected embeddings
  def cluster
    # Validate parameters
    unless params[:algorithm].present? && %w[kmeans hierarchical dbscan].include?(params[:algorithm])
      return render json: { error: "Invalid algorithm. Must be 'kmeans', 'hierarchical', or 'dbscan'" }, status: :bad_request
    end
    
    # Get embeddings to process
    embedding_ids = get_embeddings_for_reduction
    
    # Return error if no embeddings found
    if embedding_ids.empty?
      return render json: { error: "No embeddings found matching criteria" }, status: :not_found
    end
    
    # Prepare algorithm parameters
    algorithm_params = {}
    
    # Add parameters based on algorithm
    if params[:algorithm] == 'kmeans'
      algorithm_params['n_clusters'] = params[:n_clusters].to_i if params[:n_clusters].present?
      algorithm_params['max_clusters'] = params[:max_clusters].to_i if params[:max_clusters].present?
    elsif params[:algorithm] == 'hierarchical'
      algorithm_params['n_clusters'] = params[:n_clusters].to_i if params[:n_clusters].present?
      algorithm_params['linkage'] = params[:linkage] if params[:linkage].present?
      algorithm_params['max_clusters'] = params[:max_clusters].to_i if params[:max_clusters].present?
      algorithm_params['distance_threshold'] = params[:distance_threshold].to_f if params[:distance_threshold].present?
    elsif params[:algorithm] == 'dbscan'
      algorithm_params['eps'] = params[:eps].to_f if params[:eps].present?
      algorithm_params['min_samples'] = params[:min_samples].to_i if params[:min_samples].present?
      algorithm_params['metric'] = params[:metric] if params[:metric].present?
    end
    
    # Get parent cluster for hierarchical clustering
    parent_cluster_id = params[:parent_cluster_id].present? ? params[:parent_cluster_id].to_i : nil
    
    # Start a background job for clustering
    job_id = DocumentProcessing::ClusterAnalysisWorker.perform_async(
      @organization.id,
      embedding_ids,
      params[:algorithm],
      algorithm_params,
      parent_cluster_id
    )
    
    # Return job ID
    render json: { job_id: job_id, embedding_count: embedding_ids.size, message: "Clustering started" }
  end
  
  private
  
  def set_organization
    @organization = Organization.find(params[:organization_id])
  end
  
  def check_access_permission
    unless OrganizationUser.exists?(organization: @organization, user: current_user)
      render json: { error: "You don't have access to this organization" }, status: :forbidden
    end
  end
  
  def authorize_projection(projection)
    unless projection.organization_id == @organization.id
      render json: { error: "Projection not found in this organization" }, status: :not_found
    end
  end
  
  def filter_projections
    projections = VectorProjection.where(organization: @organization)
    
    # Filter by algorithm
    projections = projections.where(algorithm: params[:algorithm]) if params[:algorithm].present?
    
    # Filter by LOD level with a default of highest detail
    lod_level = params[:lod_level].present? ? params[:lod_level].to_i : 0
    projections = projections.where(lod_level: lod_level)
    
    # Filter by embedding model
    if params[:model].present?
      projections = projections
        .joins(:vector_embedding)
        .where(vector_embeddings: { model_name: params[:model] })
    end
    
    # Filter by embedding dimension
    if params[:dimension].present?
      projections = projections
        .joins(:vector_embedding)
        .where(vector_embeddings: { dimension: params[:dimension].to_i })
    end
    
    # Pagination (adapt for WebGL performance)
    page_size = params[:limit].present? ? params[:limit].to_i : 1000
    page_size = [page_size, 5000].min # Cap for performance
    
    projections
      .includes(vector_embedding: :document)
      .page(params[:page] || 1)
      .per(page_size)
  end
  
  def format_projection_for_visualization(projection)
    # Document info from embedding
    document = projection.vector_embedding.document
    
    # Format for Three.js
    {
      id: projection.id,
      coordinates: projection.projection_array,
      document_id: document.id,
      title: document.title,
      model: projection.vector_embedding.model_name,
      dimension: projection.vector_embedding.dimension
    }
  end
  
  def get_embeddings_for_reduction
    # Get embeddings by IDs if specified
    if params[:embedding_ids].present?
      embedding_ids = params[:embedding_ids].split(',').map(&:to_i)
      return VectorEmbedding
        .where(id: embedding_ids)
        .where(status: VectorEmbedding::STATUS_PROCESSED)
        .where(document: { organization_id: @organization.id })
        .pluck(:id)
    end
    
    # Or get embeddings by filter criteria
    embeddings = VectorEmbedding
      .joins(:document)
      .where(documents: { organization_id: @organization.id })
      .where(status: VectorEmbedding::STATUS_PROCESSED)
    
    # Filter by model
    if params[:model].present?
      embeddings = embeddings.where(model_name: params[:model])
    end
    
    # Filter by dimension
    if params[:dimension].present?
      embeddings = embeddings.where(dimension: params[:dimension].to_i)
    end
    
    # Limit the number of embeddings
    max_embeddings = params[:limit].present? ? params[:limit].to_i : 1000
    max_embeddings = [max_embeddings, 10000].min # Cap for performance
    
    embeddings.limit(max_embeddings).pluck(:id)
  end
end
