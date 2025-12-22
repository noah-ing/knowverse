#!/usr/bin/env ruby
# Enterprise PostgreSQL Connection Test Script
# Tests the enterprise database connection manager and diagnostics

require 'rubygems'
require 'pg'
require 'uri'
require 'timeout'

# Try to load Rails environment if available
rails_env_loaded = false
begin
  require File.expand_path('../../config/environment', __FILE__)
  rails_env_loaded = true
  puts "✅ Rails environment loaded successfully"
rescue => e
  puts "ℹ️ Rails environment not loaded: #{e.message}"
  puts "   Will run in standalone mode"
end

# Format output with colored status indicators
def format_status(status, message)
  case status
  when :success
    puts "  ✅ #{message}"
  when :warning
    puts "  ⚠️ #{message}"
  when :error
    puts "  ❌ #{message}"
  when :info
    puts "  ℹ️ #{message}"
  else
    puts "  #{message}"
  end
end

puts "\n══════════════════════════════════════════════════════"
puts "KnowVerse Enterprise PostgreSQL Connection Test"
puts "══════════════════════════════════════════════════════\n\n"

puts "SYSTEM INFORMATION"
puts "═════════════════\n"
os = RbConfig::CONFIG['host_os']
format_status(:info, "Operating System: #{os}")
format_status(:info, "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})")
format_status(:info, "PG Gem Version: #{PG::VERSION}")
format_status(:info, "Rails Loaded: #{rails_env_loaded}")
puts

puts "ENVIRONMENT VARIABLES"
puts "═══════════════════\n"
if ENV['DATABASE_URL']
  puts "DATABASE_URL: #{ENV['DATABASE_URL'].gsub(/:[^:]*@/, ':***@')}"
  
  begin
    uri = URI.parse(ENV['DATABASE_URL'])
    format_status(:info, "  Host: #{uri.host}")
    format_status(:info, "  Port: #{uri.port}")
    format_status(:info, "  User: #{uri.user}")
    format_status(:info, "  Password: #{uri.password ? '[FILTERED]' : 'none'}")
    format_status(:info, "  Path: #{uri.path}")
    format_status(:info, "  Query: #{uri.query}")
    
    if uri.host == 'localhost'
      format_status(:warning, "  Using 'localhost' which may trigger IPv6 resolution (::1)")
    elsif uri.host == '127.0.0.1'
      format_status(:success, "  Using explicit IPv4 address (127.0.0.1)")
    elsif uri.host == '::1'
      format_status(:warning, "  Using explicit IPv6 address (::1)")
    end
  rescue => e
    format_status(:error, "  Error parsing DATABASE_URL: #{e.message}")
  end
else
  format_status(:warning, "DATABASE_URL not set")
end

format_status(:info, "PGUSER: #{ENV['PGUSER'] || 'not set'}")
format_status(:info, "PGPASSWORD: #{ENV['PGPASSWORD'] ? '[FILTERED]' : 'not set'}")
format_status(:info, "PGHOST: #{ENV['PGHOST'] || 'not set'}")
format_status(:info, "PGPORT: #{ENV['PGPORT'] || 'not set'}")
puts

puts "CONNECTION ADAPTERS"
puts "══════════════════\n"

# Check if our enterprise adapter is loaded
if defined?(Database::ConnectionManager)
  format_status(:success, "Enterprise database adapter loaded")
  connection_manager = Database::ConnectionManager.instance
  
  # Display the connection manager configuration
  config = connection_manager.instance_variable_get(:@config)
  if config
    format_status(:info, "Configuration:")
    config.each do |key, value|
      if key.to_s.include?('password')
        format_status(:info, "  #{key}: [FILTERED]")
      else
        format_status(:info, "  #{key}: #{value}")
      end
    end
  else
    format_status(:warning, "Configuration not available")
  end
else
  format_status(:warning, "Enterprise database adapter not loaded")
end

# Check if the legacy IPv4 adapter is still active
if defined?(PG::Connection) && PG::Connection.singleton_methods.include?(:original_connect)
  format_status(:success, "PG::Connection patched for IPv4 compatibility")
else
  format_status(:warning, "PG::Connection not patched")
end

