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
Ahoy.job_queue = :solid_queue

# Mask IP addresses for privacy
Ahoy.mask_ips = true

# Set cookie domain
Ahoy.cookie_domain = :all

# Customize which events are tracked
Ahoy.track_visits_immediately = true

# Don't track bots
Ahoy.exclude_bots = true

# Avoid tracking when running tests
Ahoy.server_side_visits = Rails.env.production? || Rails.env.development?
