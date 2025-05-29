# frozen_string_literal: true

module Distributed
  module Consensus
    # Adapter for mapping Raft state machine operations to our domain model
    class StateAdapter
      include Singleton
      
      attr_reader :current_state_version
      
      # Initialize the state adapter
      def initialize
        @state_lock = Mutex.new
        @state_handlers = {}
        @current_state_version = 0
        @state_history = {}
        @max_history_size = 10 # Keep the last 10 state versions for rollback
      end
      
      # Register a state handler for a specific command type
      def register_handler(command_type, handler)
        @state_handlers[command_type] = handler
      end
      
      # Apply a command to the state machine
      def apply_command(command)
        handler = @state_handlers[command[:command_type]]
        
        if handler.nil?
          Rails.logger.warn("No handler registered for command type: #{command[:command_type]}")
          return { success: false, error: "No handler registered for command type: #{command[:command_type]}" }
        end
        
        @state_lock.synchronize do
          # Execute the handler with the command payload
          result = handler.call(command[:payload], command[:organization_id])
          
          # If successful, increment state version and save state snapshot
          if result[:success]
            @current_state_version += 1
            save_state_snapshot
          end
          
          result
        end
      end
      
      # Create a full snapshot of the current state
      def create_snapshot
        @state_lock.synchronize do
          snapshot = {
            version: @current_state_version,
            timestamp: Time.now.to_i,
            indexes: capture_index_state,
            cluster_config: capture_cluster_config
          }
          
          # Save snapshot to disk
          save_snapshot(snapshot)
          
          snapshot
        end
      end
      
      # Restore state from a specific snapshot
      def restore_snapshot(snapshot_version)
        @state_lock.synchronize do
          snapshot = load_snapshot(snapshot_version)
          return { success: false, error: "Snapshot not found: #{snapshot_version}" } unless snapshot
          
          # Restore the state from the snapshot
          restore_index_state(snapshot[:indexes])
          restore_cluster_config(snapshot[:cluster_config])
          
          @current_state_version = snapshot[:version]
          
          { success: true, version: @current_state_version }
        end
      end
      
      # Roll back to a previous state version
      def rollback(target_version)
        @state_lock.synchronize do
          return { success: false, error: "Invalid target version: #{target_version}" } if target_version <= 0 || target_version > @current_state_version
          
          # If we have the state history for the target version, use it
          if @state_history[target_version]
            restore_state(@state_history[target_version])
            @current_state_version = target_version
            return { success: true, version: @current_state_version }
          end
          
          # Otherwise, find the closest snapshot and replay commands
          snapshot_version = find_closest_snapshot_version(target_version)
          return { success: false, error: "No suitable snapshot found for rollback" } unless snapshot_version
          
          restore_snapshot(snapshot_version)
          
          # Replay commands from snapshot version to target version
          replay_commands(snapshot_version, target_version)
          
          { success: true, version: @current_state_version }
        end
      end
      
      private
      
      # Capture the current state of all indexes
      def capture_index_state
        # In a real implementation, this would capture the state of all HNSW indexes
        # For now, we'll return an empty hash
        {}
      end
      
      # Capture the current cluster configuration
      def capture_cluster_config
        # In a real implementation, this would capture the cluster configuration
        # For now, we'll return a dummy config
        {
          nodes: Rails.configuration.distributed.cluster_nodes || [],
          leader: Distributed::Consensus::RaftAdapter.instance.current_leader,
          version: @current_state_version
        }
      end
      
      # Save a state snapshot to persistent storage
      def save_snapshot(snapshot)
        # In a real implementation, this would save the snapshot to disk
        # For now, we'll just log it
        Rails.logger.info("Saving state snapshot version #{snapshot[:version]}")
        
        # Keep in memory for development/testing
        @state_history[@current_state_version] = snapshot
        
        # Prune history if it exceeds max size
        prune_state_history
      end
      
      # Load a snapshot from persistent storage
      def load_snapshot(version)
        # In a real implementation, this would load the snapshot from disk
        # For now, we'll just return from memory
        @state_history[version]
      end
      
      # Restore index state from a snapshot
      def restore_index_state(indexes)
        # In a real implementation, this would restore all indexes from the snapshot
        # For now, we'll just log it
        Rails.logger.info("Restoring index state from snapshot")
      end
      
      # Restore cluster configuration from a snapshot
      def restore_cluster_config(config)
        # In a real implementation, this would restore the cluster configuration
        # For now, we'll just log it
        Rails.logger.info("Restoring cluster configuration from snapshot")
      end
      
      # Find the closest snapshot version less than or equal to the target
      def find_closest_snapshot_version(target_version)
        @state_history.keys
                      .select { |v| v <= target_version }
                      .max
      end
      
      # Replay commands from start_version to end_version
      def replay_commands(start_version, end_version)
        # In a real implementation, this would replay commands from the log
        # For now, we'll just log it
        Rails.logger.info("Replaying commands from version #{start_version} to #{end_version}")
        
        @current_state_version = end_version
      end
      
      # Save a snapshot of the current state
      def save_state_snapshot
        # In a real implementation, we might not save a snapshot for every state change
        # but instead use some heuristic (e.g., every N changes)
        if @current_state_version % 100 == 0
          create_snapshot
        end
        
        # Keep in memory for rollback
        @state_history[@current_state_version] = {
          version: @current_state_version,
          timestamp: Time.now.to_i,
          # Add more state as needed
        }
        
        # Prune history if it exceeds max size
        prune_state_history
      end
      
      # Prune state history to stay within max_history_size
      def prune_state_history
        return if @state_history.size <= @max_history_size
        
        # Remove oldest versions first
        versions_to_remove = @state_history.keys.sort[0...(@state_history.size - @max_history_size)]
        versions_to_remove.each { |v| @state_history.delete(v) }
      end
      
      # Restore state from a state object
      def restore_state(state)
        Rails.logger.info("Restoring state version #{state[:version]}")
        # In a real implementation, this would restore the full state
      end
    end
  end
end
