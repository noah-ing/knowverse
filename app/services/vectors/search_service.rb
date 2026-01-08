# frozen_string_literal: true

module Vectors
  # Service for vector search and filtering operations
  # Extracts search/filter logic from VectorsController
  class SearchService
    attr_reader :organization, :params

    def initialize(organization, params = {})
      @organization = organization
      @params = params
    end

    # Filter vector projections with various criteria
    def filter_projections
      projections = VectorProjection.where(organization: organization)

      # Filter by algorithm
      projections = projections.where(algorithm: params[:algorithm]) if params[:algorithm].present?

      # Filter by LOD level with a default of highest detail
      lod_level = params[:lod_level].present? ? params[:lod_level].to_i : 0
      projections = projections.where(lod_level: lod_level)

      # Filter by embedding model
      if params[:model].present?
        projections = projections
          .joins(:vector_embedding)
          .where(vector_embeddings: { embedding_model: params[:model] })
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

    # Get embedding IDs for dimension reduction (for async jobs)
    def get_embeddings_for_reduction
      # Get embeddings by IDs if specified
      if params[:embedding_ids].present?
        embedding_ids = params[:embedding_ids].split(',').map(&:to_i)
        return VectorEmbedding
          .where(id: embedding_ids)
          .where(status: VectorEmbedding::STATUS_PROCESSED)
          .where(document: { organization_id: organization.id })
          .pluck(:id)
      end

      # Or get embeddings by filter criteria
      embeddings = base_embeddings_query

      # Limit the number of embeddings
      max_embeddings = params[:limit].present? ? params[:limit].to_i : 1000
      max_embeddings = [max_embeddings, 10000].min # Cap for performance

      embeddings.limit(max_embeddings).pluck(:id)
    end

    # Get full embedding objects (not just IDs) for synchronous processing
    def get_embeddings_for_reduction_objects
      embeddings = base_embeddings_query.includes(:document)

      # Limit
      max_embeddings = params[:limit].present? ? params[:limit].to_i : 100
      max_embeddings = [max_embeddings, 500].min

      embeddings.limit(max_embeddings).to_a
    end

    # Filter clusters for organization
    def filter_clusters
      clusters = DocumentCluster.where(organization: organization)

      # Filter by algorithm if provided
      clusters = clusters.where(algorithm: params[:algorithm]) if params[:algorithm].present?

      # Filter by parent cluster for hierarchical view
      if params[:parent_cluster_id].present?
        clusters = clusters.where(parent_cluster_id: params[:parent_cluster_id])
      else
        # Top-level clusters only by default
        clusters = clusters.roots
      end

      # Get only clusters with minimum document count
      if params[:min_documents].present?
        clusters = clusters.with_documents_min(params[:min_documents].to_i)
      end

      clusters
    end

    # Get document sample size for cluster responses
    def document_sample_size
      size = [params[:document_sample_size].to_i, 10].min
      size <= 0 ? 3 : size
    end

    private

    def base_embeddings_query
      embeddings = VectorEmbedding
        .joins(:document)
        .where(documents: { organization_id: organization.id })
        .where(status: VectorEmbedding::STATUS_PROCESSED)

      # Filter by model
      embeddings = embeddings.where(embedding_model: params[:model]) if params[:model].present?

      # Filter by dimension
      embeddings = embeddings.where(dimension: params[:dimension].to_i) if params[:dimension].present?

      embeddings
    end
  end
end
