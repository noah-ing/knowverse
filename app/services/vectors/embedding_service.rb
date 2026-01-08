# frozen_string_literal: true

module Vectors
  # Service for vector embedding and projection operations
  # Handles dimension reduction, projection saving, and data unpacking
  class EmbeddingService
    attr_reader :organization

    def initialize(organization)
      @organization = organization
    end

    # Perform dimension reduction synchronously via Haystack
    def perform_dimension_reduction(embeddings, algorithm, params)
      # Extract vectors from embeddings
      vectors = embeddings.map do |e|
        unpack_embedding(e.embedding_data)
      end.compact

      raise "No valid vectors to process" if vectors.empty?

      client = HaystackClient.new
      response = client.dimension_reduction(
        vectors: vectors,
        algorithm: algorithm,
        params: params
      )

      raise response.error unless response.success?
      response.data
    end

    # Save projections to database
    def save_projections(coordinates_array, embeddings, algorithm, params, lod_level)
      saved = 0
      coordinates_array.each_with_index do |coords, idx|
        next if idx >= embeddings.length

        embedding = embeddings[idx]

        # Delete existing projection with same parameters
        delete_existing_projection(embedding.id, algorithm, lod_level)

        create_projection(embedding, algorithm, coords, lod_level, params)
        saved += 1
      end
      saved
    end

    # Fallback: Create simple projections when Haystack is unavailable
    # Uses random projection (good enough for visualization)
    def create_simple_projections(embeddings, algorithm, params, lod_level)
      target_dims = params['dimensions'] || 3
      saved = 0

      embeddings.each do |embedding|
        # Delete existing
        delete_existing_projection(embedding.id, algorithm, lod_level)

        # Generate pseudo-random but deterministic coordinates based on embedding id
        # This ensures same embedding always gets same position
        coords = generate_deterministic_coordinates(embedding.id, target_dims)

        create_projection(embedding, algorithm, coords, lod_level, params.merge('fallback' => true))
        saved += 1
      end
      saved
    end

    # Format projection for visualization (Three.js compatible)
    def format_for_visualization(projection)
      document = projection.vector_embedding.document

      {
        id: projection.id,
        coordinates: projection.projection_array,
        document_id: document.id,
        title: document.title,
        model: projection.vector_embedding.embedding_model,
        dimension: projection.vector_embedding.dimension
      }
    end

    # Build algorithm parameters from request params
    def build_algorithm_params(params, algorithm)
      algorithm_params = {
        'dimensions' => params[:dimensions].present? ? params[:dimensions].to_i : 3
      }

      case algorithm
      when 'tsne'
        algorithm_params['perplexity'] = (params[:perplexity] || 30).to_i
        algorithm_params['learning_rate'] = (params[:learning_rate] || 200).to_f
        algorithm_params['iterations'] = (params[:iterations] || 1000).to_i
      when 'umap'
        algorithm_params['n_neighbors'] = (params[:n_neighbors] || 15).to_i
        algorithm_params['min_dist'] = (params[:min_dist] || 0.1).to_f
      end

      algorithm_params
    end

    # Build clustering algorithm parameters
    def build_clustering_params(params, algorithm)
      algorithm_params = {}

      case algorithm
      when 'kmeans'
        algorithm_params['n_clusters'] = params[:n_clusters].to_i if params[:n_clusters].present?
        algorithm_params['max_clusters'] = params[:max_clusters].to_i if params[:max_clusters].present?
      when 'hierarchical'
        algorithm_params['n_clusters'] = params[:n_clusters].to_i if params[:n_clusters].present?
        algorithm_params['linkage'] = params[:linkage] if params[:linkage].present?
        algorithm_params['max_clusters'] = params[:max_clusters].to_i if params[:max_clusters].present?
        algorithm_params['distance_threshold'] = params[:distance_threshold].to_f if params[:distance_threshold].present?
      when 'dbscan'
        algorithm_params['eps'] = params[:eps].to_f if params[:eps].present?
        algorithm_params['min_samples'] = params[:min_samples].to_i if params[:min_samples].present?
        algorithm_params['metric'] = params[:metric] if params[:metric].present?
      end

      algorithm_params
    end

    # Unpack embedding data from bytea format
    def unpack_embedding(data)
      return nil if data.nil?

      # Try different formats
      if data.is_a?(Array)
        data
      elsif data.is_a?(String)
        # Try JSON first
        begin
          JSON.parse(data)
        rescue JSON::ParserError
          # Try binary float array (packed as doubles)
          data.unpack('d*')
        end
      end
    rescue => e
      Rails.logger.error("Failed to unpack embedding: #{e.message}")
      nil
    end

    private

    def delete_existing_projection(embedding_id, algorithm, lod_level)
      VectorProjection.where(
        vector_embedding_id: embedding_id,
        organization_id: organization.id,
        algorithm: algorithm,
        lod_level: lod_level
      ).destroy_all
    end

    def create_projection(embedding, algorithm, coords, lod_level, params)
      VectorProjection.create!(
        vector_embedding_id: embedding.id,
        organization_id: organization.id,
        document_id: embedding.document_id,
        algorithm: algorithm,
        coordinates: coords,
        dimensions: coords.length,
        dimension_count: coords.length,
        lod_level: lod_level,
        parameters: params
      )
    end

    def generate_deterministic_coordinates(seed, target_dims)
      rng = Random.new(seed)
      target_dims.times.map do
        (rng.rand * 2 - 1) * 5  # Range: -5 to 5
      end
    end
  end
end
