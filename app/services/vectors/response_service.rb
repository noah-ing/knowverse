# frozen_string_literal: true

module Vectors
  # Service for building JSON responses for vectors endpoints
  class ResponseService
    attr_reader :organization, :params

    def initialize(organization, params = {})
      @organization = organization
      @params = params
    end

    # Build index JSON response for vector projections
    def index_json(projections)
      {
        vector_projections: projections.as_json(include: {
          vector_embedding: {
            only: [:id, :dimension, :embedding_model],
            include: { document: { only: [:id, :title] } }
          }
        }),
        total_count: projections.respond_to?(:total_count) ? projections.total_count : projections.size,
        current_page: projections.respond_to?(:current_page) ? projections.current_page : 1,
        total_pages: projections.respond_to?(:total_pages) ? projections.total_pages : 1
      }
    end

    # Build visualization data for projections endpoint
    def visualization_data(projections, embedding_service)
      {
        points: projections.map { |vp| embedding_service.format_for_visualization(vp) },
        algorithm: params[:algorithm] || 'tsne',
        lod_level: params[:lod_level] || 0,
        total_count: projections.count
      }
    end

    # Build reduction success response
    def reduction_success(saved_count, algorithm, fallback: false)
      response = {
        success: true,
        projection_count: saved_count,
        algorithm: algorithm,
        message: "Created #{saved_count} projections#{fallback ? ' (simplified)' : ''}"
      }
      response[:fallback] = true if fallback
      response
    end

    # Build clusters JSON response
    def clusters_json(clusters, document_sample_size)
      {
        clusters: clusters.map do |cluster|
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
        total_count: clusters.count
      }
    end

    # Build paginated index query
    def build_index_query
      projections = VectorProjection
        .where(organization: organization)
        .includes(:vector_embedding)
        .page(params[:page] || 1)
        .per(params[:per_page] || 1000)

      projections = projections.where(algorithm: params[:algorithm]) if params[:algorithm].present?

      if params[:model].present?
        projections = projections.joins(:vector_embedding).where(vector_embeddings: { embedding_model: params[:model] })
      end

      if params[:dimension].present?
        projections = projections.joins(:vector_embedding).where(vector_embeddings: { dimension: params[:dimension] })
      end

      projections = projections.where(lod_level: params[:lod_level]) if params[:lod_level].present?

      projections
    end
  end
end
