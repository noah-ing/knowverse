module DocumentProcessing
  class ClusterAnalysisWorker
    include Sidekiq::Worker
    
    sidekiq_options queue: :visualization, retry: 3
    
    # Supported clustering algorithms
    ALGORITHMS = %w[kmeans hierarchical dbscan].freeze
    
    # Default parameters for each algorithm
    DEFAULT_PARAMS = {
      'kmeans' => {
        'n_clusters' => 0, # 0 means auto-detect
        'max_clusters' => 20,
        'random_state' => 42,
        'init' => 'k-means++'
      },
      'hierarchical' => {
        'n_clusters' => 0, # 0 means auto-detect
        'linkage' => 'ward',
        'max_clusters' => 20,
        'distance_threshold' => 1.5
      },
      'dbscan' => {
        'eps' => 0.5,
        'min_samples' => 5,
        'metric' => 'cosine'
      }
    }.freeze
    
    # Worker parameters:
    # organization_id: ID of the organization
    # vector_embedding_ids: IDs of vector embeddings to process for clustering
    # algorithm: 'kmeans', 'hierarchical', or 'dbscan'
    # params: Algorithm-specific parameters (optional)
    # parent_cluster_id: Optional parent cluster ID for hierarchical clustering
    def perform(organization_id, vector_embedding_ids, algorithm = 'kmeans', params = {}, parent_cluster_id = nil)
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
      
      # Extract vectors and document IDs
      vectors = []
      document_ids = []
      
      vector_embeddings.each do |ve|
        vectors << ve.embedding
        document_ids << ve.document_id
      end
      
      return if vectors.empty?
      
      # Get dimension and model information
      dimension = vector_embeddings.first.dimension
      model_name = vector_embeddings.first.model_name
      
      # Call Python microservice for clustering
      result = perform_clustering(vectors, document_ids, algorithm, algorithm_params)
      
      # Handle parent cluster reference if this is a sub-clustering
      parent_cluster = nil
      if parent_cluster_id.present?
        parent_cluster = DocumentCluster.find_by(id: parent_cluster_id)
        return unless parent_cluster # Abort if parent cluster doesn't exist
      end
      
      # Save the clusters and memberships
      save_clusters(
        result, 
        document_ids, 
        organization_id, 
        algorithm, 
        algorithm_params, 
        parent_cluster_id,
        dimension,
        model_name
      )
    end
    
    private
    
    def check_organization_quota(organization, vector_count)
      # Check organization quota for clustering
      # Implementation will depend on your billing strategy
      # This is a placeholder for quota checking logic
      max_vectors = 100_000 # Example limit
      
      if vector_count > max_vectors
        raise "Exceeds organization quota: #{vector_count} vectors (max: #{max_vectors})"
      end
    end
    
    def perform_clustering(vectors, document_ids, algorithm, params)
      # Use HaystackClient to call Python microservice
      # In a real implementation, this would call the actual service
      
      haystack_client = HaystackClient.new
      
      response = haystack_client.cluster_documents(
        vectors: vectors,
        document_ids: document_ids,
        algorithm: algorithm,
        params: params
      )
      
      if response.success?
        response.data
      else
        raise "Clustering failed: #{response.error}"
      end
    end
    
    def save_clusters(result, document_ids, organization_id, algorithm, params, parent_cluster_id, dimension, model_name)
      # The expected result format from the Python service:
      # {
      #   'clusters': [
      #     { 
      #       'centroid': [x, y, z...], 
      #       'document_indices': [0, 5, 10...],
      #       'membership_strengths': [0.9, 0.8, 0.7...],
      #       'metadata': { 'common_terms': ['term1', 'term2'...], 'variance': 0.2, ... }
      #     },
      #     ...
      #   ]
      # }
      
      # Delete existing clusters if re-clustering the same documents with same algorithm
      if parent_cluster_id.nil?
        # Only clean top-level clusters - for subclusters we want to keep the hierarchy
        clear_existing_clusters(organization_id, document_ids, algorithm)
      end
      
      # Save each cluster and its memberships
      result['clusters'].each do |cluster_data|
        # Create the cluster
        cluster = DocumentCluster.create!(
          organization_id: organization_id,
          algorithm: algorithm,
          parameters: params.merge(dimension: dimension, model_name: model_name),
          centroid: cluster_data['centroid'],
          document_count: cluster_data['document_indices'].size,
          metadata: cluster_data['metadata'] || {},
          parent_cluster_id: parent_cluster_id
        )
        
        # Create memberships for documents in this cluster
        cluster_data['document_indices'].each_with_index do |doc_index, i|
          document_id = document_ids[doc_index]
          strength = cluster_data['membership_strengths'] ? 
                     cluster_data['membership_strengths'][i] : 
                     1.0
          
          ClusterMembership.create!(
            document_cluster_id: cluster.id,
            document_id: document_id,
            membership_strength: strength
          )
        end
        
        # If hierarchical clustering is requested and this is a top-level cluster
        # And it has enough documents, perform sub-clustering
        if algorithm == 'hierarchical' && parent_cluster_id.nil? && 
           cluster.document_count > 10 && cluster.document_count <= 1000
           
          # Get the document IDs in this cluster
          sub_document_ids = cluster.documents.pluck(:id)
          
          # Get the vector embeddings for these documents
          sub_vector_embedding_ids = VectorEmbedding
            .where(document_id: sub_document_ids)
            .where(status: VectorEmbedding::STATUS_PROCESSED)
            .where(dimension: dimension, model_name: model_name)
            .pluck(:id)
          
          # Schedule a sub-clustering job with this cluster as parent
          # Use the same algorithm but with adjusted parameters
          sub_params = params.dup
          sub_params['n_clusters'] = [params['n_clusters'] / 2, 3].max if params['n_clusters'].to_i > 0
          
          self.class.perform_async(
            organization_id, 
            sub_vector_embedding_ids, 
            algorithm, 
            sub_params, 
            cluster.id
          )
        end
      end
    end
    
    def clear_existing_clusters(organization_id, document_ids, algorithm)
      # Find existing clusters for these documents with the same algorithm
      existing_clusters = DocumentCluster
        .where(organization_id: organization_id, algorithm: algorithm)
        .joins(:cluster_memberships)
        .where(cluster_memberships: { document_id: document_ids })
        .distinct
      
      # Delete the clusters and their memberships (will cascade delete memberships)
      existing_clusters.destroy_all
    end
  end
end
