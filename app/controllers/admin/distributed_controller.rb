# frozen_string_literal: true

module Admin
  class DistributedController < ApplicationController
    before_action :require_admin
    before_action :initialize_distributed_service, only: [:dashboard, :status, :add_node, :remove_node, :snapshot, :rollback]
    
    # Show the distributed system dashboard
    def dashboard
      @cluster_status = distributed_service.get_cluster_status
      @search_metrics = Distributed::Search::DistributedSearchService.instance.get_metrics
    end
    
    # Show detailed cluster status
    def status
      @cluster_status = distributed_service.get_cluster_status
      @shard_manager = Distributed::Sharding::ShardingManager.instance
      @shard_metadata = @shard_manager.get_shard_metadata
      
      # Get organization to shard mapping
      @organization_shards = {}
      Organization.all.each do |org|
        @organization_shards[org.id] = @shard_manager.get_shard_for_organization(org.id)
      end
      
      respond_to do |format|
        format.html
        format.json { render json: @cluster_status }
      end
    end
    
    # Add a node to the cluster
    def add_node
      node_id = params[:node_id]
      
      if node_id.blank?
        flash[:error] = "Node ID cannot be blank"
        redirect_to admin_distributed_dashboard_path
        return
      end
      
      result = distributed_service.add_node(node_id)
      
      if result[:success]
        flash[:notice] = "Node #{node_id} added successfully"
      else
        flash[:error] = "Failed to add node: #{result[:error]}"
      end
      
      redirect_to admin_distributed_dashboard_path
    end
    
    # Remove a node from the cluster
    def remove_node
      node_id = params[:node_id]
      
      if node_id.blank?
        flash[:error] = "Node ID cannot be blank"
        redirect_to admin_distributed_dashboard_path
        return
      end
      
      result = distributed_service.remove_node(node_id)
      
      if result[:success]
        flash[:notice] = "Node #{node_id} removed successfully"
      else
        flash[:error] = "Failed to remove node: #{result[:error]}"
      end
      
      redirect_to admin_distributed_dashboard_path
    end
    
    # Create a snapshot of the current state
    def snapshot
      result = distributed_service.create_snapshot
      
      if result[:success]
        flash[:notice] = "Snapshot created successfully: Version #{result[:state][:version]}"
      else
        flash[:error] = "Failed to create snapshot: #{result[:error]}"
      end
      
      redirect_to admin_distributed_dashboard_path
    end
    
    # Rollback to a previous state
    def rollback
      version = params[:version].to_i
      
      if version <= 0
        flash[:error] = "Invalid version number"
        redirect_to admin_distributed_dashboard_path
        return
      end
      
      result = distributed_service.rollback(version)
      
      if result[:success]
        flash[:notice] = "Rolled back to version #{version} successfully"
      else
        flash[:error] = "Failed to rollback: #{result[:error]}"
      end
      
      redirect_to admin_distributed_dashboard_path
    end
    
    private
    
    # Ensure the user is an admin
    def require_admin
      unless current_user&.admin?
        flash[:error] = "You must be an admin to access this page"
        redirect_to root_path
      end
    end
    
    # Initialize the distributed service
    def initialize_distributed_service
      unless Distributed::DistributedService.instance.initialized
        flash[:notice] = "Initializing distributed service..."
        Distributed::DistributedService.instance.initialize_service
      end
    end
    
    # Get the distributed service instance
    def distributed_service
      Distributed::DistributedService.instance
    end
  end
end
