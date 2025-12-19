# Health check endpoint for container orchestration and monitoring
class HealthController < ApplicationController
  # Health checks are public - no authentication required

  def show
    health_status = {
      status: "healthy",
      timestamp: Time.current.iso8601,
      services: check_services,
      version: Rails.application.config.version || "1.0.0",
      environment: Rails.env
    }
    
    if all_services_healthy?(health_status[:services])
      render json: health_status, status: :ok
    else
      render json: health_status.merge(status: "degraded"), status: :service_unavailable
    end
  rescue => e
    render json: {
      status: "unhealthy",
      error: e.message,
      timestamp: Time.current.iso8601
    }, status: :service_unavailable
  end

  private

  def check_services
    services = {
      database: check_database,
      redis: check_redis,
      haystack: check_haystack,
      solid_queue: check_solid_queue
    }

    # Optional Rust services (don't fail health check if unavailable)
    if ENV['USE_RUST_SERVICES'] != 'false'
      services[:rust_embedding] = check_rust_embedding
      services[:rust_docproc] = check_rust_docproc
    end

    services
  end

  def check_database
    ActiveRecord::Base.connection.execute("SELECT 1")
    { status: "healthy", response_time_ms: measure_response_time { ActiveRecord::Base.connection.execute("SELECT 1") } }
  rescue => e
    { status: "unhealthy", error: e.message }
  end

  def check_redis
    Redis.current.ping
    { status: "healthy", response_time_ms: measure_response_time { Redis.current.ping } }
  rescue => e
    { status: "unhealthy", error: e.message }
  end

  def check_haystack
    haystack_url = ENV.fetch('HAYSTACK_SERVICE_URL', 'http://haystack:8000')
    response = Net::HTTP.get_response(URI("#{haystack_url}/health"))
    if response.code == "200"
      { status: "healthy", response_time_ms: measure_response_time { Net::HTTP.get_response(URI("#{haystack_url}/health")) } }
    else
      { status: "unhealthy", error: "HTTP #{response.code}" }
    end
  rescue => e
    { status: "unhealthy", error: e.message }
  end

  def check_solid_queue
    # Check if SolidQueue tables exist and are accessible
    SolidQueue::Job.count
    { status: "healthy", job_count: SolidQueue::Job.count }
  rescue => e
    { status: "unhealthy", error: e.message }
  end

  def check_rust_embedding
    rust_url = ENV.fetch('RUST_EMBEDDING_URL', 'http://localhost:8001')
    uri = URI("#{rust_url}/health")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 2
    http.read_timeout = 2
    response = http.get(uri.path)
    if response.code == "200"
      { status: "healthy", response_time_ms: measure_response_time { http.get(uri.path) } }
    else
      { status: "degraded", error: "HTTP #{response.code}" }
    end
  rescue => e
    { status: "unavailable", error: e.message, fallback: "python" }
  end

  def check_rust_docproc
    rust_url = ENV.fetch('RUST_DOCPROC_URL', 'http://localhost:8002')
    uri = URI("#{rust_url}/health")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 2
    http.read_timeout = 2
    response = http.get(uri.path)
    if response.code == "200"
      { status: "healthy", response_time_ms: measure_response_time { http.get(uri.path) } }
    else
      { status: "degraded", error: "HTTP #{response.code}" }
    end
  rescue => e
    { status: "unavailable", error: e.message, fallback: "python" }
  end

  def measure_response_time
    start_time = Time.current
    yield
    ((Time.current - start_time) * 1000).round(2)
  end

  def all_services_healthy?(services)
    # Core services must be healthy
    core_services = [:database, :redis, :haystack, :solid_queue]
    core_healthy = core_services.all? { |name| services[name]&.dig(:status) == "healthy" }

    # Rust services are optional (have Python fallback) - warn but don't fail
    rust_services = [:rust_embedding, :rust_docproc]
    rust_healthy = rust_services.all? { |name|
      status = services[name]&.dig(:status)
      status.nil? || status == "healthy" || status == "unavailable"
    }

    core_healthy && rust_healthy
  end
end
