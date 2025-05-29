# frozen_string_literal: true

module Distributed
  module Consensus
    # Adapter for managing Raft log operations
    class LogAdapter
      include Singleton
      
      # Command types
      module CommandType
        # Vector operations
        VECTOR_ADD = 'vector_add'
        VECTOR_REMOVE = 'vector_remove'
        VECTOR_UPDATE = 'vector_update'
        VECTOR_BATCH_ADD = 'vector_batch_add'
        
        # Index operations
        INDEX_CREATE = 'index_create'
        INDEX_DELETE = 'index_delete'
        INDEX_REBUILD = 'index_rebuild'
        
        # Membership operations
        NODE_JOIN = 'node_join'
        NODE_LEAVE = 'node_leave'
        
        # Configuration operations
        CONFIG_CHANGE = 'config_change'
        
        # Snapshot operations
        SNAPSHOT_CREATE = 'snapshot_create'
        SNAPSHOT_RESTORE = 'snapshot_restore'
      end
      
      def initialize
        @log_listeners = []
        @log_directory = Rails.root.join('tmp', 'raft', 'logs')
        @serializer = Oj
      end
      
      # Transform a vector operation into a log entry
      def create_log_entry(command_type, payload, organization_id = nil)
        entry = {
          command_type: command_type,
          payload: payload,
          timestamp: Time.now.to_i
        }
        
        # Add tenant context if organization_id is provided
        entry[:organization_id] = organization_id if organization_id
        
        # Add unique log entry ID
        entry[:id] = SecureRandom.uuid
        
        entry
      end
      
      # Create log entry for adding a vector to the index
      def create_vector_add_entry(vector_data, embedding_dimension, organization_id)
        create_log_entry(
          CommandType::VECTOR_ADD,
          {
            vector_id: vector_data[:id],
            vector: vector_data[:vector],
            metadata: vector_data[:metadata],
            dimension: embedding_dimension
          },
          organization_id
        )
      end
      
      # Create log entry for removing a vector from the index
      def create_vector_remove_entry(vector_id, organization_id)
        create_log_entry(
          CommandType::VECTOR_REMOVE,
          { vector_id: vector_id },
          organization_id
        )
      end
      
      # Create log entry for updating a vector in the index
      def create_vector_update_entry(vector_data, organization_id)
        create_log_entry(
          CommandType::VECTOR_UPDATE,
          {
            vector_id: vector_data[:id],
            vector: vector_data[:vector],
            metadata: vector_data[:metadata]
          },
          organization_id
        )
      end
      
      # Create log entry for adding multiple vectors to the index
      def create_vector_batch_add_entry(vectors_data, embedding_dimension, organization_id)
        create_log_entry(
          CommandType::VECTOR_BATCH_ADD,
          {
            vectors: vectors_data.map do |v|
              {
                vector_id: v[:id],
                vector: v[:vector],
                metadata: v[:metadata]
              }
            end,
            dimension: embedding_dimension
          },
          organization_id
        )
      end
      
      # Create log entry for creating a new index
      def create_index_create_entry(index_config, organization_id)
        create_log_entry(
          CommandType::INDEX_CREATE,
          {
            index_name: index_config[:name],
            dimension: index_config[:dimension],
            m: index_config[:m] || 16,
            ef_construction: index_config[:ef_construction] || 200,
            parameters: index_config[:parameters] || {}
          },
          organization_id
        )
      end
      
      # Create log entry for deleting an index
      def create_index_delete_entry(index_name, organization_id)
        create_log_entry(
          CommandType::INDEX_DELETE,
          { index_name: index_name },
          organization_id
        )
      end
      
      # Create log entry for rebuilding an index
      def create_index_rebuild_entry(index_name, config, organization_id)
        create_log_entry(
          CommandType::INDEX_REBUILD,
          {
            index_name: index_name,
            config: config
          },
          organization_id
        )
      end
      
      # Create log entry for node joining
      def create_node_join_entry(node_id)
        create_log_entry(
          CommandType::NODE_JOIN,
          { node_id: node_id }
        )
      end
      
      # Create log entry for node leaving
      def create_node_leave_entry(node_id)
        create_log_entry(
          CommandType::NODE_LEAVE,
          { node_id: node_id }
        )
      end
      
      # Create log entry for configuration change
      def create_config_change_entry(old_config, new_config)
        create_log_entry(
          CommandType::CONFIG_CHANGE,
          {
            old_config: old_config,
            new_config: new_config
          }
        )
      end
      
      # Create log entry for creating a snapshot
      def create_snapshot_entry(snapshot_id, metadata)
        create_log_entry(
          CommandType::SNAPSHOT_CREATE,
          {
            snapshot_id: snapshot_id,
            metadata: metadata
          }
        )
      end
      
      # Apply a committed log entry to the state machine
      def apply_log_entry(entry)
        # This would be implemented to apply the log entry to the appropriate state machine
        # For now, we'll log it
        Rails.logger.info("Applying log entry: #{entry[:command_type]}")
        
        # The actual implementation would route to the appropriate handler based on command_type
        case entry[:command_type]
        when CommandType::VECTOR_ADD, CommandType::VECTOR_BATCH_ADD, CommandType::VECTOR_UPDATE, CommandType::VECTOR_REMOVE
          apply_vector_operation(entry)
        when CommandType::INDEX_CREATE, CommandType::INDEX_DELETE, CommandType::INDEX_REBUILD
          apply_index_operation(entry)
        when CommandType::NODE_JOIN, CommandType::NODE_LEAVE, CommandType::CONFIG_CHANGE
          apply_membership_operation(entry)
        when CommandType::SNAPSHOT_CREATE, CommandType::SNAPSHOT_RESTORE
          apply_snapshot_operation(entry)
        else
          Rails.logger.warn("Unknown command type: #{entry[:command_type]}")
        end
      end
      
      # Register a listener for log commits
      def register_listener(listener)
        @log_listeners << listener
      end
      
      # Serialize a log entry for storage
      def serialize(entry)
        @serializer.dump(entry)
      end
      
      # Deserialize a log entry from storage
      def deserialize(data)
        @serializer.load(data)
      end
      
      private
      
      # Apply vector operation to the state machine
      def apply_vector_operation(entry)
        # This would update the HNSW index store with the vector operation
        # For now, we'll log it
        if entry[:organization_id]
          Rails.logger.info("Applying vector operation for organization #{entry[:organization_id]}: #{entry[:command_type]}")
        else
          Rails.logger.info("Applying global vector operation: #{entry[:command_type]}")
        end
      end
      
      # Apply index operation to the state machine
      def apply_index_operation(entry)
        # This would create, delete, or rebuild the index
        # For now, we'll log it
        if entry[:organization_id]
          Rails.logger.info("Applying index operation for organization #{entry[:organization_id]}: #{entry[:command_type]}")
        else
          Rails.logger.info("Applying global index operation: #{entry[:command_type]}")
        end
      end
      
      # Apply membership operation to the state machine
      def apply_membership_operation(entry)
        # This would update the cluster membership
        # For now, we'll log it
        Rails.logger.info("Applying membership operation: #{entry[:command_type]}")
      end
      
      # Apply snapshot operation to the state machine
      def apply_snapshot_operation(entry)
        # This would create or restore a snapshot
        # For now, we'll log it
        Rails.logger.info("Applying snapshot operation: #{entry[:command_type]}")
      end
      
      # Notify listeners of a log commit
      def notify_listeners(entry)
        @log_listeners.each do |listener|
          listener.on_log_commit(entry)
        end
      end
    end
  end
end
