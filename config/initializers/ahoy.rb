class Ahoy::Store < Ahoy::DatabaseStore
  # Associate visits with users
  def user
    controller.current_user if controller.respond_to?(:current_user)
  end
end

# Enable JavaScript tracking
Ahoy.api = true

# Disable geocoding (we don't need it for our basic analytics)
Ahoy.geocode = false

# Track visits in background to maintain performance
# Use the same job queue adapter as Rails is configured to use
Ahoy.job_queue = Rails.application.config.active_job.queue_adapter

# Mask IP addresses for privacy
Ahoy.mask_ips = true

# Set cookie domain
Ahoy.cookie_domain = :all

# Track visits immediately (removed deprecated option)
# Ahoy.track_visits_immediately = true  # This option is no longer available in newer versions

# Don't track bots (removed deprecated option)
# Ahoy.exclude_bots = true  # This option is no longer available in newer versions

# Avoid tracking when running tests (updated for current Ahoy version)
# Ahoy.server_side_visits = Rails.env.production? || Rails.env.development?
