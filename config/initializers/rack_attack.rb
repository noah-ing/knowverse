# Rack::Attack Rate Limiting Configuration for Knowverse
# Protects against brute force attacks, API abuse, and MCP tool exploitation

class Rack::Attack
  # Use Rails cache store for throttle tracking
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # === THROTTLE CONFIGURATION ===

  # General API rate limiting: 100 requests per minute
  throttle('api/general', limit: 100, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/api')
  end

  # Authentication endpoints: 20 requests per minute (stricter for security)
  throttle('auth/login', limit: 20, period: 1.minute) do |req|
    req.ip if req.path == '/users/sign_in' && req.post?
  end

  throttle('auth/magic_link', limit: 20, period: 1.minute) do |req|
    req.ip if req.path.include?('/magic_link') && req.post?
  end

  throttle('auth/password_reset', limit: 20, period: 1.minute) do |req|
    req.ip if req.path == '/users/password' && req.post?
  end

  # MCP Tool Execution endpoints: stricter throttling to prevent abuse
  throttle('mcp/tool_execution', limit: 30, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/mcp') && req.post?
  end

  throttle('mcp/tool_call', limit: 30, period: 1.minute) do |req|
    req.ip if req.path.match?(/\/tools\/\w+\/call/) && req.post?
  end

  # RAG and Vector endpoints: moderate throttling for compute-intensive operations
  throttle('rag/query', limit: 50, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/rag') && req.post?
  end

  throttle('vectors/search', limit: 50, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/vectors') && req.post?
  end

  # Search endpoints
  throttle('search', limit: 60, period: 1.minute) do |req|
    req.ip if req.path.match?(/\/search/)
  end

  # General request limiting (excludes assets)
  throttle('general', limit: 300, period: 1.minute) do |req|
    req.ip unless req.path.start_with?('/assets')
  end

  # === BLOCKLIST CONFIGURATION ===

  # Block repeated authentication failures (Fail2Ban pattern)
  blocklist('fail2ban/auth') do |req|
    # Track failed auth attempts by IP
    Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 5, findtime: 5.minutes, bantime: 1.hour) do
      # Track login failures (will be triggered by tracking below)
      req.path == '/users/sign_in' && req.post? && req.env['warden'].try(:authenticated?) == false
    end
  end

  # Block known malicious patterns (pentest probes, vulnerability scanners)
  blocklist('fail2ban/pentesters') do |req|
    Rack::Attack::Fail2Ban.filter("pentesters-#{req.ip}", maxretry: 3, findtime: 10.minutes, bantime: 1.hour) do
      # Common vulnerability probes
      req.path.match?(/\.(php|asp|aspx|jsp|cgi)$/) ||
      req.path.include?('wp-admin') ||
      req.path.include?('wp-login') ||
      req.path.include?('phpmyadmin') ||
      req.path.include?('actuator') ||
      req.path.include?('.env') ||
      req.path.include?('.git') ||
      req.path.include?('xmlrpc')
    end
  end

  # === RESPONSE CONFIGURATION ===

  # Custom response for throttled requests: 429 with Retry-After header
  self.throttled_responder = lambda do |req|
    match_data = req.env['rack.attack.match_data']
    now = Time.now.to_i
    period = match_data[:period]
    retry_after = period - (now % period)

    headers = {
      'Content-Type' => 'application/json',
      'Retry-After' => retry_after.to_s,
      'X-RateLimit-Limit' => match_data[:limit].to_s,
      'X-RateLimit-Remaining' => '0',
      'X-RateLimit-Reset' => (now + retry_after).to_s
    }

    body = {
      error: 'Rate limit exceeded',
      message: 'Too many requests. Please wait before retrying.',
      retry_after: retry_after,
      limit: match_data[:limit],
      period: match_data[:period]
    }.to_json

    [429, headers, [body]]
  end

  # Custom response for blocked requests
  self.blocklisted_responder = lambda do |req|
    headers = {
      'Content-Type' => 'application/json'
    }

    body = {
      error: 'Blocked',
      message: 'Your IP has been temporarily blocked due to suspicious activity.'
    }.to_json

    [403, headers, [body]]
  end
end

# === LOGGING ===

# Log throttle events for monitoring
ActiveSupport::Notifications.subscribe('throttle.rack_attack') do |name, start, finish, request_id, payload|
  req = payload[:request]
  Rails.logger.warn(
    "[Rack::Attack] Throttled: " \
    "IP=#{req.ip} " \
    "Path=#{req.path} " \
    "Rule=#{req.env['rack.attack.matched']}"
  )
end

# Log blocklist events
ActiveSupport::Notifications.subscribe('blocklist.rack_attack') do |name, start, finish, request_id, payload|
  req = payload[:request]
  Rails.logger.warn(
    "[Rack::Attack] Blocked: " \
    "IP=#{req.ip} " \
    "Path=#{req.path} " \
    "Rule=#{req.env['rack.attack.matched']}"
  )
end

Rails.logger.info "[Rack::Attack] Rate limiting configuration loaded"