if defined?(ActiveRecord) && defined?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
  if ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.instance_methods.include?(:connection_status) ||
     ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.private_instance_methods.include?(:connection_status)
    format_status(:success, "ActiveRecord PostgreSQLAdapter patched with connection_status")
  else
    format_status(:warning, "ActiveRecord PostgreSQLAdapter doesn't have connection_status method")
  end
  
  if ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.ancestors.any? { |a| a.name&.include?("PostgreSQLAdapterPatch") }
    format_status(:success, "ActiveRecord PostgreSQLAdapter patched with Enterprise adapter")
  else
    format_status(:warning, "ActiveRecord PostgreSQLAdapter not patched with Enterprise adapter")
  end
else
  format_status(:warning, "ActiveRecord PostgreSQLAdapter not available")
end
puts

puts "CONNECTION TESTS"
puts "═══════════════\n"

# Test direct connection with PG gem
puts "1. Testing direct PG connection with IPv4 (127.0.0.1)"
begin
  # Force IPv4 by using explicit 127.0.0.1
  start_time = Time.now
  conn = PG.connect(
    host: '127.0.0.1',
    port: 5432,
    dbname: 'knowverse_development',
    user: 'postgres',
    password: ENV.fetch('PGPASSWORD', ''),
    connect_timeout: 5
  )
  elapsed = Time.now - start_time
  
  format_status(:success, "Connected to PostgreSQL server directly with IPv4 in #{elapsed.round(3)}s")
  format_status(:info, "Server version: #{conn.server_version}")
  
  # Test query execution
  begin
    result = conn.exec("SELECT 1 as test")
    if result[0]["test"] == "1"
      format_status(:success, "Query execution successful")
    else
      format_status(:warning, "Query returned unexpected result: #{result[0]["test"]}")
    end
  rescue => e
    format_status(:error, "Query execution failed: #{e.message}")
  end
  
  conn.close
rescue => e
  format_status(:error, "Connection failed: #{e.message}")
  format_status(:info, "Backtrace: #{e.backtrace.first(3).join("\n               ")}")
end
puts

# Test connection with localhost
puts "2. Testing direct PG connection with 'localhost' (may trigger IPv6)"
begin
  start_time = Time.now
  conn = PG.connect(
    host: 'localhost',
    port: 5432,
    dbname: 'knowverse_development',
    user: 'postgres',
    password: ENV.fetch('PGPASSWORD', ''),
    connect_timeout: 5
  )
  elapsed = Time.now - start_time
  
  format_status(:success, "Connected to PostgreSQL server with 'localhost' in #{elapsed.round(3)}s")
  format_status(:info, "Server version: #{conn.server_version}")
  conn.close
rescue => e
  format_status(:error, "Connection failed: #{e.message}")
  format_status(:info, "Backtrace: #{e.backtrace.first(3).join("\n               ")}")
end
puts

