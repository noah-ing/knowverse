# lib/database/connection_manager.rb
#
# Enterprise PostgreSQL Connection Manager
# Provides improved connection handling, protocol detection, and circuit breaker patterns
# for KnowVerse's PostgreSQL connectivity

require 'singleton'
require 'timeout'

module Database
  # ConnectionMetrics tracks connection attempts, failures, and performance
  class ConnectionMetrics
    attr_reader :total_attempts, :successful_connections, :failed_connections, 
                :connection_times, :failures_by_type, :recent_failures, :last_error

    def initialize
      @total_attempts = 0
      @successful_connections = 0
      @failed_connections = 0
      @connection_times = []
      @failures_by_type = Hash.new(0)
      @recent_failures = []
      @last_error = nil
      @mutex = Mutex.new
    end

    def record_attempt
      @mutex.synchronize { @total_attempts += 1 }
    end
    
    def record_success(elapsed_time)
      @mutex.synchronize do
        @successful_connections += 1
        @connection_times << elapsed_time
        @connection_times.shift if @connection_times.length > 100 # Keep last 100 times
      end
    end
    
    def record_failure(error)
      @mutex.synchronize do
        @failed_connections += 1
        error_type = error.class.name
        @failures_by_type[error_type] += 1
        @recent_failures << { time: Time.now, type: error_type, message: error.message }
        @recent_failures.shift if @recent_failures.length > 10 # Keep last 10 failures
        @last_error = error
      end
    end
    
    def success_rate
      return 100.0 if @total_attempts == 0
      (@successful_connections.to_f / @total_attempts) * 100
    end
    
    def average_connect_time
      return 0 if @connection_times.empty?
      @connection_times.sum / @connection_times.length
    end
    
    def reset_recent_stats
      @mutex.synchronize do
        @recent_failures = []
        @connection_times = []
      end
    end
    
    def to_h
      {
        total_attempts: @total_attempts,
        successful_connections: @successful_connections,
        failed_connections: @failed_connections,
        success_rate: success_rate,
        average_connect_time: average_connect_time,
        failures_by_type: @failures_by_type,
        recent_failures: @recent_failures
      }
    end
  end
  
  # CircuitBreaker provides protection against cascading failures
  class CircuitBreaker
    attr_reader :state, :failure_count, :last_failure_time, :reset_timeout
    
    STATES = [:closed, :open, :half_open].freeze
    
    def initialize(failure_threshold: 5, reset_timeout: 30)
      @failure_threshold = failure_threshold
      @reset_timeout = reset_timeout
      @failure_count = 0
      @state = :closed
      @last_failure_time = nil
      @mutex = Mutex.new
    end
    
    def allow_request?
      @mutex.synchronize do
        case @state
        when :closed
          true
        when :half_open
          true
        when :open
          if Time.now - @last_failure_time >= @reset_timeout
            @state = :half_open
            log("Circuit breaker state changed to half-open")
            true
          else
            false
          end
        end
      end
    end
    
    def mark_success
      @mutex.synchronize do
        if @state == :half_open
          @state = :closed
          @failure_count = 0
          log("Circuit breaker state changed to closed")
        end
      end
    end
    
    def mark_failure
      @mutex.synchronize do
        @failure_count += 1
        @last_failure_time = Time.now
        
        if @state == :closed && @failure_count >= @failure_threshold
          @state = :open
          log("Circuit breaker state changed to open. Failures: #{@failure_count}")
        elsif @state == :half_open
          @state = :open
          log("Circuit breaker state changed to open after half-open failure")
        end
      end
    end
    
    def reset
      @mutex.synchronize do
        @failure_count = 0
        @state = :closed
        log("Circuit breaker reset to closed state")
      end
    end
    
    private
    
    def log(message)
      if defined?(Rails) && Rails.logger
        Rails.logger.info("CircuitBreaker: #{message}")
      else
        puts "CircuitBreaker: #{message}"
      end
    end
  end
  
  # ConnectionManager provides enterprise-grade PostgreSQL connection handling
  class ConnectionManager
    include Singleton
    
    attr_reader :metrics, :circuit_breaker
    
    def initialize
      @config = load_config
      @metrics = ConnectionMetrics.new
      @circuit_breaker = CircuitBreaker.new(
        failure_threshold: @config[:failure_threshold],
        reset_timeout: @config[:reset_timeout]
      )
      @mutex = Mutex.new
      
      log("Initialized KnowVerse Enterprise Connection Manager")
      log("Configuration: #{@config.inspect}")
      
      # Override PG connection methods if available
      patch_pg_connection if defined?(PG::Connection)
    end
    
    # Get a connection with protocol validation and circuit breaker protection
    def connection(custom_config = {})
      raise ConnectionError, "Circuit breaker open - too many recent failures" unless @circuit_breaker.allow_request?
      
      config = @config.merge(custom_config)
      @metrics.record_attempt
      
      start_time = Time.now
      connection = nil
      
      begin
        # Attempt connection with timeout
        Timeout.timeout(config[:connect_timeout]) do
          connection = create_connection(config)
        end
        
        # Validate connection by running a simple query
        validate_connection(connection)
        
        # Record success
        elapsed = Time.now - start_time
        @metrics.record_success(elapsed)
        @circuit_breaker.mark_success
        
        log("Successfully established validated connection in #{elapsed.round(3)}s")
        connection
      rescue => e
        @metrics.record_failure(e)
        @circuit_breaker.mark_failure
        
        log_error("Connection error", e)
        raise ConnectionError, "Failed to establish database connection: #{e.message}"
      end
    end
    
    # Safely execute a block with a connection, ensuring it's returned to the pool
    def with_connection(custom_config = {})
      conn = connection(custom_config)
      yield conn
    rescue => e
      log_error("Error during connection use", e)
      raise
    ensure
      conn&.close rescue nil
    end
    
    # Reset the circuit breaker (for administrative use)
    def reset_circuit_breaker
      @circuit_breaker.reset
      @metrics.reset_recent_stats
      log("Connection manager reset requested")
    end
    
    # Get connection status for monitoring
    def status
      {
        circuit_breaker: {
          state: @circuit_breaker.state,
          failure_count: @circuit_breaker.failure_count,
          last_failure_time: @circuit_breaker.last_failure_time
        },
        metrics: @metrics.to_h,
        configuration: @config.reject { |k, v| k.to_s.include?("password") }
      }
    end
    
    private
    
    def load_config
      # Default configuration
      config = {
        host: '127.0.0.1',  # Always use IPv4
        port: 5432,
        dbname: 'knowverse_development',
        user: 'postgres',
        password: nil,
        connect_timeout: 5,
        connection_validation_timeout: 2,
        max_attempts: 3,
        retry_delay: 1.0,
        failure_threshold: 5,
        reset_timeout: 30
      }
      
      # Load from Rails config if available
      if defined?(Rails) && Rails.application
        begin
          # Rails 7 uses symbol keys
          rails_config = Rails.application.config.database_configuration[Rails.env]
          
          config[:host] = rails_config[:host] || rails_config['host'] || config[:host]
          config[:port] = rails_config[:port] || rails_config['port'] || config[:port]
          config[:dbname] = rails_config[:database] || rails_config['database'] || config[:dbname]
          config[:user] = rails_config[:username] || rails_config['username'] || config[:user]
          config[:password] = rails_config[:password] || rails_config['password'] || config[:password]
        rescue => e
          log_error("Error loading Rails database configuration", e)
        end
      end
      
      # Environment variables override all
      config[:host] = ENV['PGHOST'] if ENV['PGHOST']
      config[:port] = ENV['PGPORT'].to_i if ENV['PGPORT']
      config[:dbname] = ENV['PGDATABASE'] if ENV['PGDATABASE']
      config[:user] = ENV['PGUSER'] if ENV['PGUSER']
      config[:password] = ENV['PGPASSWORD'] if ENV['PGPASSWORD']
      
      # Parse DATABASE_URL if available
      if ENV['DATABASE_URL']
        begin
          require 'uri'
          uri = URI.parse(ENV['DATABASE_URL'])
          config[:host] = uri.host if uri.host
          config[:port] = uri.port if uri.port
          config[:user] = uri.user if uri.user
          config[:password] = uri.password if uri.password
          config[:dbname] = uri.path.sub(/^\//, '') if uri.path
        rescue => e
          log_error("Error parsing DATABASE_URL", e)
        end
      end
      
      # Force IPv4 by ensuring host is not 'localhost'
      config[:host] = '127.0.0.1' if config[:host] == 'localhost'
      
      config
    end
    
    def create_connection(config)
      # Use proper IPv4 addressing
      if config[:host] == 'localhost'
        config = config.merge(host: '127.0.0.1')
        log("Forcing IPv4 by changing localhost to 127.0.0.1")
      end
      
      # Add retry logic
      max_attempts = config[:max_attempts]
      attempt = 0
      retry_wait = config[:retry_delay]
      last_error = nil
      
      begin
        attempt += 1
        log("Connecting to PostgreSQL at #{config[:host]}:#{config[:port]} (attempt #{attempt}/#{max_attempts})")
        
        # Create the connection
        PG.connect(
          host: config[:host],
          port: config[:port],
          dbname: config[:dbname],
          user: config[:user],
          password: config[:password],
          connect_timeout: config[:connect_timeout]
        )
      rescue => e
        last_error = e
        if attempt < max_attempts
          sleep_time = retry_wait * (2 ** (attempt - 1))
          log("Connection failed: #{e.message}, retrying in #{sleep_time}s")
          sleep(sleep_time)
          retry
        else
          log("Failed after #{max_attempts} attempts: #{e.message}")
          raise
        end
      end
    end
    
    def validate_connection(connection)
      # Validate the connection by running a simple query
      # This ensures the connection wasn't immediately terminated after establishment
      Timeout.timeout(@config[:connection_validation_timeout]) do
        result = connection.exec("SELECT 1 AS connection_test")
        if result[0]["connection_test"] != "1"
          raise "Connection validation failed: unexpected result"
        end
      end
      log("Connection validated successfully")
    rescue => e
      log_error("Connection validation failed", e)
      raise
    end
    
    def patch_pg_connection
      # Only patch if not already patched
      return if PG::Connection.singleton_methods.include?(:original_connect)
      
      log("Patching PG::Connection to use enterprise connection management")
      
      # Store original connect method
      PG::Connection.singleton_class.alias_method(:original_connect, :connect)
      
      # Replace with our managed version
      PG::Connection.define_singleton_method(:connect) do |*args|
        ConnectionManager.instance.with_connection do |conn|
          conn
        end
      end
      
      log("Successfully patched PG::Connection")
    rescue => e
      log_error("Failed to patch PG::Connection", e)
    end
    
    def log(message)
      if defined?(Rails) && Rails.logger
        Rails.logger.info("PG-ConnectionManager: #{message}")
      else
        puts "PG-ConnectionManager: #{message}"
      end
    end
    
    def log_error(message, error)
      if defined?(Rails) && Rails.logger
        Rails.logger.error("PG-ConnectionManager: #{message}: #{error.message}")
        Rails.logger.error(error.backtrace.join("\n")) if error.backtrace
      else
        puts "PG-ConnectionManager ERROR: #{message}: #{error.message}"
        puts error.backtrace.join("\n") if error.backtrace
      end
    end
  end
  
  # Custom error class for connection issues
  class ConnectionError < StandardError; end
end

# Initialize the connection manager if Rails is available
if defined?(Rails) && Rails.application
  Rails.application.config.to_prepare do
    Database::ConnectionManager.instance
  end
end
