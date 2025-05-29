# frozen_string_literal: true

# Load environment variables for distributed system configuration
node_id = ENV.fetch('DISTRIBUTED_NODE_ID', Socket.gethostname)
cluster_nodes = ENV.fetch('DISTRIBUTED_CLUSTER_NODES', '').split(',').map(&:strip).reject(&:empty?)
start_auto = ENV.fetch('DISTRIBUTED_AUTO_START', 'false').downcase == 'true'

Rails.logger.info("Distributed system configuration:")
Rails.logger.info("  Node ID: #{node_id}")
Rails.logger.info("  Cluster nodes: #{cluster_nodes.join(', ')}")
Rails.logger.info("  Auto-start: #{start_auto}")

# Set up Rails configuration for distributed components
Rails.application.config.distributed = ActiveSupport::OrderedOptions.new
Rails.application.config.distributed.node_id = node_id
Rails.application.config.distributed.cluster_nodes = cluster_nodes
Rails.application.config.distributed.auto_start = start_auto

# Create required directories
FileUtils.mkdir_p(Rails.root.join('tmp', 'raft', node_id, 'logs'))
FileUtils.mkdir_p(Rails.root.join('tmp', 'raft', node_id, 'snapshots'))
FileUtils.mkdir_p(Rails.root.join('tmp', 'raft', node_id, 'state'))
FileUtils.mkdir_p(Rails.root.join('tmp', 'distributed', 'config'))

# Initialize the distributed service if auto-start is enabled
if Rails.application.config.distributed.auto_start && !Rails.env.test?
  Rails.application.config.after_initialize do
    Rails.logger.info("Auto-starting distributed service...")
    begin
      Distributed::DistributedService.instance.initialize_service
      Rails.logger.info("Distributed service started successfully.")
    rescue StandardError => e
      Rails.logger.error("Failed to start distributed service: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
  end
end

# Handle graceful shutdown
at_exit do
  if Rails.application.config.distributed.auto_start && 
     Distributed::DistributedService.instance.initialized && 
     !Rails.env.test?
    Rails.logger.info("Shutting down distributed service...")
    Distributed::DistributedService.instance.shutdown
    Rails.logger.info("Distributed service stopped.")
  end
end
