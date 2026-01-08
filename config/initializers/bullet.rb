# frozen_string_literal: true

# Bullet gem configuration for N+1 query detection
# Only enabled in development environment
if defined?(Bullet) && Rails.env.development?
  Rails.application.configure do
    config.after_initialize do
      Bullet.enable = true
      Bullet.alert = false # Don't use JavaScript alerts
      Bullet.bullet_logger = true # Log to log/bullet.log
      Bullet.console = true # Log to browser console
      Bullet.rails_logger = true # Log to Rails log
      Bullet.add_footer = true # Add footer to HTML pages showing N+1 queries

      # Raise an error in test environment (optional)
      # Bullet.raise = true if Rails.env.test?

      # Whitelist associations that are intentionally not eager loaded
      # Bullet.add_safelist type: :unused_eager_loading, class_name: "Model", association: :association
    end
  end
end
