# frozen_string_literal: true

module Distributed
  # Main entry point for the distributed system
  class DistributedService
    include Singleton
    
    attr_reader :initialized, :node_id
    
    def initialize
      @initialized = false
      @node_id = nil
      @initialization_lock = Mutex.new
    end
    
    # Initialize the distributed service
    def initialize_service
      return if @initialized
      
      @initialization_lock.synchronize do
        return if @initialized
        
        # Initialize configuration adapter
        config_adapter = Distributed::Config::ConfigurationAdapter.instance
        config_adapter.initialize_with_defaults
        
        # Get node ID from configuration
        @node_id = Rails.configuration.distributed.node_id
        
        # Initialize Raft consensus
        init_consensus
        
        # Initialize sharding
        init_sharding
        
        # Register state handlers
        register_state_handlers
        
        # Start the Raft node
        Distributed::Consensus::RaftAdapter.instance.start
        
        @initialized = true
        
        Rails.logger.info("Distributed service initialized with node ID: #{@node_id}")
      end
    end
    
    # Shutdown the distributed service
    def shutdown
      return unless @initialized
      
      @initialization_lock.synchronize do
        return unless @initialized
        
        # Stop the Raft node
        Distributed::Consensus::RaftAdapter.instance.stop
        
        @initialized = false
        
        Rails.logger.info("Distributed service shut down")
      end
    end
    
    # Add a vector to the distributed index
    def add_vector(vector_data, embedding_dimension, organization_id)
      ensure_initialized
      
      # Get the shard for this organization
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_id = shard_manager.get_shard_for_organization(organization_id)
      
      # Check if this node is responsible for this shard
      if shard_id == @node_id
        # Local operation - update index directly
        add_vector_to_local_index(vector_data, embedding_dimension, organization_id)
      else
        # Remote operation - create log entry and submit to Raft
        log_adapter = Distributed::Consensus::LogAdapter.instance
        entry = log_adapter.create_vector_add_entry(vector_data, embedding_dimension, organization_id)
        
        # Submit command to Raft consensus
        raft_adapter = Distributed::Consensus::RaftAdapter.instance
        raft_adapter.submit_command('vector_add', entry, organization_id)
      end
    end
    
    # Add multiple vectors to the distributed index
    def add_vectors_batch(vectors_data, embedding_dimension, organization_id)
      ensure_initialized
      
      # Get the shard for this organization
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_id = shard_manager.get_shard_for_organization(organization_id)
      
      # Check if this node is responsible for this shard
      if shard_id == @node_id
        # Local operation - update index directly
        add_vectors_batch_to_local_index(vectors_data, embedding_dimension, organization_id)
      else
        # Remote operation - create log entry and submit to Raft
        log_adapter = Distributed::Consensus::LogAdapter.instance
        entry = log_adapter.create_vector_batch_add_entry(vectors_data, embedding_dimension, organization_id)
        
        # Submit command to Raft consensus
        raft_adapter = Distributed::Consensus::RaftAdapter.instance
        raft_adapter.submit_command('vector_batch_add', entry, organization_id)
      end
    end
    
    # Remove a vector from the distributed index
    def remove_vector(vector_id, organization_id)
      ensure_initialized
      
      # Get the shard for this organization
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_id = shard_manager.get_shard_for_organization(organization_id)
      
      # Check if this node is responsible for this shard
      if shard_id == @node_id
        # Local operation - update index directly
        remove_vector_from_local_index(vector_id, organization_id)
      else
        # Remote operation - create log entry and submit to Raft
        log_adapter = Distributed::Consensus::LogAdapter.instance
        entry = log_adapter.create_vector_remove_entry(vector_id, organization_id)
        
        # Submit command to Raft consensus
        raft_adapter = Distributed::Consensus::RaftAdapter.instance
        raft_adapter.submit_command('vector_remove', entry, organization_id)
      end
    end
    
    # Update a vector in the distributed index
    def update_vector(vector_data, organization_id)
      ensure_initialized
      
      # Get the shard for this organization
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_id = shard_manager.get_shard_for_organization(organization_id)
      
      # Check if this node is responsible for this shard
      if shard_id == @node_id
        # Local operation - update index directly
        update_vector_in_local_index(vector_data, organization_id)
      else
        # Remote operation - create log entry and submit to Raft
        log_adapter = Distributed::Consensus::LogAdapter.instance
        entry = log_adapter.create_vector_update_entry(vector_data, organization_id)
        
        # Submit command to Raft consensus
        raft_adapter = Distributed::Consensus::RaftAdapter.instance
        raft_adapter.submit_command('vector_update', entry, organization_id)
      end
    end
    
    # Perform a search query against the distributed index
    def search(query_vector, embedding_dimension, k, organization_id)
      ensure_initialized
      
      # Get the shard for this organization
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_id = shard_manager.get_shard_for_organization(organization_id)
      
      # Check if this node is responsible for this shard
      if shard_id == @node_id
        # Local operation - search index directly
        search_local_index(query_vector, embedding_dimension, k, organization_id)
      else
        # Remote operation - forward to appropriate node
        # In a real implementation, this would make an HTTP request to the appropriate node
        # For now, we'll simulate it by returning an empty result
        Rails.logger.info("Forwarding search request for organization #{organization_id} to shard #{shard_id}")
        []
      end
    end
    
    # Add a new node to the cluster
    def add_node(node_id)
      ensure_initialized
      
      # Check if this node is the leader
      raft_adapter = Distributed::Consensus::RaftAdapter.instance
      unless raft_adapter.leader?
        return { success: false, error: "Only the leader node can add nodes to the cluster" }
      end
      
      # Add node to configuration
      config_adapter = Distributed::Config::ConfigurationAdapter.instance
      result = config_adapter.add_node(node_id)
      
      return result unless result[:success]
      
      # Add node to sharding
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_result = shard_manager.add_node(node_id)
      
      # Add node to Raft consensus
      raft_result = raft_adapter.add_node(node_id)
      
      { success: true, config: result, sharding: shard_result, raft: raft_result }
    end
    
    # Remove a node from the cluster
    def remove_node(node_id)
      ensure_initialized
      
      # Check if this node is the leader
      raft_adapter = Distributed::Consensus::RaftAdapter.instance
      unless raft_adapter.leader?
        return { success: false, error: "Only the leader node can remove nodes from the cluster" }
      end
      
      # Check we're not removing ourselves
      if node_id == @node_id
        return { success: false, error: "A node cannot remove itself from the cluster" }
      end
      
      # Remove node from configuration
      config_adapter = Distributed::Config::ConfigurationAdapter.instance
      result = config_adapter.remove_node(node_id)
      
      return result unless result[:success]
      
      # Remove node from sharding
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_result = shard_manager.remove_node(node_id)
      
      # Remove node from Raft consensus
      raft_result = raft_adapter.remove_node(node_id)
      
      { success: true, config: result, sharding: shard_result, raft: raft_result }
    end
    
    # Get cluster status
    def get_cluster_status
      ensure_initialized
      
      # Get configuration
      config_adapter = Distributed::Config::ConfigurationAdapter.instance
      config = config_adapter.get_configuration
      
      # Get sharding information
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_metadata = shard_manager.get_shard_metadata
      
      # Get Raft status
      raft_adapter = Distributed::Consensus::RaftAdapter.instance
      raft_state = raft_adapter.state
      raft_leader = raft_adapter.current_leader
      
      {
        node_id: @node_id,
        raft_state: raft_state,
        raft_leader: raft_leader,
        config_version: config[:version],
        active_nodes: config[:nodes],
        node_roles: config[:roles],
        node_status: config[:status],
        shard_metadata: shard_metadata
      }
    end
    
    # Create a snapshot of the current state
    def create_snapshot
      ensure_initialized
      
      # Check if this node is the leader
      raft_adapter = Distributed::Consensus::RaftAdapter.instance
      unless raft_adapter.leader?
        return { success: false, error: "Only the leader node can create snapshots" }
      end
      
      # Create state snapshot
      state_adapter = Distributed::Consensus::StateAdapter.instance
      snapshot = state_adapter.create_snapshot
      
      # Create configuration snapshot
      config_adapter = Distributed::Config::ConfigurationAdapter.instance
      config_snapshot = config_adapter.get_configuration
      
      { success: true, state: snapshot, config: config_snapshot }
    end
    
    # Initiate a rollback to a previous state
    def rollback(target_version)
      ensure_initialized
      
      # Check if this node is the leader
      raft_adapter = Distributed::Consensus::RaftAdapter.instance
      unless raft_adapter.leader?
        return { success: false, error: "Only the leader node can initiate rollbacks" }
      end
      
      # Rollback state
      state_adapter = Distributed::Consensus::StateAdapter.instance
      state_result = state_adapter.rollback(target_version)
      
      return state_result unless state_result[:success]
      
      # Rollback configuration
      config_adapter = Distributed::Config::ConfigurationAdapter.instance
      config_result = config_adapter.rollback(target_version)
      
      { success: true, state: state_result, config: config_result }
    end
    
    private
    
    # Ensure the service is initialized
    def ensure_initialized
      raise "DistributedService not initialized. Call initialize_service() first." unless @initialized
    end
    
    # Initialize Raft consensus
    def init_consensus
      # Initialize the Raft adapter
      raft_adapter = Distributed::Consensus::RaftAdapter.instance
      
      # Register event handlers
      raft_adapter.on(:state_change) do |old_state, new_state|
        Rails.logger.info("Raft state changed from #{old_state} to #{new_state}")
      end
      
      raft_adapter.on(:leader_election) do |leader_id|
        Rails.logger.info("New leader elected: #{leader_id}")
      end
      
      raft_adapter.on(:log_commit) do |log_entry|
        Rails.logger.debug("Log entry committed: #{log_entry}")
      end
      
      raft_adapter.on(:membership_change) do |change|
        Rails.logger.info("Cluster membership changed: #{change}")
      end
    end
    
    # Initialize sharding
    def init_sharding
      # Initialize the sharding manager
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_manager.initialize_with_defaults
    end
    
    # Register state handlers
    def register_state_handlers
      state_adapter = Distributed::Consensus::StateAdapter.instance
      log_adapter = Distributed::Consensus::LogAdapter.instance
      
      # Register handlers for each command type
      log_adapter.class::CommandType.constants.each do |const|
        command_type = log_adapter.class::CommandType.const_get(const)
        
        state_adapter.register_handler(command_type) do |payload, organization_id|
          handle_command(command_type, payload, organization_id)
        end
      end
    end
    
    # Handle a command in the state machine
    def handle_command(command_type, payload, organization_id)
      log_adapter = Distributed::Consensus::LogAdapter.instance
      
      case command_type
      when log_adapter.class::CommandType::VECTOR_ADD
        add_vector_to_local_index(payload, payload[:dimension], organization_id)
      when log_adapter.class::CommandType::VECTOR_BATCH_ADD
        add_vectors_batch_to_local_index(payload[:vectors], payload[:dimension], organization_id)
      when log_adapter.class::CommandType::VECTOR_REMOVE
        remove_vector_from_local_index(payload[:vector_id], organization_id)
      when log_adapter.class::CommandType::VECTOR_UPDATE
        update_vector_in_local_index(payload, organization_id)
      when log_adapter.class::CommandType::INDEX_CREATE
        create_local_index(payload, organization_id)
      when log_adapter.class::CommandType::INDEX_DELETE
        delete_local_index(payload[:index_name], organization_id)
      when log_adapter.class::CommandType::INDEX_REBUILD
        rebuild_local_index(payload[:index_name], payload[:config], organization_id)
      else
        Rails.logger.warn("Unknown command type: #{command_type}")
        { success: false, error: "Unknown command type: #{command_type}" }
      end
    end
    
    # Add a vector to the local index
    def add_vector_to_local_index(vector_data, embedding_dimension, organization_id)
      # In a real implementation, this would use the HnswIndexStore to add the vector
      # For now, we'll log it
      Rails.logger.info("Adding vector #{vector_data[:id]} for organization #{organization_id} with dimension #{embedding_dimension}")
      
      # Update shard vector count
      update_shard_vector_count(@node_id, 1)
      
      { success: true, vector_id: vector_data[:id] }
    end
    
    # Add multiple vectors to the local index
    def add_vectors_batch_to_local_index(vectors_data, embedding_dimension, organization_id)
      # In a real implementation, this would use the HnswIndexStore to add the vectors
      # For now, we'll log it
      Rails.logger.info("Adding batch of #{vectors_data.size} vectors for organization #{organization_id} with dimension #{embedding_dimension}")
      
      # Update shard vector count
      update_shard_vector_count(@node_id, vectors_data.size)
      
      { success: true, count: vectors_data.size }
    end
    
    # Remove a vector from the local index
    def remove_vector_from_local_index(vector_id, organization_id)
      # In a real implementation, this would use the HnswIndexStore to remove the vector
      # For now, we'll log it
      Rails.logger.info("Removing vector #{vector_id} for organization #{organization_id}")
      
      # Update shard vector count
      update_shard_vector_count(@node_id, -1)
      
      { success: true, vector_id: vector_id }
    end
    
    # Update a vector in the local index
    def update_vector_in_local_index(vector_data, organization_id)
      # In a real implementation, this would use the HnswIndexStore to update the vector
      # For now, we'll log it
      Rails.logger.info("Updating vector #{vector_data[:id]} for organization #{organization_id}")
      
      { success: true, vector_id: vector_data[:id] }
    end
    
    # Create a local index
    def create_local_index(index_config, organization_id)
      # In a real implementation, this would create a new HNSW index
      # For now, we'll log it
      Rails.logger.info("Creating index #{index_config[:index_name]} for organization #{organization_id} with dimension #{index_config[:dimension]}")
      
      { success: true, index_name: index_config[:index_name] }
    end
    
    # Delete a local index
    def delete_local_index(index_name, organization_id)
      # In a real implementation, this would delete an HNSW index
      # For now, we'll log it
      Rails.logger.info("Deleting index #{index_name} for organization #{organization_id}")
      
      { success: true, index_name: index_name }
    end
    
    # Rebuild a local index
    def rebuild_local_index(index_name, config, organization_id)
      # In a real implementation, this would rebuild an HNSW index
      # For now, we'll log it
      Rails.logger.info("Rebuilding index #{index_name} for organization #{organization_id}")
      
      { success: true, index_name: index_name }
    end
    
    # Search the local index
    def search_local_index(query_vector, embedding_dimension, k, organization_id)
      # In a real implementation, this would use the HnswIndexStore to search the index
      # For now, we'll log it
      Rails.logger.info("Searching with dimension #{embedding_dimension} for organization #{organization_id}, k=#{k}")
      
      # Return empty result for now
      []
    end
    
    # Update the vector count for a shard
    def update_shard_vector_count(shard_id, delta)
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_manager.update_vector_count(shard_id, delta)
    end
  end
end
