# frozen_string_literal: true

module Distributed
  module Sharding
    # Manages the allocation of organizations to shards
    class ShardingManager
      include Singleton
      
      attr_reader :strategy
      
      def initialize
        @strategy = DefaultShardingStrategy.new
        @shard_lock = Mutex.new
        @shard_assignments = {}
        @shard_metadata = {}
        @initialized = false
      end
      
      # Initialize sharding manager
      def initialize_with_defaults
        return if @initialized
        
        @shard_lock.synchronize do
          return if @initialized
          
          # Get cluster nodes from configuration
          config_adapter = Distributed::Config::ConfigurationAdapter.instance
          config = config_adapter.get_configuration
          
          # Initialize sharding with available nodes
          @strategy.initialize_ring(config[:nodes])
          
          # Initialize metadata for each shard
          config[:nodes].each do |node_id|
            @shard_metadata[node_id] = {
              status: 'ready',
              vector_count: 0,
              max_vectors: 1_000_000, # Default limit of 1M vectors per shard
              organizations: []
            }
          end
          
          @initialized = true
          
          Rails.logger.info("Initialized sharding manager with #{config[:nodes].size} nodes")
        end
      end
      
      # Get shard for a specific organization
      def get_shard_for_organization(organization_id)
        ensure_initialized
        
        @shard_lock.synchronize do
          # If organization already assigned to a shard, return it
          return @shard_assignments[organization_id] if @shard_assignments[organization_id]
          
          # Otherwise, assign to a shard using the strategy
          shard = @strategy.get_shard_for_key(organization_id.to_s)
          @shard_assignments[organization_id] = shard
          
          # Update shard metadata
          update_shard_metadata(shard, organization_id, :add)
          
          Rails.logger.info("Assigned organization #{organization_id} to shard #{shard}")
          
          shard
        end
      end
      
      # Get all organizations assigned to a shard
      def get_organizations_for_shard(shard_id)
        ensure_initialized
        
        @shard_lock.synchronize do
          metadata = @shard_metadata[shard_id]
          return [] unless metadata
          
          metadata[:organizations]
        end
      end
      
      # Rebalance organizations across shards when adding/removing nodes
      def rebalance_shards(old_nodes, new_nodes)
        ensure_initialized
        
        @shard_lock.synchronize do
          Rails.logger.info("Rebalancing shards from #{old_nodes.size} to #{new_nodes.size} nodes")
          
          # Initialize the ring with new nodes
          @strategy.initialize_ring(new_nodes)
          
          # Track reassignments for logging
          reassignments = []
          
          # Reassign all organizations based on new ring
          new_assignments = {}
          @shard_assignments.each do |org_id, old_shard|
            new_shard = @strategy.get_shard_for_key(org_id.to_s)
            new_assignments[org_id] = new_shard
            
            if old_shard != new_shard
              reassignments << { organization_id: org_id, from: old_shard, to: new_shard }
              
              # Update shard metadata
              update_shard_metadata(old_shard, org_id, :remove) if @shard_metadata[old_shard]
              update_shard_metadata(new_shard, org_id, :add)
            end
          end
          
          # Update assignments
          @shard_assignments = new_assignments
          
          # Log reassignments
          Rails.logger.info("Rebalancing complete. #{reassignments.size} organizations reassigned.")
          reassignments.each do |r|
            Rails.logger.info("Reassigned organization #{r[:organization_id]} from shard #{r[:from]} to #{r[:to]}")
          end
          
          { success: true, reassignments: reassignments }
        end
      end
      
      # Add a new node to the sharding ring
      def add_node(node_id)
        ensure_initialized
        
        @shard_lock.synchronize do
          # Get current nodes
          config_adapter = Distributed::Config::ConfigurationAdapter.instance
          config = config_adapter.get_configuration
          old_nodes = config[:nodes]
          
          # Add new node
          new_nodes = old_nodes + [node_id]
          
          # Initialize metadata for new node
          @shard_metadata[node_id] = {
            status: 'ready',
            vector_count: 0,
            max_vectors: 1_000_000,
            organizations: []
          }
          
          # Rebalance shards
          rebalance_shards(old_nodes, new_nodes)
        end
      end
      
      # Remove a node from the sharding ring
      def remove_node(node_id)
        ensure_initialized
        
        @shard_lock.synchronize do
          # Get current nodes
          config_adapter = Distributed::Config::ConfigurationAdapter.instance
          config = config_adapter.get_configuration
          old_nodes = config[:nodes]
          
          # Check if node exists
          unless old_nodes.include?(node_id)
            return { success: false, error: "Node does not exist: #{node_id}" }
          end
          
          # Remove node
          new_nodes = old_nodes.reject { |n| n == node_id }
          
          # Check if we have enough nodes left
          if new_nodes.empty?
            return { success: false, error: "Cannot remove last node from cluster" }
          end
          
          # Remove metadata for node
          @shard_metadata.delete(node_id)
          
          # Rebalance shards
          rebalance_shards(old_nodes, new_nodes)
        end
      end
      
      # Update vector count for a shard
      def update_vector_count(shard_id, delta)
        ensure_initialized
        
        @shard_lock.synchronize do
          metadata = @shard_metadata[shard_id]
          return { success: false, error: "Shard not found: #{shard_id}" } unless metadata
          
          metadata[:vector_count] += delta
          
          Rails.logger.debug("Updated vector count for shard #{shard_id} by #{delta} to #{metadata[:vector_count]}")
          
          { success: true, count: metadata[:vector_count] }
        end
      end
      
      # Check if a shard has capacity for more vectors
      def shard_has_capacity?(shard_id)
        ensure_initialized
        
        @shard_lock.synchronize do
          metadata = @shard_metadata[shard_id]
          return false unless metadata
          
          metadata[:vector_count] < metadata[:max_vectors]
        end
      end
      
      # Get all shard metadata
      def get_shard_metadata
        ensure_initialized
        
        @shard_metadata.dup
      end
      
      # Set maximum vectors per shard
      def set_max_vectors_per_shard(shard_id, max_vectors)
        ensure_initialized
        
        @shard_lock.synchronize do
          metadata = @shard_metadata[shard_id]
          return { success: false, error: "Shard not found: #{shard_id}" } unless metadata
          
          metadata[:max_vectors] = max_vectors
          
          Rails.logger.info("Set maximum vectors for shard #{shard_id} to #{max_vectors}")
          
          { success: true }
        end
      end
      
      private
      
      # Ensure sharding manager is initialized
      def ensure_initialized
        raise "ShardingManager not initialized. Call initialize_with_defaults() first." unless @initialized
      end
      
      # Update shard metadata when adding/removing organizations
      def update_shard_metadata(shard_id, organization_id, operation)
        metadata = @shard_metadata[shard_id]
        return unless metadata
        
        case operation
        when :add
          metadata[:organizations] << organization_id unless metadata[:organizations].include?(organization_id)
        when :remove
          metadata[:organizations].delete(organization_id)
        end
      end
    end
    
    # Default sharding strategy using consistent hashing
    class DefaultShardingStrategy
      def initialize
        @ring = {}
        @sorted_keys = []
        @replicas = 10 # Number of virtual nodes per real node
      end
      
      # Initialize the hash ring with given nodes
      def initialize_ring(nodes)
        @ring = {}
        
        nodes.each do |node_id|
          @replicas.times do |i|
            key = generate_key("#{node_id}:#{i}")
            @ring[key] = node_id
          end
        end
        
        @sorted_keys = @ring.keys.sort
      end
      
      # Get shard for a specific key (e.g., organization ID)
      def get_shard_for_key(key)
        return @ring[@sorted_keys.first] if @ring.empty?
        
        hashed_key = generate_key(key)
        
        # Find the first point in the ring >= hashed_key
        idx = @sorted_keys.bsearch_index { |k| k >= hashed_key } || 0
        
        # Get the node at this position (wrapping around if needed)
        @ring[@sorted_keys[idx % @sorted_keys.size]]
      end
      
      private
      
      # Generate hash key
      def generate_key(key)
        Digest::SHA1.hexdigest(key.to_s)
      end
    end
  end
end
