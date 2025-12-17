# frozen_string_literal: true

require 'concurrent'

module Infrastructure
  # Production-grade rate limiter with multiple strategies
  # Supports token bucket, sliding window, and adaptive rate limiting
  class RateLimiter
    include Singleton

    # Default limits
    DEFAULTS = {
      api_requests_per_minute: 1000,
      search_requests_per_minute: 500,
      embedding_requests_per_minute: 100,
      document_uploads_per_hour: 100,
      max_concurrent_requests: 50
    }.freeze

    # Backpressure thresholds
    BACKPRESSURE = {
      warn_queue_depth: 100,
      critical_queue_depth: 500,
      shed_load_threshold: 0.9,  # Start shedding at 90% capacity
      recovery_threshold: 0.7    # Resume at 70% capacity
    }.freeze

    def initialize
      @lock = Mutex.new
      @buckets = {}
      @sliding_windows = {}
      @concurrent_requests = Concurrent::AtomicFixnum.new(0)
      @backpressure_mode = false
      @metrics = RateLimitMetrics.new

      # Organization-specific limits (can be customized per tenant)
      @org_limits = {}

      # Circuit breaker for downstream services
      @circuit_breakers = {}
    end

    # Check if request is allowed (token bucket algorithm)
    def allow?(key:, limit: nil, window: 60)
      limit ||= DEFAULTS[:api_requests_per_minute]

      @lock.synchronize do
        bucket = get_or_create_bucket(key, limit, window)

        if bucket[:tokens] >= 1
          bucket[:tokens] -= 1
          @metrics.record_allowed(key)
          true
        else
          @metrics.record_rejected(key)
          false
        end
      end
    end

    # Check with sliding window counter (more accurate for distributed)
    def allow_sliding?(key:, limit:, window: 60)
      now = Time.now.to_i

      @lock.synchronize do
        window_data = @sliding_windows[key] ||= { counts: {}, limit: limit, window: window }

        # Clean old windows
        cutoff = now - window
        window_data[:counts].delete_if { |ts, _| ts < cutoff }

        # Calculate current count
        current_count = window_data[:counts].values.sum

        if current_count < limit
          window_data[:counts][now] ||= 0
          window_data[:counts][now] += 1
          @metrics.record_allowed(key)
          true
        else
          @metrics.record_rejected(key)
          false
        end
      end
    end

    # Acquire a concurrent request slot
    def acquire_concurrent(timeout: 5)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      loop do
        current = @concurrent_requests.value

        if current < DEFAULTS[:max_concurrent_requests]
          if @concurrent_requests.compare_and_set(current, current + 1)
            @metrics.record_concurrent_acquired
            return ConcurrencyToken.new(self)
          end
        else
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          if elapsed >= timeout
            @metrics.record_concurrent_timeout
            return nil
          end

          # Exponential backoff
          sleep([0.01 * (2 ** (elapsed * 10)), 0.1].min)
        end
      end
    end

    # Release a concurrent request slot
    def release_concurrent
      @concurrent_requests.decrement
      @metrics.record_concurrent_released
    end

    # Check backpressure status
    def backpressure?
      @backpressure_mode
    end

    # Update backpressure based on system load
    def update_backpressure(queue_depth:, cpu_usage: nil, memory_usage: nil)
      @lock.synchronize do
        if queue_depth >= BACKPRESSURE[:critical_queue_depth] ||
           (cpu_usage && cpu_usage >= BACKPRESSURE[:shed_load_threshold]) ||
           (memory_usage && memory_usage >= BACKPRESSURE[:shed_load_threshold])

          unless @backpressure_mode
            @backpressure_mode = true
            Rails.logger.warn("[RateLimiter] Backpressure ENABLED - queue=#{queue_depth}")
            @metrics.record_backpressure_enabled
          end

        elsif @backpressure_mode &&
              queue_depth < BACKPRESSURE[:warn_queue_depth] &&
              (!cpu_usage || cpu_usage < BACKPRESSURE[:recovery_threshold]) &&
              (!memory_usage || memory_usage < BACKPRESSURE[:recovery_threshold])

          @backpressure_mode = false
          Rails.logger.info("[RateLimiter] Backpressure DISABLED - recovered")
          @metrics.record_backpressure_disabled
        end
      end
    end

    # Set organization-specific limits
    def set_org_limits(organization_id, limits)
      @lock.synchronize do
        @org_limits[organization_id] = DEFAULTS.merge(limits)
      end
    end

    # Get effective limits for an organization
    def limits_for(organization_id)
      @org_limits[organization_id] || DEFAULTS
    end

    # Circuit breaker for downstream services
    def circuit_open?(service)
      breaker = @circuit_breakers[service]
      return false unless breaker

      breaker[:open] && Time.now < breaker[:retry_after]
    end

    def record_service_success(service)
      @lock.synchronize do
        breaker = @circuit_breakers[service]
        return unless breaker

        breaker[:failures] = 0
        breaker[:open] = false
      end
    end

    def record_service_failure(service, threshold: 5, cooldown: 30)
      @lock.synchronize do
        breaker = @circuit_breakers[service] ||= { failures: 0, open: false }
        breaker[:failures] += 1

        if breaker[:failures] >= threshold
          breaker[:open] = true
          breaker[:retry_after] = Time.now + cooldown
          Rails.logger.warn("[RateLimiter] Circuit OPEN for #{service}")
        end
      end
    end

    # Get current metrics
    def metrics
      @metrics.summary.merge(
        concurrent_requests: @concurrent_requests.value,
        backpressure_mode: @backpressure_mode,
        circuit_breakers: @circuit_breakers.transform_values { |b| b[:open] }
      )
    end

    # Reset for testing
    def reset!
      @lock.synchronize do
        @buckets.clear
        @sliding_windows.clear
        @concurrent_requests.value = 0
        @backpressure_mode = false
        @circuit_breakers.clear
        @metrics = RateLimitMetrics.new
      end
    end

    private

    def get_or_create_bucket(key, limit, window)
      now = Time.now.to_f

      bucket = @buckets[key] ||= {
        tokens: limit.to_f,
        last_refill: now,
        rate: limit.to_f / window
      }

      # Refill tokens based on elapsed time
      elapsed = now - bucket[:last_refill]
      bucket[:tokens] = [bucket[:tokens] + (elapsed * bucket[:rate]), limit.to_f].min
      bucket[:last_refill] = now

      bucket
    end

    # Token for managing concurrent request lifecycle
    class ConcurrencyToken
      def initialize(limiter)
        @limiter = limiter
        @released = false
      end

      def release
        return if @released
        @released = true
        @limiter.release_concurrent
      end

      def with_release
        yield
      ensure
        release
      end
    end

    # Metrics collector
    class RateLimitMetrics
      def initialize
        @allowed = Concurrent::AtomicFixnum.new(0)
        @rejected = Concurrent::AtomicFixnum.new(0)
        @concurrent_acquired = Concurrent::AtomicFixnum.new(0)
        @concurrent_released = Concurrent::AtomicFixnum.new(0)
        @concurrent_timeouts = Concurrent::AtomicFixnum.new(0)
        @backpressure_events = Concurrent::AtomicFixnum.new(0)
        @key_stats = Concurrent::Hash.new { |h, k| h[k] = { allowed: 0, rejected: 0 } }
        @lock = Mutex.new
      end

      def record_allowed(key)
        @allowed.increment
        @lock.synchronize { @key_stats[key][:allowed] += 1 }
      end

      def record_rejected(key)
        @rejected.increment
        @lock.synchronize { @key_stats[key][:rejected] += 1 }
      end

      def record_concurrent_acquired
        @concurrent_acquired.increment
      end

      def record_concurrent_released
        @concurrent_released.increment
      end

      def record_concurrent_timeout
        @concurrent_timeouts.increment
      end

      def record_backpressure_enabled
        @backpressure_events.increment
      end

      def record_backpressure_disabled
        # Just for tracking state changes
      end

      def summary
        total = @allowed.value + @rejected.value
        rejection_rate = total > 0 ? (@rejected.value.to_f / total).round(4) : 0

        {
          total_requests: total,
          allowed: @allowed.value,
          rejected: @rejected.value,
          rejection_rate: rejection_rate,
          concurrent_acquired: @concurrent_acquired.value,
          concurrent_timeouts: @concurrent_timeouts.value,
          backpressure_events: @backpressure_events.value,
          top_rejected_keys: top_rejected_keys(5)
        }
      end

      private

      def top_rejected_keys(n)
        @lock.synchronize do
          @key_stats.sort_by { |_, v| -v[:rejected] }
                    .take(n)
                    .map { |k, v| { key: k, rejected: v[:rejected] } }
        end
      end
    end
  end

  # Rack middleware for HTTP rate limiting
  class RateLimitMiddleware
    def initialize(app)
      @app = app
      @limiter = RateLimiter.instance
    end

    def call(env)
      request = Rack::Request.new(env)

      # Extract client identifier
      client_key = extract_client_key(request)

      # Check backpressure first
      if @limiter.backpressure?
        return backpressure_response unless priority_request?(request)
      end

      # Check rate limit
      unless @limiter.allow?(key: client_key, limit: rate_limit_for(request))
        return rate_limited_response(client_key)
      end

      # Acquire concurrent slot
      token = @limiter.acquire_concurrent(timeout: 2)
      return concurrent_limit_response unless token

      begin
        @app.call(env)
      ensure
        token.release
      end
    end

    private

    def extract_client_key(request)
      # Priority: API key > User ID > Organization > IP
      request.env['HTTP_X_API_KEY'] ||
        request.env['warden']&.user&.id ||
        request.params['organization_id'] ||
        request.ip
    end

    def rate_limit_for(request)
      case request.path
      when %r{^/api/v\d+/search}
        500  # Search endpoint
      when %r{^/api/v\d+/embed}
        100  # Embedding endpoint
      when %r{^/api/v\d+/documents}
        200  # Document operations
      else
        1000  # Default
      end
    end

    def priority_request?(request)
      # Health checks and admin endpoints bypass backpressure
      request.path.start_with?('/health', '/admin', '/metrics')
    end

    def rate_limited_response(key)
      [
        429,
        {
          'Content-Type' => 'application/json',
          'Retry-After' => '60',
          'X-RateLimit-Limit' => '1000',
          'X-RateLimit-Remaining' => '0'
        },
        [JSON.generate({ error: 'rate_limited', message: 'Too many requests', key: key })]
      ]
    end

    def backpressure_response
      [
        503,
        {
          'Content-Type' => 'application/json',
          'Retry-After' => '30'
        },
        [JSON.generate({ error: 'service_overloaded', message: 'System under heavy load, please retry' })]
      ]
    end

    def concurrent_limit_response
      [
        503,
        {
          'Content-Type' => 'application/json',
          'Retry-After' => '5'
        },
        [JSON.generate({ error: 'concurrent_limit', message: 'Too many concurrent requests' })]
      ]
    end
  end
end
