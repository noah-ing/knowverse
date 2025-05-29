# frozen_string_literal: true

module Distributed
  module Search
    # Distributed version of HNSW index store that works with Raft consensus and sharding
    class DistributedIndexStore
      attr_reader :organization_id, :memory_usage, :embedding_dimension
      
      # Initialize a new distributed index store for an organization
      def initialize(organization_id, embedding_dimension, config = {})
        @organization_id = organization_id
        @embedding_dimension = embedding_dimension
        @config = config
        @memory_usage = 0
        @local_store = nil
        @distributed_service = Distributed::DistributedService.instance
        
        # Get the local index if this node is responsible for this organization
        init_local_index if is_local_organization?
      end
      
      # Insert a vector into the distributed index
      def insert(vector, document_id)
        # Ensure vector has the correct dimension
        unless vector.size == @embedding_dimension
          raise ArgumentError, "Vector dimension mismatch: got #{vector.size}, expected #{@embedding_dimension}"
        end
        
        # Prepare vector data
        vector_data = {
          id: document_id,
          vector: vector,
          metadata: { timestamp: Time.now.to_i }
        }
        
        # Send to distributed service
        result = @distributed_service.add_vector(vector_data, @embedding_dimension, @organization_id)
        
        # If local operation, return the reference directly
        if is_local_organization? && @local_store
          # Return a unique distributed reference
          "#{@distributed_service.node_id}:#{result[:vector_id]}"
        else
          # For remote operations, create a placeholder reference
          "pending:#{document_id}"
        end
      end
      
      # Insert multiple vectors in a batch
      def insert_batch(vectors_with_ids)
        # Ensure all vectors have the correct dimension
        vectors_with_ids.each do |v|
          unless v[:vector].size == @embedding_dimension
            raise ArgumentError, "Vector dimension mismatch for #{v[:id]}: got #{v[:vector].size}, expected #{@embedding_dimension}"
          end
        end
        
        # Prepare vector data
        vectors_data = vectors_with_ids.map do |v|
          {
            id: v[:id],
            vector: v[:vector],
            metadata: v[:metadata] || { timestamp: Time.now.to_i }
          }
        end
        
        # Send to distributed service
        result = @distributed_service.add_vectors_batch(vectors_data, @embedding_dimension, @organization_id)
        
        # Return success status
        result[:success] || false
      end
      
      # Search for nearest neighbors
      def search(query_vector, k)
        # Ensure query vector has the correct dimension
        unless query_vector.size == @embedding_dimension
          raise ArgumentError, "Query vector dimension mismatch: got #{query_vector.size}, expected #{@embedding_dimension}"
        end
        
        # Use distributed service to search
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        results = @distributed_service.search(query_vector, @embedding_dimension, k, @organization_id)
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        # Track metrics
        duration_ms = (end_time - start_time) * 1000
        Rails.logger.debug("Distributed search completed in #{duration_ms.round(2)}ms for organization #{@organization_id}")
        
        # Transform results to match expected format if needed
        results.map do |r|
          {
            id: r[:id],
            distance: r[:distance],
            score: r[:score] || (1.0 / (1.0 + r[:distance])),
            metadata: r[:metadata] || {}
          }
        end
      end
      
      # Check if a document exists in the index
      def contains?(document_id)
        if is_local_organization? && @local_store
          # If local, check directly
          @local_store.contains?(document_id)
        else
          # For remote operations, we can't efficiently check without a query
          # In a real implementation, we might cache this information or have a specialized API
          false
        end
      end
      
      # Delete a document from the index
      def delete(document_id)
        # Send to distributed service
        result = @distributed_service.remove_vector(document_id, @organization_id)
        
        # Return success status
        result[:success] || false
      end
      
      # Update memory usage estimate
      def update_memory_usage
        if is_local_organization? && @local_store
          @memory_usage = @local_store.memory_usage
        else
          # For remote operations, we don't have accurate memory usage
          @memory_usage = 0
        end
        
        @memory_usage
      end
      
      private
      
      # Check if this organization's data should be stored on this node
      def is_local_organization?
        # Get the shard for this organization
        shard_manager = Distributed::Sharding::ShardingManager.instance
        shard_id = shard_manager.get_shard_for_organization(@organization_id)
        
        # Check if this node is responsible for this shard
        shard_id == @distributed_service.node_id
      end
      
      # Initialize the local index for this organization
      def init_local_index
        # Use the regular HnswIndexStore for local operations
        @local_store = Wasm::HnswIndexStore.new(@organization_id, @config.merge(dimension: @embedding_dimension))
        
        # Update memory usage
        update_memory_usage
      end
    end
  end
end
