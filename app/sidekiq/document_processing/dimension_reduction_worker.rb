module DocumentProcessing
  class DimensionReductionWorker
    include Sidekiq::Worker
    
    sidekiq_options queue: :visualization, retry: 3
    
    # Supported algorithms
    ALGORITHMS = %w[tsne umap].freeze
    
    # Default parameters for each algorithm
    DEFAULT_PARAMS = {
      'tsne' => {
        'perplexity' => 30,
        'learning_rate' => 200,
        'iterations' => 1000,
        'dimensions' => 3
      },
      'umap' => {
        'n_neighbors' => 15,
        'min_dist' => 0.1,
        'dimensions' => 3
      }
    }.freeze
    
    # Worker parameters:
    # organization_id: ID of the organization
    # vector_embedding_ids: IDs of vector embeddings to process
    # algorithm: 'tsne' or 'umap'
    # params: Algorithm-specific parameters (optional)
    # lod_level: Level of detail (0=highest, 1=medium, 2=low, etc.)
    def perform(organization_id, vector_embedding_ids, algorithm = 'tsne', params = {}, lod_level = 0)
      # Validate parameters
      return unless ALGORITHMS.include?(algorithm)
      
      # Get organization and check quota
      organization = Organization.find(organization_id)
      check_organization_quota(organization, vector_embedding_ids.size)
      
      # Merge with default parameters
      algorithm_params = DEFAULT_PARAMS[algorithm].merge(params)
      
      # Get vector embeddings
      vector_embeddings = VectorEmbedding
        .where(id: vector_embedding_ids)
        .where(status: VectorEmbedding::STATUS_PROCESSED)
        .includes(:document)
      
      # Find the dimension for these embeddings (all should be the same)
      # In a real implementation, we'd handle mixed dimensions, but keeping it simple here
      return if vector_embeddings.empty?
      
      dimension = vector_embeddings.first.dimension
      embedding_model = vector_embeddings.first.embedding_model
      
      # Check if we've already done this projection recently
      # Skip if we already have this exact configuration
      existing = check_existing_projections(organization_id, algorithm, algorithm_params, dimension, embedding_model, lod_level)
      return if existing
      
      # For Level of Detail (LOD) processing:
      # LOD 0: All vectors (full resolution)
      # LOD 1: ~10% of vectors (medium resolution)
      # LOD 2: ~1% of vectors (low resolution)
      vector_embeddings = sample_for_lod(vector_embeddings, lod_level)
      
      # Get embeddings as array of vectors
      vectors = []
      embedding_ids = []
      
      vector_embeddings.each do |ve|
        vectors << ve.embedding
        embedding_ids << ve.id
      end
      
      # Call Python microservice for dimension reduction
      result = perform_dimension_reduction(vectors, algorithm, algorithm_params)
      
      # Save the projections
      save_projections(result, embedding_ids, organization_id, algorithm, algorithm_params, lod_level)
    end
    
    private
    
    def check_organization_quota(organization, vector_count)
      # Check organization quota for dimension reduction
      # Implementation will depend on your billing strategy
      # This is a placeholder for quota checking logic
      max_vectors = 100_000 # Example limit
      
      if vector_count > max_vectors
        raise "Exceeds organization quota: #{vector_count} vectors (max: #{max_vectors})"
      end
    end
    
    def check_existing_projections(organization_id, algorithm, params, dimension, embedding_model, lod_level)
      # Check if we have recent projections with the same parameters
      VectorProjection
        .joins(:vector_embedding)
        .where(
          organization_id: organization_id,
          algorithm: algorithm,
          lod_level: lod_level,
          vector_embeddings: { 
            dimension: dimension,
            embedding_model: embedding_model
          }
        )
        .where("parameters @> ?", params.to_json)
        .where("created_at > ?", 24.hours.ago)
        .exists?
    end
    
    def sample_for_lod(vector_embeddings, lod_level)
      case lod_level
      when 0
        # Full resolution - use all vectors
        vector_embeddings
      when 1
        # Medium resolution - ~10% of vectors
        sample_size = [vector_embeddings.size / 10, 100].max
        vector_embeddings.sample(sample_size)
      when 2
        # Low resolution - ~1% of vectors
        sample_size = [vector_embeddings.size / 100, 50].max
        vector_embeddings.sample(sample_size)
      else
        # Very low resolution - fixed small sample
        vector_embeddings.sample([vector_embeddings.size, 25].min)
      end
    end
    
    def perform_dimension_reduction(vectors, algorithm, params)
      # Use HaystackClient to call Python microservice
      # In a real implementation, this would call the actual service
      # For now, we'll simulate the response
      
      haystack_client = HaystackClient.new
      
      response = haystack_client.dimension_reduction(
        vectors: vectors,
        algorithm: algorithm,
        params: params
      )
      
      if response.success?
        response.data
      else
        raise "Dimension reduction failed: #{response.error}"
      end
    end
    
    def save_projections(result, embedding_ids, organization_id, algorithm, params, lod_level)
      # Save each projection to the database
      result.each_with_index do |coordinates, index|
        embedding_id = embedding_ids[index]
        
        # Get embedding to access its organization
        embedding = VectorEmbedding.find(embedding_id)
        
        # Create the projection
        VectorProjection.create!(
          vector_embedding_id: embedding_id,
          organization_id: organization_id,
          algorithm: algorithm,
          parameters: params,
          coordinates: coordinates,
          dimensions: params['dimensions'] || 3,
          lod_level: lod_level
        )
      end
    end
  end
end
