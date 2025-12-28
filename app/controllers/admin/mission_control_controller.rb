class Admin::MissionControlController < Admin::BaseController
  layout 'admin'

  def index
    # System metrics
    @system_metrics = gather_system_metrics

    # Document processing pipeline
    @pipeline_status = gather_pipeline_status

    # Search operations
    @search_metrics = gather_search_metrics

    # Infrastructure status
    @infrastructure = gather_infrastructure_status

    # Recent activity log
    @activity_log = gather_activity_log
  end

  def status
    render json: {
      timestamp: Time.current.iso8601,
      uptime: calculate_uptime,
      system: gather_system_metrics,
      pipeline: gather_pipeline_status,
      search: gather_search_metrics,
      infrastructure: gather_infrastructure_status
    }
  end

  private

  def gather_system_metrics
    {
      total_documents: Document.count,
      processed_documents: Document.processed.count,
      pending_documents: Document.pending.count,
      processing_documents: Document.processing.count,
      error_documents: Document.errored.count,
      search_ready: Document.search_ready.count,
      total_embeddings: VectorEmbedding.count,
      total_users: User.count,
      active_users: User.where(subscription_status: 'active').count,
      total_organizations: Organization.count,
      total_searches: (SearchQuery.count rescue 0),
      avg_response_time: calculate_avg_response_time
    }
  end

  def gather_pipeline_status
    recent_jobs = []

    # Get recent document processing activity
    Document.order(updated_at: :desc).limit(10).each do |doc|
      recent_jobs << {
        id: doc.id,
        title: doc.title.truncate(30),
        status: doc.status,
        embedding_status: doc.embedding_status,
        updated_at: doc.updated_at
      }
    end

    {
      queue_depth: Document.pending.count + Document.processing.count,
      throughput_per_hour: calculate_throughput,
      recent_jobs: recent_jobs,
      stages: {
        extraction: {
          active: Document.where(status: 'processing').count,
          completed: Document.where(status: 'processed').count,
          failed: Document.where(status: 'error').count
        },
        embedding: {
          active: Document.where(embedding_status: 'processing').count,
          completed: Document.where(embedding_status: 'processed').count,
          failed: Document.where(embedding_status: 'error').count
        }
      }
    }
  end

  def gather_search_metrics
    # Recent search performance
    recent_queries = (SearchQuery.order(created_at: :desc).limit(20) rescue [])

    {
      total_queries: (SearchQuery.count rescue 0),
      queries_today: (SearchQuery.where('created_at > ?', Time.current.beginning_of_day).count rescue 0),
      avg_latency_ms: recent_queries.any? ? recent_queries.average(:latency).to_f.round(1) : 0,
      providers: gather_provider_stats,
      recent_queries: recent_queries.map { |q|
        {
          query: q.query_text.truncate(40),
          provider: q.search_provider,
          latency: q.latency,
          results: q.result_count,
          time: q.created_at
        }
      }
    }
  end

  def gather_provider_stats
    stats = {}
    SearchQuery.group(:provider).count.each do |provider, count|
      stats[provider] = {
        count: count,
        avg_latency: SearchQuery.where(provider: provider).average(:latency).to_f.round(1)
      }
    end
    stats
  rescue
    {}
  end

  def gather_infrastructure_status
    {
      database: check_database_status,
      redis: check_redis_status,
      haystack: check_haystack_status,
      qdrant: check_qdrant_status,
      storage: check_storage_status
    }
  end

  def check_database_status
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      { status: 'operational', latency_ms: measure_db_latency }
    rescue => e
      { status: 'error', message: e.message.truncate(50) }
    end
  end

  def check_redis_status
    begin
      redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379')
      start = Time.now
      redis.ping
      latency = ((Time.now - start) * 1000).round(1)
      { status: 'operational', latency_ms: latency }
    rescue => e
      { status: 'offline', message: e.message.truncate(50) }
    end
  end

  def check_haystack_status
    begin
      uri = URI.parse("#{ENV['HAYSTACK_SERVICE_URL'] || 'http://localhost:8000'}/health")
      response = Net::HTTP.get_response(uri)
      { status: response.code == '200' ? 'operational' : 'degraded', code: response.code }
    rescue => e
      { status: 'offline', message: e.message.truncate(50) }
    end
  end

  def check_qdrant_status
    begin
      uri = URI.parse("#{ENV['QDRANT_URL'] || 'http://localhost:6333'}/collections")
      response = Net::HTTP.get_response(uri)
      { status: response.code == '200' ? 'operational' : 'degraded', code: response.code }
    rescue => e
      { status: 'offline', message: e.message.truncate(50) }
    end
  end

  def check_storage_status
    begin
      # Check ActiveStorage is working
      {
        status: 'operational',
        blobs_count: ActiveStorage::Blob.count,
        total_size_mb: (ActiveStorage::Blob.sum(:byte_size) / 1_000_000.0).round(2)
      }
    rescue => e
      { status: 'error', message: e.message.truncate(50) }
    end
  end

  def gather_activity_log
    activities = []

    # Recent documents
    Document.order(created_at: :desc).limit(5).each do |doc|
      activities << {
        type: 'document',
        action: 'uploaded',
        subject: doc.title.truncate(25),
        time: doc.created_at,
        status: doc.status
      }
    end

    # Recent users
    User.order(created_at: :desc).limit(3).each do |user|
      activities << {
        type: 'user',
        action: 'joined',
        subject: user.email.split('@').first.truncate(15),
        time: user.created_at,
        status: 'success'
      }
    end

    # Sort by time
    activities.sort_by { |a| a[:time] }.reverse.first(10)
  end

  def calculate_uptime
    # Simulated uptime based on when app started
    boot_time = Rails.application.config.respond_to?(:boot_time) ? Rails.application.config.boot_time : Time.current - 1.hour
    seconds = (Time.current - boot_time).to_i

    days = seconds / 86400
    hours = (seconds % 86400) / 3600
    minutes = (seconds % 3600) / 60

    "#{days}d #{hours}h #{minutes}m"
  end

  def calculate_throughput
    # Documents processed in last hour
    Document.where('updated_at > ?', 1.hour.ago)
            .where(status: 'processed')
            .count
  end

  def calculate_avg_response_time
    (SearchQuery.where('created_at > ?', 24.hours.ago)
               .average(:latency)
               .to_f.round(1) rescue 0)
  end

  def measure_db_latency
    start = Time.now
    ActiveRecord::Base.connection.execute("SELECT 1")
    ((Time.now - start) * 1000).round(1)
  end
end
