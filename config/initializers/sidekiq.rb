# Enterprise-grade Sidekiq configuration for Docker environment
# Universal configuration - platform detection no longer needed

require 'sidekiq'

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
  
  # Sidekiq-specific logging
  config.logger.level = Logger::INFO
  config.logger.info "🚀 Sidekiq server configured with background processing"
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
  config.logger.info "🚀 Sidekiq client configured"
end
