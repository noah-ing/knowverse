# frozen_string_literal: true

module Distributed
  module Testing
    # Network simulator for testing network failures in distributed systems
    class NetworkSimulator
      class << self
        # Simulate a network partition between nodes
        # @param node_ids [Array<String>] List of node IDs to isolate from the cluster
        def create_partition(node_ids)
          node_ids = Array(node_ids)
          
          # Update distributed service to simulate network partition
          node_ids.each do |node_id|
            toggle_node_connectivity(node_id, false)
          end
          
          Rails.logger.info("Simulated network partition created for nodes: #{node_ids.join(', ')}")
          
          # Return lambda to heal the partition
          -> { heal_partition(node_ids) }
        end
        
        # Simulate a network partition healing
        # @param node_ids [Array<String>] List of node IDs to reconnect to the cluster
        def heal_partition(node_ids)
          node_ids = Array(node_ids)
          
          # Restore network connectivity
          node_ids.each do |node_id|
            toggle_node_connectivity(node_id, true)
          end
          
          Rails.logger.info("Network partition healed for nodes: #{node_ids.join(', ')}")
        end
        
        # Simulate a node crash
        # @param node_id [String] ID of the node to crash
        def crash_node(node_id)
          # Simulate a node crash by stopping its services
          service = Distributed::DistributedService.instance
          node = service.cluster_nodes.find { |n| n.node_id == node_id }
          return unless node
          
          # Store the node's original state
          original_state = node.dup
          
          # Simulate crash by setting node to offline and clearing listeners
          node.status = :offline
          service.raft_adapter.on(:state_change) { |_| } if node_id == service.node_id
          
          Rails.logger.info("Simulated crash for node: #{node_id}")
          
          # Return lambda to recover the node
          -> { recover_node(node_id, original_state) }
        end
        
        # Simulate a node recovery
        # @param node_id [String] ID of the node to recover
        # @param original_state [Object] Original state of the node before crash
        def recover_node(node_id, original_state = nil)
          service = Distributed::DistributedService.instance
          node = service.cluster_nodes.find { |n| n.node_id == node_id }
          return unless node
          
          # Restore node to online state
          node.status = :online
          
          # Re-register event handlers if this is the current node
          if node_id == service.node_id
            service.raft_adapter.register_event_handlers
          end
          
          Rails.logger.info("Recovered node: #{node_id}")
        end
        
        # Corrupt log entries for a node
        # @param node_id [String] ID of the node to corrupt logs for
        # @param severity [Symbol] :minor, :moderate, or :severe
        def corrupt_logs(node_id, severity = :moderate)
          # Path to the node's Raft log directory
          log_path = Rails.root.join('tmp', 'raft', node_id, 'logs')
          return unless Dir.exist?(log_path)
          
          # Different severities corrupt different amounts of data
          corrupt_entries = case severity
                           when :minor
                             1
                           when :moderate
                             3
                           when :severe
                             5
                           else
                             1
                           end
          
          # Find log files and corrupt the latest ones
          log_files = Dir.glob(File.join(log_path, '*.log')).sort_by { |f| File.mtime(f) }.reverse
          log_files.take(corrupt_entries).each do |file|
            corrupt_file(file)
          end
          
          Rails.logger.info("Corrupted #{corrupt_entries} log entries for node: #{node_id}")
        end
        
        private
        
        # Toggle network connectivity for a node
        def toggle_node_connectivity(node_id, connected)
          service = Distributed::DistributedService.instance
          
          # If this is the current node, we need to update its outgoing connections
          if node_id == service.node_id
            service.cluster_nodes.each do |node|
              next if node.node_id == node_id
              node.reachable = connected
            end
          else
            # Otherwise update just this node's connectivity
            node = service.cluster_nodes.find { |n| n.node_id == node_id }
            node.reachable = connected if node
          end
        end
        
        # Corrupt a file by introducing random bytes
        def corrupt_file(file_path)
          return unless File.exist?(file_path)
          
          File.open(file_path, 'r+b') do |file|
            # Get file size and calculate corruption points
            size = file.size
            return if size < 10
            
            # Corrupt at 3 random positions
            3.times do
              # Choose random position (avoiding first and last 5 bytes)
              pos = rand(5..(size - 5))
              file.pos = pos
              
              # Write random byte
              file.putc(rand(256).chr)
            end
          end
        end
      end
    end
  end
end