# Test Enterprise ConnectionManager if available
if defined?(Database::ConnectionManager)
  puts "3. Testing Enterprise ConnectionManager"
  
  connection_manager = Database::ConnectionManager.instance
  
  begin
    start_time = Time.now
    conn = connection_manager.connection
    elapsed = Time.now - start_time
    
    format_status(:success, "Connected using Enterprise ConnectionManager in #{elapsed.round(3)}s")
    
    # Test query execution
    begin
      result = conn.exec("SELECT 1 as test")
      if result[0]["test"] == "1"
        format_status(:success, "Query execution successful")
      else
        format_status(:warning, "Query returned unexpected result: #{result[0]["test"]}")
      end
    rescue => e
      format_status(:error, "Query execution failed: #{e.message}")
    end
    
    conn.close
    
    # Check connection metrics
    status = connection_manager.status
    format_status(:info, "Connection Manager Status:")
    format_status(:info, "  Circuit Breaker: #{status[:circuit_breaker][:state]}")
    format_status(:info, "  Total Attempts: #{status[:metrics][:total_attempts]}")
    format_status(:info, "  Success Rate: #{status[:metrics][:success_rate].round(2)}%")
    format_status(:info, "  Avg Connect Time: #{status[:metrics][:average_connect_time].round(3)}s")
  rescue => e
    format_status(:error, "Enterprise ConnectionManager failed: #{e.message}")
    format_status(:info, "Backtrace: #{e.backtrace.first(3).join("\n               ")}")
  end
  puts
  
  # Test circuit breaker functionality
  puts "4. Testing Circuit Breaker Functionality"
  
  # First reset the circuit breaker to ensure clean state
  begin
    connection_manager.reset_circuit_breaker
    format_status(:success, "Circuit breaker reset")
  rescue => e
    format_status(:error, "Failed to reset circuit breaker: #{e.message}")
  end
  
  # Create an invalid config to trigger failures
  begin
    format_status(:info, "Attempting to trigger circuit breaker with bad configuration...")
    
    # Make multiple bad connection attempts to trigger circuit breaker
    5.times do |i|
      begin
        Timeout.timeout(2) do
          conn = connection_manager.connection(
            host: 'invalid-host',
            port: 9999,
            connect_timeout: 1
          )
          conn.close
        end
      rescue => e
        format_status(:info, "  Attempt #{i+1} failed as expected: #{e.message.split("\n").first}")
      end
    end
    
    # Check circuit breaker state
    status = connection_manager.status
    if status[:circuit_breaker][:state] == :open
      format_status(:success, "Circuit breaker opened as expected after multiple failures")
    else
      format_status(:warning, "Circuit breaker did not open as expected, state: #{status[:circuit_breaker][:state]}")
    end
    
    # Try a valid connection with circuit breaker open
    begin
      Timeout.timeout(2) do
        conn = connection_manager.connection
        format_status(:warning, "Unexpected success: connection succeeded while circuit breaker open")
        conn.close
      end
    rescue => e
      if e.message.include?("Circuit breaker open")
        format_status(:success, "Connection correctly rejected due to open circuit breaker")
      else
        format_status(:warning, "Connection failed with unexpected error: #{e.message}")
      end
    end
    
    # Reset circuit breaker to restore functionality
    connection_manager.reset_circuit_breaker
    format_status(:success, "Circuit breaker reset successfully")
    
    # Verify system is functional again
    begin
      conn = connection_manager.connection
      format_status(:success, "Connection successful after circuit breaker reset")
      conn.close
    rescue => e
      format_status(:error, "Connection failed after circuit breaker reset: #{e.message}")
    end
  rescue => e
    format_status(:error, "Circuit breaker test failed: #{e.message}")
    format_status(:info, "Backtrace: #{e.backtrace.first(3).join("\n               ")}")
  end
  puts
end

# Test ActiveRecord connection if available
if rails_env_loaded && defined?(ActiveRecord)
  puts "5. Testing ActiveRecord Connection"
  
  begin
    start_time = Time.now
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      elapsed = Time.now - start_time
      
      format_status(:success, "ActiveRecord connection succeeded in #{elapsed.round(3)}s")
      format_status(:info, "ActiveRecord adapter: #{connection.adapter_name}")
      format_status(:info, "Database: #{connection.current_database}")
      
      # Get connection config (sensitive details filtered)
      config = connection.pool.db_config.configuration_hash.reject { |k,v| k.to_s == 'password' }
      format_status(:info, "Connection config: #{config}")
      
      # Test query execution
      result = connection.execute("SELECT 1 as test")
      begin
        test_value = result.first["test"] || result.first[0] # Handles different result formats
        if test_value.to_s == "1"
          format_status(:success, "Query execution successful")
        else
          format_status(:warning, "Query returned unexpected result: #{test_value}")
        end
      rescue => e
        format_status(:warning, "Could not parse query result: #{e.message}")
      end
    end
  rescue => e
    format_status(:error, "ActiveRecord connection failed: #{e.message}")
    format_status(:info, "Backtrace: #{e.backtrace.first(3).join("\n               ")}")
  end
  puts
end

puts "SERVER DIAGNOSTIC INFORMATION"
puts "════════════════════════════\n"

# Gather network interface information to check IPv4/IPv6 bindings
puts "Network Interface Status:"
interface_command = case RbConfig::CONFIG['host_os']
when /mswin|mingw|cygwin/
  "ipconfig"
when /darwin|mac os/
  "ifconfig"
when /linux/
  "ip addr show"
else
  nil
end

