# frozen_string_literal: true

module Distributed
  module Consensus
    # Adapter for Raft consensus - delegates to RaftNode for actual implementation
    # This adapter provides backwards compatibility with existing code while using
    # the real Raft implementation
    class RaftAdapter
      include Singleton

      # Raft node states (for compatibility)
      FOLLOWER = 0
      CANDIDATE = 1
      LEADER = 2

      # Map internal states to compatibility constants
      STATE_MAP = {
        RaftNode::State::FOLLOWER => FOLLOWER,
        RaftNode::State::CANDIDATE => CANDIDATE,
        RaftNode::State::LEADER => LEADER
      }.freeze

      attr_reader :cluster_nodes

      def initialize
        @initialized = false
        @lock = Mutex.new
        @cluster_nodes = []
        @callbacks = {
          state_change: [],
          leader_election: [],
          log_commit: [],
          membership_change: []
        }
      end

      # Get node ID
      def node_id
        @raft_node&.node_id || Rails.configuration.distributed&.node_id
      end

      # Get current state (backwards compatible integer)
      def state
        return FOLLOWER unless @raft_node
        STATE_MAP[@raft_node.state] || FOLLOWER
      end

      # Get current leader
      def current_leader
        @raft_node&.current_leader
      end

      # Initialize and start the Raft node
      def start
        return if @initialized

        @lock.synchronize do
          return if @initialized

          # Get configuration
          node_id = Rails.configuration.distributed&.node_id ||
                   ENV.fetch('DISTRIBUTED_NODE_ID', Socket.gethostname)

          @cluster_nodes = Rails.configuration.distributed&.cluster_nodes || []

          # Build peer registry from cluster nodes
          peers = build_peer_registry(@cluster_nodes)

          # Initialize storage
          @storage = RaftStorage.new(node_id: node_id)

          # Initialize RPC transport
          @rpc = RaftRPC.new(node_id: node_id, peers: peers)

          # Configure the Raft node
          @raft_node = RaftNode.instance
          @raft_node.configure(
            node_id: node_id,
            peers: @cluster_nodes,
            storage: @storage,
            rpc: @rpc
          )

          # Register event handlers that forward to compatibility callbacks
          register_event_handlers

          # Start the Raft node
          @raft_node.start

          # Start health monitoring
          Distributed::Monitoring::ClusterHealthMonitor.instance.start

          @initialized = true

          Rails.logger.info("[RaftAdapter] Started with node_id=#{node_id}, peers=#{@cluster_nodes.join(', ')}")
        end
      end

      # Stop the Raft node
      def stop
        return unless @initialized

        @lock.synchronize do
          return unless @initialized

          # Stop health monitoring
          Distributed::Monitoring::ClusterHealthMonitor.instance.stop

          # Stop the Raft node
          @raft_node&.stop

          # Close storage
          @storage&.close

          @initialized = false

          Rails.logger.info("[RaftAdapter] Stopped")
        end
      end

      # Submit a command to the Raft cluster
      def submit_command(command, data, organization_id = nil)
        ensure_initialized

        # Build command structure
        cmd = {
          type: command,
          data: data,
          organization_id: organization_id,
          timestamp: Time.now.to_i
        }

        # Submit to Raft consensus
        result = @raft_node.submit_command(cmd)

        # Return a Promise for backwards compatibility
        if result[:success]
          Concurrent::Promise.fulfill(result)
        else
          # If not leader, try to forward to leader
          if result[:error] == 'not_leader' && result[:leader_hint]
            forward_to_leader(result[:leader_hint], cmd)
          else
            Concurrent::Promise.reject(result[:error])
          end
        end
      end

      # Add a node to the cluster
      def add_node(new_node_id)
        ensure_initialized
        submit_command('add_node', { node_id: new_node_id })
      end

      # Remove a node from the cluster
      def remove_node(target_node_id)
        ensure_initialized
        submit_command('remove_node', { node_id: target_node_id })
      end

      # Register callback for different events
      def on(event, &block)
        return unless block_given? && @callbacks.key?(event)
        @callbacks[event] << block
      end

      # Check if this node is the leader
      def leader?
        @raft_node&.leader? || false
      end

      # Take a snapshot of the current state
      def take_snapshot
        ensure_initialized

        # Get current state from the state adapter
        state_data = StateAdapter.instance.create_snapshot
        serialized = Oj.dump(state_data, mode: :compat)

        # Create snapshot through storage
        @storage.create_snapshot(
          last_included_index: @raft_node.commit_index,
          last_included_term: @raft_node.current_term,
          data: serialized
        )
      end

      # Get cluster status
      def cluster_status
        return {} unless @raft_node

        status = @raft_node.cluster_status
        health = Distributed::Monitoring::ClusterHealthMonitor.instance.health_summary

        status.merge(health: health)
      end

      private

      def ensure_initialized
        raise "RaftAdapter not initialized. Call start() first." unless @initialized
      end

      def build_peer_registry(cluster_nodes)
        registry = {}

        cluster_nodes.each do |node_spec|
          # Node spec can be "node_id" or "node_id:host:port"
          parts = node_spec.split(':')
          node_id = parts[0]

          if parts.length >= 3
            registry[node_id] = {
              host: parts[1],
              port: parts[2].to_i
            }
          else
            # Assume localhost with different ports for development
            registry[node_id] = {
              host: 'localhost',
              port: 7100 + registry.size + 1
            }
          end
        end

        registry
      end

      def register_event_handlers
        @raft_node.on(:state_change) do |old_state, new_state|
          old_compat = STATE_MAP[old_state]
          new_compat = STATE_MAP[new_state]

          @callbacks[:state_change].each do |callback|
            callback.call(old_compat, new_compat)
          end
        end

        @raft_node.on(:leader_elected) do |leader_id, term|
          @callbacks[:leader_election].each do |callback|
            callback.call(leader_id)
          end
        end

        @raft_node.on(:log_committed) do |entry|
          @callbacks[:log_commit].each do |callback|
            callback.call(entry)
          end

          # Apply the command to the state machine
          apply_command(entry)
        end
      end

      def apply_command(entry)
        command = entry.command
        return unless command

        case command[:type]
        when 'add_node'
          handle_add_node(command[:data])
        when 'remove_node'
          handle_remove_node(command[:data])
        else
          # Forward to state adapter for domain-specific commands
          StateAdapter.instance.apply_command(
            command_type: command[:type],
            payload: command[:data],
            organization_id: command[:organization_id]
          )
        end
      end

      def handle_add_node(data)
        new_node_id = data[:node_id]
        return unless new_node_id

        @cluster_nodes << new_node_id unless @cluster_nodes.include?(new_node_id)

        # Update peer registry
        peers = build_peer_registry(@cluster_nodes)
        @rpc.update_peers(peers)

        @callbacks[:membership_change].each do |callback|
          callback.call({ type: :add, node_id: new_node_id })
        end

        Rails.logger.info("[RaftAdapter] Added node: #{new_node_id}")
      end

      def handle_remove_node(data)
        target_node_id = data[:node_id]
        return unless target_node_id

        @cluster_nodes.delete(target_node_id)

        # Update peer registry
        peers = build_peer_registry(@cluster_nodes)
        @rpc.update_peers(peers)

        @callbacks[:membership_change].each do |callback|
          callback.call({ type: :remove, node_id: target_node_id })
        end

        Rails.logger.info("[RaftAdapter] Removed node: #{target_node_id}")
      end

      def forward_to_leader(leader_id, command)
        Concurrent::Promise.new do
          begin
            result = @rpc.forward_to_leader(leader_id, command)

            if result[:success]
              result
            else
              raise result[:error] || 'Forward failed'
            end
          rescue => e
            Rails.logger.error("[RaftAdapter] Failed to forward to leader #{leader_id}: #{e.message}")
            raise e
          end
        end.execute
      end
    end
  end
end
