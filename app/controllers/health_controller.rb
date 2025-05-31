# Health check endpoint for container orchestration and monitoring
class HealthController < ApplicationController
  # Skip authentication for health checks
  skip_before_action :authenticate_user!, if: :devise_controller?
  
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
    {
      database: check_database,
      redis: check_redis,
      haystack: check_haystack,
      solid_queue: check_solid_queue
    }
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

  def measure_response_time
    start_time = Time.current
    yield
    ((Time.current - start_time) * 1000).round(2)
  end

  def all_services_healthy?(services)
    services.values.all? { |service| service[:status] == "healthy" }
  end
end
