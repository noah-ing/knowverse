# Enterprise Security Configuration for Knowverse
# Hardens Rails application for enterprise deployment

Rails.application.configure do
  # Force SSL in production and staging
  if Rails.env.production? || Rails.env.staging?
    config.force_ssl = true
    config.ssl_options = {
      redirect: { status: 301, port: 443 },
      secure_cookies: true,
      hsts: {
        expires: 1.year,
        subdomains: true,
        preload: true
      }
    }
  end
end

# Security Headers Middleware
class SecurityHeadersMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)
    
    # Content Security Policy
    headers['Content-Security-Policy'] = [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net https://ga.jspm.io",
      "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
      "font-src 'self' https://fonts.gstatic.com",
      "img-src 'self' data: https:",
      "connect-src 'self' ws: wss:",
      "frame-ancestors 'none'",
      "base-uri 'self'",
      "form-action 'self'"
    ].join('; ')
    
    # Security headers
    headers['X-Frame-Options'] = 'DENY'
    headers['X-Content-Type-Options'] = 'nosniff'
    headers['X-XSS-Protection'] = '1; mode=block'
    headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    headers['Permissions-Policy'] = 'camera=(), microphone=(), geolocation=()'
    
    # HTTPS Strict Transport Security
    if Rails.env.production?
      headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains; preload'
    end
    
    # Remove server identification
    headers.delete('Server')
    headers.delete('X-Powered-By')
    
    [status, headers, response]
  end
end

# Apply security headers middleware
Rails.application.config.middleware.insert_before 0, SecurityHeadersMiddleware

# Configure secure cookies
Rails.application.config.session_store :cookie_store,
  key: '_knowverse_session',
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax,
  expire_after: 24.hours

# Rate limiting configuration (if Rack::Attack is available)
if defined?(Rack::Attack)
  Rails.application.configure do
    config.middleware.use Rack::Attack
  end

  # Enable logging
  ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |name, start, finish, request_id, req|
    Rails.logger.warn "Rate limit exceeded for IP: #{req.ip}"
  end

  # Rate limiting rules
  Rack::Attack.throttle('general', limit: 300, period: 1.minute) do |req|
    req.ip unless req.path.start_with?('/assets')
  end

  Rack::Attack.throttle('search', limit: 60, period: 1.minute) do |req|
    req.ip if req.path.match?(/\/search/)
  end

  Rack::Attack.throttle('api', limit: 100, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/api')
  end

  # Block suspicious requests
  Rack::Attack.blocklist('fail2ban pentesters') do |req|
    # Block known bad IPs
    Rack::Attack::Fail2Ban.filter("pentesters-#{req.ip}", maxretry: 5, findtime: 10.minutes, bantime: 1.hour) do
      req.path.match?(/\.(php|asp|aspx|jsp|cgi)$/) ||
      req.path.include?('wp-admin') ||
      req.path.include?('phpmyadmin') ||
      req.user_agent&.include?('bot')
    end
  end
end

# Enterprise audit logging
class SecurityAuditLogger
  def self.log_security_event(event_type, details = {})
    Rails.logger.info({
      event: 'security_audit',
      type: event_type,
      timestamp: Time.current.iso8601,
      details: details,
      environment: Rails.env
    }.to_json)
  end

  def self.log_authentication_attempt(user_id, success, ip_address)
    log_security_event('authentication_attempt', {
      user_id: user_id,
      success: success,
      ip_address: ip_address,
      user_agent: Thread.current[:request]&.user_agent
    })
  end

  def self.log_privilege_escalation(user_id, action, resource)
    log_security_event('privilege_escalation', {
      user_id: user_id,
      action: action,
      resource: resource,
      ip_address: Thread.current[:request]&.remote_ip
    })
  end

  def self.log_data_access(user_id, resource_type, resource_id, action)
    log_security_event('data_access', {
      user_id: user_id,
      resource_type: resource_type,
      resource_id: resource_id,
      action: action,
      ip_address: Thread.current[:request]&.remote_ip
    })
  end
end

# Parameter filtering for logs (prevent sensitive data exposure)
Rails.application.configure do
  config.filter_parameters += [
    :password, :password_confirmation, :secret, :token, :key, :api_key,
    :access_token, :refresh_token, :authentication_token, :remember_token,
    :credit_card, :ssn, :social_security_number, :date_of_birth
  ]
end

Rails.logger.info "🔒 Enterprise security configuration loaded successfully"
