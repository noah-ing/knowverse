# frozen_string_literal: true

class VectorsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :check_access_permission

  # GET /organizations/:organization_id/vectors
  def index
    if table_exists?("vector_projections")
      @vector_projections = response_service.build_index_query
    else
      @vector_projections = []
      @table_missing = true
      @missing_table = "vector_projections"
    end

    respond_to do |format|
      format.html
      format.json { render json: response_service.index_json(@vector_projections) }
    end
  end

  # GET /organizations/:organization_id/vectors/projections
  def projections
    if params[:id].present?
      @projection = VectorProjection.find(params[:id])
      authorize_projection(@projection)
      return render json: embedding_service.format_for_visualization(@projection)
    end

    @vector_projections = search_service.filter_projections
    render json: response_service.visualization_data(@vector_projections, embedding_service)
  end

  # POST /organizations/:organization_id/vectors/reduce
  def reduce
    unless valid_reduction_algorithm?
      return render json: { error: "Invalid algorithm. Must be 'tsne', 'umap', or 'pca'" }, status: :bad_request
    end

    embeddings = search_service.get_embeddings_for_reduction_objects
    return render json: { error: "No embeddings found matching criteria" }, status: :not_found if embeddings.empty?

    algorithm_params = embedding_service.build_algorithm_params(params, params[:algorithm])
    lod_level = params[:lod_level].present? ? params[:lod_level].to_i : 0

    begin
      result = embedding_service.perform_dimension_reduction(embeddings, params[:algorithm], algorithm_params)
      saved_count = embedding_service.save_projections(result, embeddings, params[:algorithm], algorithm_params, lod_level)
      render json: response_service.reduction_success(saved_count, params[:algorithm])
    rescue => e
      Rails.logger.error("Dimension reduction failed: #{e.message}")
      saved_count = embedding_service.create_simple_projections(embeddings, params[:algorithm], algorithm_params, lod_level)
      render json: response_service.reduction_success(saved_count, params[:algorithm], fallback: true)
    end
  end

  # GET /organizations/:organization_id/vectors/clusters
  def clusters
    @clusters = search_service.filter_clusters

    respond_to do |format|
      format.html
      format.json { render json: response_service.clusters_json(@clusters, search_service.document_sample_size) }
    end
  end

  # POST /organizations/:organization_id/vectors/cluster
  def cluster
    unless valid_clustering_algorithm?
      return render json: { error: "Invalid algorithm. Must be 'kmeans', 'hierarchical', or 'dbscan'" }, status: :bad_request
    end

    embedding_ids = search_service.get_embeddings_for_reduction
    return render json: { error: "No embeddings found matching criteria" }, status: :not_found if embedding_ids.empty?

    algorithm_params = embedding_service.build_clustering_params(params, params[:algorithm])
    parent_cluster_id = params[:parent_cluster_id].present? ? params[:parent_cluster_id].to_i : nil

    job_id = DocumentProcessing::ClusterAnalysisWorker.perform_async(
      @organization.id, embedding_ids, params[:algorithm], algorithm_params, parent_cluster_id
    )

    render json: { job_id: job_id, embedding_count: embedding_ids.size, message: "Clustering started" }
  end

  private

  def set_organization
    @organization = Organization.find(params[:organization_id])
  end

  def check_access_permission
    return if OrganizationUser.exists?(organization: @organization, user: current_user)
    render json: { error: "You don't have access to this organization" }, status: :forbidden
  end

  def authorize_projection(projection)
    return if projection.organization_id == @organization.id
    render json: { error: "Projection not found in this organization" }, status: :not_found
  end

  def search_service
    @search_service ||= Vectors::SearchService.new(@organization, params)
  end

  def embedding_service
    @embedding_service ||= Vectors::EmbeddingService.new(@organization)
  end

  def response_service
    @response_service ||= Vectors::ResponseService.new(@organization, params)
  end

  def valid_reduction_algorithm?
    params[:algorithm].present? && %w[tsne umap pca].include?(params[:algorithm])
  end

  def valid_clustering_algorithm?
    params[:algorithm].present? && %w[kmeans hierarchical dbscan].include?(params[:algorithm])
  end
end
