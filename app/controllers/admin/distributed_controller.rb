# frozen_string_literal: true

module Admin
  # DistributedController - Qdrant cluster management
  #
  # Provides admin dashboard for monitoring and managing the Qdrant vector cluster.
  # Replaces the old Ruby-based distributed system with Qdrant's native cluster management.
  #
  class DistributedController < ApplicationController
    before_action :require_admin

    # Show the distributed system dashboard
    def dashboard
      raw_status = qdrant_adapter.cluster_status
      @cluster_status = transform_cluster_status(raw_status)
      @search_metrics = build_search_metrics
      @healthy = SearchRouter.healthy?
      @collections = collection_stats
    end

    # Show detailed cluster status
    def status
      raw_status = qdrant_adapter.cluster_status
      @cluster_status = transform_cluster_status(raw_status)
      @collections = collection_stats_detailed
      @shard_metadata = build_shard_metadata
      @organization_shards = build_organization_shards

      respond_to do |format|
        format.html
        format.json { render json: { cluster: @cluster_status, collections: @collections } }
      end
    end

    # Create a snapshot for backup
    def snapshot
      collection = params[:collection]

      if collection.blank?
        flash[:error] = "Collection name required"
        redirect_to admin_distributed_dashboard_path
        return
      end

      result = qdrant_adapter.create_snapshot(collection)

      if result[:success]
        flash[:notice] = "Snapshot created: #{result[:snapshot]}"
      else
        flash[:error] = "Failed to create snapshot: #{result[:error]}"
      end

      redirect_to admin_distributed_dashboard_path
    end

    # Trigger index optimization
    def optimize
      collection = params[:collection]

      if collection.blank?
        flash[:error] = "Collection name required"
        redirect_to admin_distributed_dashboard_path
        return
      end

      result = qdrant_adapter.optimize(collection)

      if result[:success]
        flash[:notice] = "Optimization triggered for #{collection}"
      else
        flash[:error] = "Failed to optimize: #{result[:error]}"
      end

      redirect_to admin_distributed_dashboard_path
    end

    # Health check endpoint
    def health
      healthy = SearchRouter.healthy?

      render json: {
        status: healthy ? 'healthy' : 'unhealthy',
        cluster: qdrant_adapter.cluster_status,
        timestamp: Time.current.iso8601
      }, status: healthy ? :ok : :service_unavailable
    end

    # Metrics endpoint
    def metrics
      render json: {
        qdrant: qdrant_adapter.metrics,
        search: search_metrics,
        timestamp: Time.current.iso8601
      }
    end

    private

    def require_admin
      unless current_user&.admin?
        flash[:error] = "You must be an admin to access this page"
        redirect_to root_path
      end
    end

    def qdrant_adapter
      @qdrant_adapter ||= VectorStore::QdrantClusterAdapter.new(
        cluster_urls: ENV.fetch('QDRANT_CLUSTER_URLS', 'http://localhost:6333').split(','),
        api_key: ENV['QDRANT_API_KEY']
      )
    end

    def collection_stats
      Organization.all.map do |org|
        stats = SearchRouter.stats(org.id)
        {
          organization_id: org.id,
          organization_name: org.name,
          collection: "org_#{org.id}_documents",
          exists: stats[:exists],
          vectors_count: stats[:vectors_count] || 0,
          status: stats[:status] || 'unknown'
        }
      end
    rescue StandardError => e
      Rails.logger.error("Failed to get collection stats: #{e.message}")
      []
    end

    def collection_stats_detailed
      Organization.all.map do |org|
        collection_name = "org_#{org.id}_documents"
        info = qdrant_adapter.collection_info(collection_name)
        shard_info = qdrant_adapter.shard_info(collection_name)

        {
          organization_id: org.id,
          organization_name: org.name,
          collection: collection_name,
          info: info,
          shards: shard_info
        }
      end
    rescue StandardError => e
      Rails.logger.error("Failed to get detailed stats: #{e.message}")
      []
    end

    def search_metrics
      {
        total_searches: 0, # Would come from metrics tracking
        avg_latency_ms: 0
      }
    end

    # Transform Qdrant cluster status to view-compatible format
    def transform_cluster_status(raw_status)
      peers = raw_status[:peers] || {}
      peer_ids = peers.keys.map(&:to_s)
      raft_info = raw_status[:raft_info] || {}

      # Determine leader from raft info
      leader_peer_id = raft_info[:leader]&.to_s

      # Build node status map
      node_status = {}
      peers.each do |peer_id, peer_info|
        node_status[peer_id.to_s] = {
          status: peer_info.is_a?(Hash) && peer_info[:uri] ? 'online' : 'unknown',
          last_updated: Time.current.to_i
        }
      end

      {
        node_id: raw_status[:peer_id]&.to_s || 'local',
        raft_state: raft_state_to_int(raw_status[:status]),
        raft_leader: leader_peer_id,
        config_version: raft_info[:term] || 0,
        active_nodes: peer_ids.presence || ['local'],
        node_roles: {},
        node_status: node_status
      }
    end

    # Convert Qdrant status string to raft state integer
    def raft_state_to_int(status)
      case status&.to_s&.downcase
      when 'enabled', 'leader'
        2 # Leader
      when 'candidate'
        1 # Candidate
      else
        0 # Follower
      end
    end

    # Build search metrics for the dashboard
    def build_search_metrics
      metrics = qdrant_adapter.metrics
      {
        status: 'ready',
        avg_search_time: metrics[:avg_search_latency_ms] || 0,
        avg_insert_time: 0,
        max_memory_usage: 0,
        total_indexes: @collections&.size || 0
      }
    end

    # Build shard metadata from Qdrant collections
    def build_shard_metadata
      # Return empty hash - Qdrant handles sharding internally
      # This prevents nil errors in the view
      {}
    end

    # Build organization to shard mapping
    def build_organization_shards
      # Return empty hash - Qdrant handles shard assignment internally
      # This prevents nil errors in the view
      {}
    end
  end
end