if interface_command
  begin
    output = `#{interface_command}`
    ipv4_count = output.scan(/inet[\s]+addr[\s]*:[\s]*([0-9.]+)|inet[\s]+([0-9.]+)/).flatten.compact.size
    ipv6_count = output.scan(/inet6[\s]+addr[\s]*:[\s]*([0-9a-f:]+)|inet6[\s]+([0-9a-f:]+)/).flatten.compact.size
    
    format_status(:info, "IPv4 Addresses: #{ipv4_count}")
    format_status(:info, "IPv6 Addresses: #{ipv6_count}")
    
    if ipv4_count == 0
      format_status(:warning, "No IPv4 addresses found, may impact connection ability")
    end
    
    if ipv6_count > 0
      format_status(:info, "IPv6 is enabled on this system")
    else
      format_status(:info, "IPv6 appears to be disabled on this system")
    end
  rescue => e
    format_status(:warning, "Could not determine network interface status: #{e.message}")
  end
else
  format_status(:warning, "Could not determine network interface command for this OS")
end
puts

# Check PostgreSQL server status
puts "PostgreSQL Server Status:"
pg_command = case RbConfig::CONFIG['host_os']
when /mswin|mingw|cygwin/
  "pg_ctl status -D \"C:/Program Files/PostgreSQL/13/data\""
when /darwin|mac os/
  "pg_ctl status -D /usr/local/var/postgres"
when /linux/
  "systemctl status postgresql"
else
  nil
end

if pg_command
  begin
    output = `#{pg_command}`
    if output.include?("server is running") || output.include?("active (running)")
      format_status(:success, "PostgreSQL server appears to be running")
    else
      format_status(:warning, "PostgreSQL server may not be running")
    end
  rescue => e
    format_status(:warning, "Could not determine PostgreSQL status: #{e.message}")
  end
else
  format_status(:warning, "Could not determine PostgreSQL status command for this OS")
end

# Try to get PostgreSQL configuration information if connected
if defined?(Database::ConnectionManager)
  begin
    connection_manager = Database::ConnectionManager.instance
    conn = connection_manager.connection
    
    # Check listen_addresses setting
    result = conn.exec("SHOW listen_addresses")
    listen_addresses = result[0]["listen_addresses"]
    format_status(:info, "PostgreSQL listen_addresses: #{listen_addresses}")
    
    if listen_addresses == "*"
      format_status(:info, "Server is listening on all addresses")
    elsif listen_addresses.include?(",")
      format_status(:info, "Server is listening on specific addresses: #{listen_addresses}")
    elsif listen_addresses == "localhost"
      format_status(:info, "Server is listening only on localhost")
      format_status(:warning, "This may cause IPv6/IPv4 resolution issues on some systems")
    elsif listen_addresses == "127.0.0.1"
      format_status(:info, "Server is listening only on IPv4 localhost")
    elsif listen_addresses == "::1"
      format_status(:info, "Server is listening only on IPv6 localhost")
      format_status(:warning, "This will prevent IPv4-only connections")
    end
    
    # Check if IPv6 is enabled in PostgreSQL
    begin
      result = conn.exec("SHOW tcp_keepalives_idle")
      format_status(:info, "tcp_keepalives_idle: #{result[0]["tcp_keepalives_idle"]}s")
    rescue => e
      format_status(:warning, "Could not get tcp_keepalives_idle: #{e.message}")
    end
    
    conn.close
  rescue => e
    format_status(:warning, "Could not get PostgreSQL configuration: #{e.message}")
  end
end
puts

puts "RECOMMENDATIONS"
puts "══════════════\n"

# Provide recommendations based on test results
if defined?(Database::ConnectionManager)
  format_status(:success, "Enterprise PostgreSQL Connection Manager is active")
  format_status(:info, "Monitor connection metrics through Rails console using 'connection_status'")
  format_status(:info, "Check circuit breaker status during connection issues")
else
  format_status(:warning, "Consider implementing the Enterprise PostgreSQL Connection Manager")
  format_status(:info, "See docs/enterprise_postgres_solution.md for implementation details")
end

# General recommendations
format_status(:info, "Ensure PostgreSQL is configured with 'listen_addresses = '0.0.0.0'' to accept all IPv4 connections")
format_status(:info, "Consider setting up pgBouncer for connection pooling")
format_status(:info, "For production deployments, implement the full HA architecture described in docs/enterprise_postgres_solution.md")

puts "\nTest completed at: #{Time.now}"
puts "══════════════════════════════════════════════════════"
