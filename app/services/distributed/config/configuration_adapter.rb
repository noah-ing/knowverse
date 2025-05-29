# frozen_string_literal: true

module Distributed
  module Config
    # Adapter for managing distributed cluster configuration
    class ConfigurationAdapter
      include Singleton
      
      attr_reader :config_version, :active_nodes, :node_roles
      
      # Initialize the configuration adapter
      def initialize
        @config_lock = Mutex.new
        @config_version = 0
        @active_nodes = []
        @node_roles = {}
        @node_status = {}
        @snapshot_history = {}
        @max_history_size = 10
        @initialized = false
      end
      
      # Initialize with default configuration
      def initialize_with_defaults
        return if @initialized
        
        @config_lock.synchronize do
          return if @initialized
          
          # Load configuration from environment or config file
          load_initial_configuration
          
          # Set up snapshot directory
          setup_snapshot_directory
          
          @initialized = true
        end
      end
      
      # Get the current cluster configuration
      def get_configuration
        {
          version: @config_version,
          nodes: @active_nodes,
          roles: @node_roles,
          status: @node_status
        }
      end
      
      # Apply a configuration change with joint consensus
      def apply_configuration_change(old_config, new_config)
        @config_lock.synchronize do
          # Validate that old configuration matches current state
          unless old_config[:version] == @config_version && 
                 array_compare(old_config[:nodes], @active_nodes) &&
                 hash_compare(old_config[:roles], @node_roles)
            return { success: false, error: "Configuration mismatch. Cluster configuration has changed since the operation was initiated." }
          end
          
          # Apply new configuration
          @active_nodes = new_config[:nodes]
          @node_roles = new_config[:roles]
          @config_version += 1
          
          # Update node status for any new nodes
          update_node_status
          
          # Save configuration snapshot
          save_configuration_snapshot
          
          { success: true, version: @config_version }
        end
      end
      
      # Add a node to the configuration
      def add_node(node_id, role = 'follower')
        @config_lock.synchronize do
          # Check if node already exists
          if @active_nodes.include?(node_id)
            return { success: false, error: "Node already exists: #{node_id}" }
          end
          
          # Create old and new configuration for consensus
          old_config = get_configuration
          
          # Add node to active nodes and set role
          new_active_nodes = @active_nodes.dup
          new_active_nodes << node_id
          
          new_node_roles = @node_roles.dup
          new_node_roles[node_id] = role
          
          new_config = {
            version: @config_version + 1,
            nodes: new_active_nodes,
            roles: new_node_roles
          }
          
          # Apply the change using joint consensus
          result = apply_joint_consensus(old_config, new_config)
          
          if result[:success]
            Rails.logger.info("Added node #{node_id} with role #{role}")
          else
            Rails.logger.error("Failed to add node #{node_id}: #{result[:error]}")
          end
          
          result
        end
      end
      
      # Remove a node from the configuration
      def remove_node(node_id)
        @config_lock.synchronize do
          # Check if node exists
          unless @active_nodes.include?(node_id)
            return { success: false, error: "Node does not exist: #{node_id}" }
          end
          
          # Create old and new configuration for consensus
          old_config = get_configuration
          
          # Remove node from active nodes and roles
          new_active_nodes = @active_nodes.dup
          new_active_nodes.delete(node_id)
          
          new_node_roles = @node_roles.dup
          new_node_roles.delete(node_id)
          
          new_config = {
            version: @config_version + 1,
            nodes: new_active_nodes,
            roles: new_node_roles
          }
          
          # Apply the change using joint consensus
          result = apply_joint_consensus(old_config, new_config)
          
          if result[:success]
            Rails.logger.info("Removed node #{node_id}")
          else
            Rails.logger.error("Failed to remove node #{node_id}: #{result[:error]}")
          end
          
          result
        end
      end
      
      # Change a node's role
      def change_node_role(node_id, new_role)
        @config_lock.synchronize do
          # Check if node exists
          unless @active_nodes.include?(node_id)
            return { success: false, error: "Node does not exist: #{node_id}" }
          end
          
          # Create old and new configuration for consensus
          old_config = get_configuration
          
          # Update node role
          new_node_roles = @node_roles.dup
          new_node_roles[node_id] = new_role
          
          new_config = {
            version: @config_version + 1,
            nodes: @active_nodes.dup,
            roles: new_node_roles
          }
          
          # Apply the change using joint consensus
          result = apply_joint_consensus(old_config, new_config)
          
          if result[:success]
            Rails.logger.info("Changed role of node #{node_id} to #{new_role}")
          else
            Rails.logger.error("Failed to change role of node #{node_id}: #{result[:error]}")
          end
          
          result
        end
      end
      
      # Update the status of a node
      def update_node_status(node_id, status)
        @config_lock.synchronize do
          if status == 'online' && !@active_nodes.include?(node_id)
            Rails.logger.warn("Attempted to set status for unknown node: #{node_id}")
            return { success: false, error: "Node not in active list: #{node_id}" }
          end
          
          @node_status[node_id] = {
            status: status,
            last_updated: Time.now.to_i
          }
          
          Rails.logger.info("Updated status of node #{node_id} to #{status}")
          
          { success: true }
        end
      end
      
      # Roll back to a previous configuration version
      def rollback(target_version)
        @config_lock.synchronize do
          return { success: false, error: "Invalid target version: #{target_version}" } if target_version <= 0 || target_version > @config_version
          
          # If we have the snapshot for the target version, use it
          if @snapshot_history[target_version]
            restore_configuration(@snapshot_history[target_version])
            return { success: true, version: @config_version }
          end
          
          # Otherwise, return error
          { success: false, error: "No configuration snapshot found for version #{target_version}" }
        end
      end
      
      # Check if a node is currently active
      def node_active?(node_id)
        @active_nodes.include?(node_id) && @node_status[node_id]&.dig(:status) == 'online'
      end
      
      # Find the leader node
      def find_leader_node
        @node_roles.select { |_, role| role == 'leader' }.keys.first
      end
      
      private
      
      # Load initial configuration from environment or config file
      def load_initial_configuration
        # In a real implementation, this would load from environment variables or config files
        node_id = ENV.fetch('DISTRIBUTED_NODE_ID', Socket.gethostname)
        cluster_nodes = ENV.fetch('DISTRIBUTED_CLUSTER_NODES', '').split(',').map(&:strip)
        
        # Remove own node ID from cluster nodes if present
        cluster_nodes.delete(node_id)
        
        # Set up initial configuration
        @active_nodes = [node_id] + cluster_nodes
        @node_roles = { node_id => 'follower' }
        @active_nodes.each do |n|
          @node_roles[n] ||= 'follower'
          @node_status[n] = { status: 'unknown', last_updated: Time.now.to_i }
        end
        
        # Set own node as online
        @node_status[node_id] = { status: 'online', last_updated: Time.now.to_i }
        
        # Set up Rails configuration for distributed components
        unless Rails.configuration.respond_to?(:distributed)
          Rails.application.config.distributed = ActiveSupport::OrderedOptions.new
        end
        
        Rails.configuration.distributed.node_id = node_id
        Rails.configuration.distributed.cluster_nodes = cluster_nodes
        
        Rails.logger.info("Initialized distributed configuration with node ID: #{node_id}, Cluster nodes: #{cluster_nodes.join(', ')}")
      end
      
      # Set up snapshot directory
      def setup_snapshot_directory
        snapshot_dir = Rails.root.join('tmp', 'distributed', 'config')
        FileUtils.mkdir_p(snapshot_dir) unless File.directory?(snapshot_dir)
      end
      
      # Apply joint consensus for configuration change
      def apply_joint_consensus(old_config, new_config)
        # In a real implementation, this would use the Raft consensus mechanism
        # For now, we'll simulate it by directly applying the new configuration
        
        # Apply transitional joint configuration
        Rails.logger.info("Applying joint consensus configuration change from version #{old_config[:version]} to #{new_config[:version]}")
        
        # Apply final new configuration
        @active_nodes = new_config[:nodes]
        @node_roles = new_config[:roles]
        @config_version = new_config[:version]
        
        # Update node status for any new nodes
        update_node_status
        
        # Save configuration snapshot
        save_configuration_snapshot
        
        { success: true, version: @config_version }
      end
      
      # Update status for all nodes
      def update_node_status
        @active_nodes.each do |node_id|
          @node_status[node_id] ||= { status: 'unknown', last_updated: Time.now.to_i }
        end
      end
      
      # Save configuration snapshot
      def save_configuration_snapshot
        snapshot = {
          version: @config_version,
          nodes: @active_nodes.dup,
          roles: @node_roles.dup,
          status: @node_status.dup,
          timestamp: Time.now.to_i
        }
        
        # Save to memory
        @snapshot_history[@config_version] = snapshot
        
        # Prune history if it exceeds max size
        prune_snapshot_history
        
        # In a real implementation, also save to disk
        # save_snapshot_to_disk(snapshot)
        
        snapshot
      end
      
      # Restore configuration from a snapshot
      def restore_configuration(snapshot)
        @active_nodes = snapshot[:nodes].dup
        @node_roles = snapshot[:roles].dup
        @node_status = snapshot[:status].dup
        @config_version = snapshot[:version]
        
        Rails.logger.info("Restored configuration to version #{@config_version}")
      end
      
      # Save snapshot to disk
      def save_snapshot_to_disk(snapshot)
        snapshot_dir = Rails.root.join('tmp', 'distributed', 'config')
        snapshot_path = File.join(snapshot_dir, "config_#{snapshot[:version]}.json")
        
        File.write(snapshot_path, Oj.dump(snapshot, mode: :compat))
      end
      
      # Prune snapshot history to stay within max_history_size
      def prune_snapshot_history
        return if @snapshot_history.size <= @max_history_size
        
        # Remove oldest versions first
        versions_to_remove = @snapshot_history.keys.sort[0...(@snapshot_history.size - @max_history_size)]
        versions_to_remove.each { |v| @snapshot_history.delete(v) }
      end
      
      # Compare arrays for equality ignoring order
      def array_compare(a, b)
        a.sort == b.sort
      end
      
      # Compare hashes for equality
      def hash_compare(a, b)
        a == b
      end
    end
  end
end
