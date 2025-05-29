module Wasm
  class HnswIndexStore
    attr_reader :organization_id, :memory_usage
    
    # Initialize a new HNSW index store for an organization
    def initialize(organization_id, config)
      @organization_id = organization_id
      @config = config
      @partitions = {}
      @document_to_partition = {}
      @active_partitions = Set.new
      @partition_access_times = {}
      @memory_usage = 0
      @max_active_partitions = 5  # Default, can be configured
      
      # Load configuration for this organization
      load_organization_config
    end
    
    # Insert a vector into the appropriate partition
    def insert(vector, document_id)
      # Calculate which partition this document belongs to
      partition_key = partition_for_document(document_id)
      
      # Ensure the partition is loaded
      ensure_partition_loaded(partition_key)
      
      # Insert the vector into the partition
      node_id = @partitions[partition_key].insert(vector, document_id)
      
      # Track which partition contains this document
      @document_to_partition[document_id] = partition_key
      
      # Update memory usage estimate
      update_memory_usage
      
      # Return a reference that includes partition and node ID
      "#{partition_key}:#{node_id}"
    end
    
    # Search for nearest neighbors
    def search(query_vector, k)
      results = []
      
      # Search across all active partitions
      @active_partitions.each do |partition_key|
        # Skip if partition isn't loaded
        next unless @partitions.key?(partition_key)
        
        # Search in this partition
        partition_results = @partitions[partition_key].search(query_vector, k)
        
        # Add to combined results
        results.concat(partition_results)
        
        # Update access time
        @partition_access_times[partition_key] = Time.current
      end
      
      # Sort and limit results
      results.sort_by { |r| r[:distance] }.take(k)
    end
    
    # Check if a document exists in the index
    def contains?(document_id)
      partition_key = @document_to_partition[document_id]
      return false unless partition_key
      
      ensure_partition_loaded(partition_key)
      @partitions[partition_key].contains?(document_id)
    end
    
    # Delete a document from the index
    def delete(document_id)
      partition_key = @document_to_partition[document_id]
      return false unless partition_key
      
      ensure_partition_loaded(partition_key)
      result = @partitions[partition_key].delete(document_id)
      
      # If successful, remove from tracking
      if result
        @document_to_partition.delete(document_id)
        update_memory_usage
      end
      
      result
    end
    
    # Get the partition for a document ID
    def partition_for_document(document_id)
      # Simple partitioning strategy based on ID
      partition_number = (document_id.to_i % 1_000_000) / @config[:partition_size]
      "org_#{@organization_id}_partition_#{partition_number}"
    end
    
    private
    
    # Load organization-specific configuration
    def load_organization_config
      # In production, we'd load this from the database
      # For now, just use the global config
      @partition_size = @config[:partition_size]
      @max_active_partitions = calculate_max_partitions
    end
    
    # Calculate maximum number of active partitions based on memory quota
    def calculate_max_partitions
      # Simple calculation: assume each partition uses ~500MB
      estimated_partition_mb = 500
      max_partitions = @config[:memory_quota_mb] / estimated_partition_mb
      
      # Ensure at least 1 and no more than 20 partitions
      [1, [max_partitions, 20].min].max
    end
    
    # Ensure a partition is loaded and ready for use
    def ensure_partition_loaded(partition_key)
      # If already loaded, just update access time
      if @partitions.key?(partition_key)
        @partition_access_times[partition_key] = Time.current
        @active_partitions.add(partition_key)
        return
      end
      
      # Check if we need to evict a partition
      if @active_partitions.size >= @max_active_partitions
        evict_least_used_partition
      end
      
      # Load/create the partition
      @partitions[partition_key] = create_partition(partition_key)
      @partition_access_times[partition_key] = Time.current
      @active_partitions.add(partition_key)
      
      # Update memory usage estimate
      update_memory_usage
    end
    
    # Create a new HNSW partition
    def create_partition(partition_key)
      # In production, we'd either create a new WASM HNSW graph
      # or load an existing one from storage
      # For now, create a simple Ruby HNSW implementation
      RubyHnswGraph.new(@config)
    end
    
    # Evict the least recently used partition
    def evict_least_used_partition
      return if @active_partitions.empty?
      
      # Find the partition with the oldest access time
      least_used = @active_partitions.min_by { |p| @partition_access_times[p] || Time.at(0) }
      
      # Remove from active set and unload
      @active_partitions.delete(least_used)
      
      # In production, we'd persist the partition to storage before unloading
      # For now, just remove the reference
      @partitions.delete(least_used)
      
      # Update memory usage estimate
      update_memory_usage
    end
    
    # Update memory usage estimate
    def update_memory_usage
      # Sum up memory usage across all active partitions
      @memory_usage = @partitions.sum do |_, partition|
        partition.respond_to?(:memory_usage) ? partition.memory_usage : 100_000_000
      end
    end
  end
  
  # Simple Ruby implementation of HNSW graph for development
  # In production, this would be replaced by the WASM implementation
  class RubyHnswGraph
    attr_reader :memory_usage
    
    def initialize(config)
      @nodes = {}
      @document_map = {}
      @config = config
      @memory_usage = 0
    end
    
    # Insert a vector
    def insert(vector, document_id)
      node_id = @nodes.size
      
      # Store the vector and create connections
      @nodes[node_id] = {
        vector: vector,
        connections: Set.new
      }
      
      # Map document ID to node ID
      @document_map[document_id] = node_id
      
      # Connect to nearest neighbors
      connect_to_neighbors(node_id)
      
      # Update memory usage estimate
      update_memory_usage
      
      node_id
    end
    
    # Search for nearest neighbors
    def search(query_vector, k)
      return [] if @nodes.empty?
      
      # Calculate distances to all nodes
      distances = @nodes.map do |node_id, node|
        [node_id, euclidean_distance(query_vector, node[:vector])]
      end
      
      # Sort by distance and take top k
      nearest = distances.sort_by { |_, distance| distance }.take(k)
      
      # Convert to result format
      nearest.map do |node_id, distance|
        document_id = @document_map.key(node_id)
        {
          id: document_id,
          distance: distance,
          score: 1.0 / (1.0 + distance)  # Convert distance to similarity score
        }
      end
    end
    
    # Check if a document exists
    def contains?(document_id)
      @document_map.key?(document_id)
    end
    
    # Delete a document
    def delete(document_id)
      node_id = @document_map[document_id]
      return false unless node_id
      
      # Remove connections to this node
      @nodes.each do |id, node|
        node[:connections].delete(node_id)
      end
      
      # Remove the node
      @nodes.delete(node_id)
      @document_map.delete(document_id)
      
      # Update memory usage estimate
      update_memory_usage
      
      true
    end
    
    private
    
    # Connect a node to its nearest neighbors
    def connect_to_neighbors(node_id)
      return if @nodes.size <= 1
      
      node = @nodes[node_id]
      
      # Find nearest neighbors
      distances = @nodes.except(node_id).map do |id, n|
        [id, euclidean_distance(node[:vector], n[:vector])]
      end
      
      # Connect to M nearest
      nearest = distances.sort_by { |_, distance| distance }.take(@config[:m])
      nearest.each do |neighbor_id, _|
        # Add bidirectional connections
        node[:connections].add(neighbor_id)
        @nodes[neighbor_id][:connections].add(node_id)
      end
    end
    
    # Calculate Euclidean distance between vectors
    def euclidean_distance(a, b)
      # Ensure same length
      raise "Vector dimensions don't match" if a.size != b.size
      
      # Calculate squared differences
      squared_diff_sum = a.zip(b).sum { |x, y| (x - y) ** 2 }
      
      # Return square root of sum
      Math.sqrt(squared_diff_sum)
    end
    
    # Update memory usage estimate
    def update_memory_usage
      # Rough estimate: each node with connections and vector
      vector_bytes = @nodes.values.sum { |n| n[:vector].size * 4 }  # 4 bytes per float
      connection_bytes = @nodes.values.sum { |n| n[:connections].size * 8 }  # 8 bytes per connection
      overhead_bytes = @nodes.size * 64  # Overhead per node
      
      @memory_usage = vector_bytes + connection_bytes + overhead_bytes
    end
  end
end
