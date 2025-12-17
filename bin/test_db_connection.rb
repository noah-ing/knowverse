                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   #!/usr/bin/env ruby
# PostgreSQL Database Connection Test Script
# This script tests direct database connectivity using both the pg gem and ActiveRecord

require 'rubygems'
require 'pg'
require 'uri'

puts "KnowVerse PostgreSQL Connection Test"
puts "==================================="
puts

# Test environment variables
puts "Environment variables:"
if ENV['DATABASE_URL']
  puts "DATABASE_URL: #{ENV['DATABASE_URL']}"
  uri = URI.parse(ENV['DATABASE_URL'])
  puts "  Host: #{uri.host}"
  puts "  Port: #{uri.port}"
  puts "  User: #{uri.user}"
  puts "  Password: #{uri.password ? '[FILTERED]' : 'none'}"
  puts "  Path: #{uri.path}"
  puts "  Query: #{uri.query}"
else
  puts "DATABASE_URL not set"
end

puts "PGUSER: #{ENV['PGUSER'] || 'not set'}"
puts "PGPASSWORD: #{ENV['PGPASSWORD'] ? '[FILTERED]' : 'not set'}"
puts "PGHOST: #{ENV['PGHOST'] || 'not set'}"
puts "PGPORT: #{ENV['PGPORT'] || 'not set'}"
puts

# Try IPv4 direct connection first
puts "Attempting IPv4 direct connection with the PG gem"
begin
  puts "Connecting to PostgreSQL at 127.0.0.1:5432..."
  conn = PG.connect(
    host: '127.0.0.1',
    port: 5432,
    dbname: 'knowverse_development',
    user: 'postgres',
    password: '***REMOVED***'
  )
  result = conn.exec("SELECT 1 as test")
  puts "  ✅ Success! Connected to PostgreSQL server directly with IPv4."
  puts "  Server version: #{conn.server_version}"
  conn.close
rescue => e
  puts "  ❌ Error: #{e.message}"
  puts "  Backtrace: #{e.backtrace.join("\n               ")}"
end
puts

# Try localhost connection to test hostname resolution
puts "Attempting localhost connection with the PG gem"
begin
  puts "Connecting to PostgreSQL at localhost:5432..."
  conn = PG.connect(
    host: 'localhost',
    port: 5432,
    dbname: 'knowverse_development',
    user: 'postgres',
    password: '***REMOVED***'
  )
  result = conn.exec("SELECT 1 as test")
  puts "  ✅ Success! Connected to PostgreSQL server directly with 'localhost'."
  puts "  Server version: #{conn.server_version}"
  conn.close
rescue => e
  puts "  ❌ Error: #{e.message}"
  puts "  Backtrace: #{e.backtrace.join("\n               ")}"
end
puts

# Check if we have ActiveRecord available
begin
  puts "Attempting to load Rails and ActiveRecord..."
  require File.expand_path('../../config/environment', __FILE__)
  
  puts "  ✅ Rails environment loaded successfully"
  
  # Test ActiveRecord connection
  puts "Testing ActiveRecord connection..."
  
  begin
  # Check if our IPv4 patch is active
  if defined?(PgIpv4ConnectionPatch) ||
     (defined?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) && 
      (ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.instance_methods.include?(:resolve_database_host) ||
       ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.private_instance_methods.include?(:resolve_database_host)))
    puts "  ✅ PostgreSQL IPv4 patch is active"
  else
    puts "  ❌ PostgreSQL IPv4 patch is NOT active"
    puts "  Available methods: #{ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.instance_methods.grep(/resolve|database|host|connect/).sort.join(', ')}" if defined?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
  end
    
  # Force 127.0.0.1 connection (no localhost) using database.yml config
  ActiveRecord::Base.establish_connection(
    adapter: 'postgresql',
    host: '127.0.0.1',
    database: 'knowverse_development',
    username: 'postgres',
    password: '***REMOVED***'
  )
  
  # Try a simple query using ActiveRecord
  result = ActiveRecord::Base.connection.execute("SELECT 1 as test")
  puts "  ✅ ActiveRecord connection successful!"
  puts "  ActiveRecord adapter: #{ActiveRecord::Base.connection.adapter_name}"
  puts "  Database: #{ActiveRecord::Base.connection.current_database}"
  puts "  Connection config: #{ActiveRecord::Base.connection_db_config.configuration_hash.reject { |k,v| k.to_s == 'password' }}"
  rescue => e
    puts "  ❌ ActiveRecord connection error: #{e.message}"
    puts "  Backtrace: #{e.backtrace.join("\n               ")}"
  end
rescue LoadError => e
  puts "  ❌ Could not load Rails environment: #{e.message}"
end
