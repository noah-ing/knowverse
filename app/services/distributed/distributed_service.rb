# frozen_string_literal: true

module Distributed
  # Main entry point for the distributed system
  # Provides real distributed vector storage with Raft consensus and sharding
  class DistributedService
    include Singleton

    attr_reader :initialized, :node_id

    def initialize
      @initialized = false
      @node_id = nil
      @initialization_lock = Mutex.new
      @remote_client = nil
      @node_registry = {}
      @local_indexes = {}  # organization_id:dimension => HnswIndexStore
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

        # Build node registry for remote communication
        build_node_registry

        # Initialize remote shard client
        @remote_client = Distributed::Search::RemoteShardClient.new(
          node_registry: @node_registry
        )

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

        # Close all local indexes
        @local_indexes.values.each(&:close) if @local_indexes.respond_to?(:values)

        @initialized = false

        Rails.logger.info("Distributed service shut down")
      end
    end

    # Add a vector to the distributed index
    def add_vector(vector_data, embedding_dimension, organization_id)
      ensure_initialized

      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_id = shard_manager.get_shard_for_organization(organization_id)

      if shard_id == @node_id
        # Local operation - update index directly
        add_vector_to_local_index(vector_data, embedding_dimension, organization_id)
      else
        # Remote operation - forward via HTTP
        begin
          result = @remote_client.insert(
            shard_id,
            vector: vector_data[:vector],
            document_id: vector_data[:id],
            organization_id: organization_id,
            dimension: embedding_dimension,
            metadata: vector_data[:metadata] || {}
          )

          { success: true, vector_id: vector_data[:id], remote: true }
        rescue Distributed::Search::RemoteShardClient::ShardUnavailableError => e
          # Fall back to Raft replication
          Rails.logger.warn("Remote insert failed, using Raft replication: #{e.message}")

          log_adapter = Distributed::Consensus::LogAdapter.instance
          entry = log_adapter.create_vector_add_entry(vector_data, embedding_dimension, organization_id)

          raft_adapter = Distributed::Consensus::RaftAdapter.instance
          raft_adapter.submit_command('vector_add', entry, organization_id)
        end
      end
    end

    # Add multiple vectors to the distributed index
    def add_vectors_batch(vectors_data, embedding_dimension, organization_id)
      ensure_initialized

      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_id = shard_manager.get_shard_for_organization(organization_id)

      if shard_id == @node_id
        add_vectors_batch_to_local_index(vectors_data, embedding_dimension, organization_id)
      else
        # Batch insert via Raft (more reliable for batches)
        log_adapter = Distributed::Consensus::LogAdapter.instance
        entry = log_adapter.create_vector_batch_add_entry(vectors_data, embedding_dimension, organization_id)

        raft_adapter = Distributed::Consensus::RaftAdapter.instance
        raft_adapter.submit_command('vector_batch_add', entry, organization_id)
      end
    end

    # Remove a vector from the distributed index
    def remove_vector(vector_id, organization_id)
      ensure_initialized

      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_id = shard_manager.get_shard_for_organization(organization_id)

      if shard_id == @node_id
        remove_vector_from_local_index(vector_id, organization_id)
      else
        begin
          result = @remote_client.delete(
            shard_id,
            document_id: vector_id,
            organization_id: organization_id
          )

          { success: true, vector_id: vector_id, remote: true }
        rescue Distributed::Search::RemoteShardClient::ShardUnavailableError => e
          # Fall back to Raft replication
          log_adapter = Distributed::Consensus::LogAdapter.instance
          entry = log_adapter.create_vector_remove_entry(vector_id, organization_id)

          raft_adapter = Distributed::Consensus::RaftAdapter.instance
          raft_adapter.submit_command('vector_remove', entry, organization_id)
        end
      end
    end

    # Update a vector in the distributed index
    def update_vector(vector_data, organization_id)
      ensure_initialized

      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_id = shard_manager.get_shard_for_organization(organization_id)

      if shard_id == @node_id
        update_vector_in_local_index(vector_data, organization_id)
      else
        log_adapter = Distributed::Consensus::LogAdapter.instance
        entry = log_adapter.create_vector_update_entry(vector_data, organization_id)

        raft_adapter = Distributed::Consensus::RaftAdapter.instance
        raft_adapter.submit_command('vector_update', entry, organization_id)
      end
    end

    # Perform a search query against the distributed index
    def search(query_vector, embedding_dimension, k, organization_id)
      ensure_initialized

      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_id = shard_manager.get_shard_for_organization(organization_id)

      if shard_id == @node_id
        # Local search
        search_local_index(query_vector, embedding_dimension, k, organization_id)
      else
        # Remote search - this is a READ operation, no consensus needed
        begin
          results = @remote_client.search(
            shard_id,
            query_vector: query_vector,
            k: k,
            organization_id: organization_id,
            dimension: embedding_dimension
          )

          results
        rescue Distributed::Search::RemoteShardClient::ShardUnavailableError => e
          Rails.logger.error("Remote search failed: #{e.message}")
          []
        end
      end
    end

    # Multi-shard search (scatter-gather)
    def search_all_shards(query_vector, embedding_dimension, k, organization_id)
      ensure_initialized

      config = Distributed::Config::ConfigurationAdapter.instance.get_configuration
      all_shards = config[:nodes] || [@node_id]

      # Search all shards in parallel
      @remote_client.parallel_search(
        shards: all_shards,
        query_vector: query_vector,
        k: k,
        organization_id: organization_id,
        dimension: embedding_dimension
      )
    end

    # Add a new node to the cluster
    def add_node(new_node_id)
      ensure_initialized

      raft_adapter = Distributed::Consensus::RaftAdapter.instance
      unless raft_adapter.leader?
        return { success: false, error: "Only the leader node can add nodes to the cluster" }
      end

      # Add node to configuration
      config_adapter = Distributed::Config::ConfigurationAdapter.instance
      result = config_adapter.add_node(new_node_id)

      return result unless result[:success]

      # Update node registry
      @node_registry[new_node_id] = parse_node_spec(new_node_id)
      @remote_client = Distributed::Search::RemoteShardClient.new(
        node_registry: @node_registry
      )

      # Add node to sharding
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_result = shard_manager.add_node(new_node_id)

      # Add node to Raft consensus
      raft_result = raft_adapter.add_node(new_node_id)

      { success: true, config: result, sharding: shard_result, raft: raft_result }
    end

    # Remove a node from the cluster
    def remove_node(target_node_id)
      ensure_initialized

      raft_adapter = Distributed::Consensus::RaftAdapter.instance
      unless raft_adapter.leader?
        return { success: false, error: "Only the leader node can remove nodes from the cluster" }
      end

      if target_node_id == @node_id
        return { success: false, error: "A node cannot remove itself from the cluster" }
      end

      # Remove node from configuration
      config_adapter = Distributed::Config::ConfigurationAdapter.instance
      result = config_adapter.remove_node(target_node_id)

      return result unless result[:success]

      # Update node registry
      @node_registry.delete(target_node_id)
      @remote_client = Distributed::Search::RemoteShardClient.new(
        node_registry: @node_registry
      )

      # Remove node from sharding
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_result = shard_manager.remove_node(target_node_id)

      # Remove node from Raft consensus
      raft_result = raft_adapter.remove_node(target_node_id)

      { success: true, config: result, sharding: shard_result, raft: raft_result }
    end

    # Get cluster status
    def get_cluster_status
      ensure_initialized

      config_adapter = Distributed::Config::ConfigurationAdapter.instance
      config = config_adapter.get_configuration

      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_metadata = shard_manager.get_shard_metadata

      raft_adapter = Distributed::Consensus::RaftAdapter.instance

      # Get health status from monitor
      health = Distributed::Monitoring::ClusterHealthMonitor.instance.health_summary

      # Get remote client metrics
      shard_metrics = @remote_client&.shard_metrics || {}

      {
        node_id: @node_id,
        raft_state: raft_adapter.state,
        raft_leader: raft_adapter.current_leader,
        config_version: config[:version],
        active_nodes: config[:nodes],
        node_roles: config[:roles],
        node_status: config[:status],
        shard_metadata: shard_metadata,
        health: health,
        shard_metrics: shard_metrics
      }
    end

    # Create a snapshot of the current state
    def create_snapshot
      ensure_initialized

      raft_adapter = Distributed::Consensus::RaftAdapter.instance
      unless raft_adapter.leader?
        return { success: false, error: "Only the leader node can create snapshots" }
      end

      state_adapter = Distributed::Consensus::StateAdapter.instance
      snapshot = state_adapter.create_snapshot

      config_adapter = Distributed::Config::ConfigurationAdapter.instance
      config_snapshot = config_adapter.get_configuration

      { success: true, state: snapshot, config: config_snapshot }
    end

    # Initiate a rollback to a previous state
    def rollback(target_version)
      ensure_initialized

      raft_adapter = Distributed::Consensus::RaftAdapter.instance
      unless raft_adapter.leader?
        return { success: false, error: "Only the leader node can initiate rollbacks" }
      end

      state_adapter = Distributed::Consensus::StateAdapter.instance
      state_result = state_adapter.rollback(target_version)

      return state_result unless state_result[:success]

      config_adapter = Distributed::Config::ConfigurationAdapter.instance
      config_result = config_adapter.rollback(target_version)

      { success: true, state: state_result, config: config_result }
    end

    private

    def ensure_initialized
      raise "DistributedService not initialized. Call initialize_service() first." unless @initialized
    end

    def build_node_registry
      config = Distributed::Config::ConfigurationAdapter.instance.get_configuration
      nodes = config[:nodes] || []

      @node_registry = {}
      nodes.each do |node_spec|
        @node_registry[node_spec] = parse_node_spec(node_spec)
      end
    end

    def parse_node_spec(node_spec)
      # Node spec can be "node_id" or "node_id:host:port"
      parts = node_spec.to_s.split(':')

      if parts.length >= 3
        { host: parts[1], port: parts[2].to_i }
      else
        # Default to localhost with derived port for development
        port_offset = node_spec.hash.abs % 100
        { host: 'localhost', port: 7200 + port_offset }
      end
    end

    def init_consensus
      raft_adapter = Distributed::Consensus::RaftAdapter.instance

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
        # Rebuild node registry when membership changes
        build_node_registry
      end
    end

    def init_sharding
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_manager.initialize_with_defaults
    end

    def register_state_handlers
      state_adapter = Distributed::Consensus::StateAdapter.instance
      log_adapter = Distributed::Consensus::LogAdapter.instance

      log_adapter.class::CommandType.constants.each do |const|
        command_type = log_adapter.class::CommandType.const_get(const)

        state_adapter.register_handler(command_type) do |payload, organization_id|
          handle_command(command_type, payload, organization_id)
        end
      end
    end

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

    # Get or create local index for organization/dimension
    def get_local_index(organization_id, embedding_dimension)
      key = "#{organization_id}:#{embedding_dimension}"

      @local_indexes[key] ||= begin
        # Use the WASM HNSW index store if available
        if defined?(Wasm::HnswIndexStore)
          Wasm::HnswIndexStore.new(organization_id, dimension: embedding_dimension)
        else
          # Fallback to in-memory structure
          InMemoryVectorIndex.new(dimension: embedding_dimension)
        end
      end
    end

    def add_vector_to_local_index(vector_data, embedding_dimension, organization_id)
      index = get_local_index(organization_id, embedding_dimension)

      vector = vector_data[:vector]
      document_id = vector_data[:id] || vector_data[:vector_id]

      result = index.insert(vector, document_id)

      update_shard_vector_count(@node_id, 1)

      Rails.logger.debug("Added vector #{document_id} to local index for org #{organization_id}")

      { success: true, vector_id: document_id, reference: result }
    end

    def add_vectors_batch_to_local_index(vectors_data, embedding_dimension, organization_id)
      index = get_local_index(organization_id, embedding_dimension)

      count = 0
      vectors_data.each do |v|
        vector = v[:vector]
        document_id = v[:id] || v[:vector_id]

        index.insert(vector, document_id)
        count += 1
      end

      update_shard_vector_count(@node_id, count)

      Rails.logger.debug("Added batch of #{count} vectors to local index for org #{organization_id}")

      { success: true, count: count }
    end

    def remove_vector_from_local_index(vector_id, organization_id)
      # Need to find which dimension index contains this vector
      @local_indexes.each do |key, index|
        if key.start_with?("#{organization_id}:")
          if index.respond_to?(:delete)
            index.delete(vector_id)
          end
        end
      end

      update_shard_vector_count(@node_id, -1)

      Rails.logger.debug("Removed vector #{vector_id} from local index for org #{organization_id}")

      { success: true, vector_id: vector_id }
    end

    def update_vector_in_local_index(vector_data, organization_id)
      # Update is delete + add
      vector_id = vector_data[:id] || vector_data[:vector_id]
      dimension = vector_data[:vector]&.size

      remove_vector_from_local_index(vector_id, organization_id)

      # Re-add doesn't increment count (net zero change)
      index = get_local_index(organization_id, dimension)
      index.insert(vector_data[:vector], vector_id)

      Rails.logger.debug("Updated vector #{vector_id} in local index for org #{organization_id}")

      { success: true, vector_id: vector_id }
    end

    def create_local_index(index_config, organization_id)
      dimension = index_config[:dimension]
      index = get_local_index(organization_id, dimension)

      Rails.logger.info("Created local index for org #{organization_id} with dimension #{dimension}")

      { success: true, index_name: index_config[:index_name] }
    end

    def delete_local_index(index_name, organization_id)
      # Find and remove indexes for this organization
      keys_to_remove = @local_indexes.keys.select { |k| k.start_with?("#{organization_id}:") }
      keys_to_remove.each { |k| @local_indexes.delete(k) }

      Rails.logger.info("Deleted local index #{index_name} for org #{organization_id}")

      { success: true, index_name: index_name }
    end

    def rebuild_local_index(index_name, config, organization_id)
      # For rebuild, we'd need to re-index all vectors
      Rails.logger.info("Rebuilding local index #{index_name} for org #{organization_id}")

      { success: true, index_name: index_name }
    end

    def search_local_index(query_vector, embedding_dimension, k, organization_id)
      index = get_local_index(organization_id, embedding_dimension)

      results = index.search(query_vector, k)

      results.map do |r|
        {
          id: r[:id],
          distance: r[:distance],
          score: r[:score] || (1.0 / (1.0 + r[:distance]))
        }
      end
    end

    def update_shard_vector_count(shard_id, delta)
      shard_manager = Distributed::Sharding::ShardingManager.instance
      shard_manager.update_vector_count(shard_id, delta)
    end

    # Simple in-memory vector index fallback
    class InMemoryVectorIndex
      def initialize(dimension:)
        @dimension = dimension
        @vectors = {}  # id => vector
      end

      def insert(vector, id)
        @vectors[id] = vector
        id
      end

      def delete(id)
        @vectors.delete(id)
      end

      def search(query_vector, k)
        return [] if @vectors.empty?

        # Brute force search for fallback
        results = @vectors.map do |id, vector|
          distance = euclidean_distance(query_vector, vector)
          { id: id, distance: distance, score: 1.0 / (1.0 + distance) }
        end

        results.sort_by { |r| r[:distance] }.take(k)
      end

      def close; end

      private

      def euclidean_distance(a, b)
        return Float::INFINITY if a.size != b.size

        sum = 0.0
        a.each_with_index do |val, i|
          diff = val - b[i]
          sum += diff * diff
        end

        Math.sqrt(sum)
      end
    end
  end
end
