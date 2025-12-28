# frozen_string_literal: true

# RateLimiter provides simple rate limiting for external API calls
#
# Usage:
#   limiter = RateLimiter.new(
#     key: 'openai_embeddings',
#     max_requests: 3000,
#     period: 60  # 3000 requests per 60 seconds
#   )
#
#   limiter.throttle do
#     # API call here
#   end
#
# Supports Redis for distributed rate limiting or falls back to in-memory.
class RateLimiter
  class RateLimitExceeded < StandardError; end

  # Default limits per provider (requests per minute)
  PROVIDER_LIMITS = {
    'openai' => { max_requests: 3000, period: 60 },
    'anthropic' => { max_requests: 60, period: 60 },
    'cohere' => { max_requests: 100, period: 60 },
    'local' => { max_requests: 1000, period: 60 }, # self-hosted models
    'default' => { max_requests: 100, period: 60 }
  }.freeze

  attr_reader :key, :max_requests, :period

  def initialize(key:, max_requests: nil, period: nil, provider: nil)
    @key = "rate_limit:#{key}"

    if provider && PROVIDER_LIMITS[provider]
      limits = PROVIDER_LIMITS[provider]
      @max_requests = max_requests || limits[:max_requests]
      @period = period || limits[:period]
    else
      limits = PROVIDER_LIMITS['default']
      @max_requests = max_requests || limits[:max_requests]
      @period = period || limits[:period]
    end

    @redis = redis_available? ? Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379') : nil
  end

  # Execute block with rate limiting
  # Raises RateLimitExceeded if limit is reached
  def throttle(&block)
    wait_if_needed
    increment_counter
    yield
  end

  # Execute with automatic retry on rate limit
  def throttle_with_retry(max_retries: 3, &block)
    retries = 0
    begin
      throttle(&block)
    rescue RateLimitExceeded
      retries += 1
      if retries <= max_retries
        sleep_time = calculate_backoff(retries)
        Rails.logger.warn "[RateLimiter] Rate limit hit for #{key}, sleeping #{sleep_time}s (retry #{retries}/#{max_retries})"
        sleep(sleep_time)
        retry
      else
        raise
      end
    end
  end

  # Check if rate limit would be exceeded
  def would_exceed?
    current_count >= max_requests
  end

  # Get current request count
  def current_count
    if @redis
      @redis.get(key).to_i
    else
      @memory_store ||= {}
      entry = @memory_store[key]
      return 0 unless entry && entry[:expires_at] > Time.current
      entry[:count]
    end
  end

  # Time until rate limit resets
  def time_until_reset
    if @redis
      ttl = @redis.ttl(key)
      ttl.positive? ? ttl : 0
    else
      @memory_store ||= {}
      entry = @memory_store[key]
      return 0 unless entry
      remaining = entry[:expires_at] - Time.current
      remaining.positive? ? remaining : 0
    end
  end

  # Get current usage as percentage
  def usage_percentage
    (current_count.to_f / max_requests * 100).round(1)
  end

  # Reset the rate limit (useful for testing)
  def reset!
    if @redis
      @redis.del(key)
    else
      @memory_store&.delete(key)
    end
  end

  private

  def wait_if_needed
    return unless would_exceed?

    wait_time = time_until_reset
    if wait_time > 0
      Rails.logger.info "[RateLimiter] Waiting #{wait_time}s for rate limit reset on #{key}"
      sleep(wait_time + 0.1)
    end
  end

  def increment_counter
    if @redis
      redis_increment
    else
      memory_increment
    end
  end

  def redis_increment
    current = @redis.incr(key)
    @redis.expire(key, period) if current == 1
    raise RateLimitExceeded, "Rate limit exceeded for #{key}" if current > max_requests
  end

  def memory_increment
    @memory_store ||= {}
    entry = @memory_store[key]

    if entry.nil? || entry[:expires_at] <= Time.current
      @memory_store[key] = { count: 1, expires_at: Time.current + period }
    else
      entry[:count] += 1
      raise RateLimitExceeded, "Rate limit exceeded for #{key}" if entry[:count] > max_requests
    end
  end

  def calculate_backoff(retry_count)
    # Exponential backoff: 1s, 2s, 4s, 8s...
    base_delay = 1
    max_delay = 30
    delay = base_delay * (2 ** (retry_count - 1))
    [delay, max_delay].min
  end

  def redis_available?
    Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379').ping == 'PONG'
  rescue
    false
  end

  class << self
    # Convenience method for embedding generation
    def for_embeddings(provider = 'openai')
      new(key: "embeddings:#{provider}", provider: provider)
    end

    # Convenience method for document extraction
    def for_extraction
      new(key: 'document_extraction', max_requests: 100, period: 60)
    end

    # Get limiter for specific organization (for per-org limits)
    def for_organization(org_id, operation)
      new(key: "org:#{org_id}:#{operation}", max_requests: 500, period: 60)
    end
  end
end
