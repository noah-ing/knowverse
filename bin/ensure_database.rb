#!/usr/bin/env ruby
# PostgreSQL Database Setup Script
# This script ensures the database exists and has proper permissions

require 'pg'
require 'uri'
require 'fileutils'

def log(message)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{message}"
end

log "KnowVerse PostgreSQL Database Setup"
log "=================================="

# Load database configuration from .env.local if it exists
if File.exist?(".env.local")
  log "Loading DATABASE_URL from .env.local..."
  env_content = File.read(".env.local")
  if env_content =~ /DATABASE_URL=([^\s]+)/
    database_url = $1
    log "Found DATABASE_URL: #{database_url.gsub(/:[^:]*@/, ':***@')}"
    
    # Parse the URL
    uri = URI.parse(database_url)
    
    # Extract components
    host = uri.host || "127.0.0.1"
    port = uri.port || 5432
    username = uri.user || "postgres"
    password = uri.password || "postgres"
    database_name = uri.path.sub(/^\//, '')
    
    log "  Host: #{host}"
    log "  Port: #{port}"
    log "  User: #{username}"
    log "  Database: #{database_name}"
  else
    log "No DATABASE_URL found in .env.local, using defaults."
    host = "127.0.0.1"
    port = 5432
    username = "postgres"
    password = "postgres"
    database_name = "knowverse_development"
  end
else
  log "No .env.local file found, using defaults."
  host = "127.0.0.1"
  port = 5432
  username = "postgres"
  password = "postgres"
  database_name = "knowverse_development"
end

# First, try to connect to the postgres admin database
log "Attempting to connect to PostgreSQL server..."

begin
  # Force IPv4
  conn = PG.connect(
    host: host,
    port: port,
    user: username,
    password: password,
    dbname: 'postgres',
    connect_timeout: 5
  )
  
  log "✅ Successfully connected to PostgreSQL server!"
  
  # Check if the target database exists
  result = conn.exec("SELECT 1 FROM pg_database WHERE datname = $1", [database_name])
  
  if result.count > 0
    log "✅ Database '#{database_name}' already exists"
  else
    log "Creating database '#{database_name}'..."
    # Create the database
    conn.exec("CREATE DATABASE #{database_name} OWNER #{username}")
    log "✅ Database '#{database_name}' created successfully"
  end
  
  # Close the admin connection
  conn.close
  
  # Connect to the target database
  log "Connecting to '#{database_name}' database..."
  conn = PG.connect(
    host: host,
    port: port,
    user: username,
    password: password,
    dbname: database_name,
    connect_timeout: 5
  )
  
  log "✅ Successfully connected to '#{database_name}' database"
  
  # Check if the pgvector extension is installed
  result = conn.exec("SELECT 1 FROM pg_extension WHERE extname = 'vector'")
  
  if result.count > 0
    log "✅ pgvector extension is already installed"
  else
    begin
      log "Installing pgvector extension..."
      conn.exec("CREATE EXTENSION vector")
      log "✅ pgvector extension installed successfully"
    rescue PG::Error => e
      log "❌ Error installing pgvector extension: #{e.message}"
      log "   This is expected if the extension is not available on your server."
      log "   You may need to install the 'postgresql-13-vector' package."
    end
  end
  
  # Check permissions for our user
  result = conn.exec("SELECT has_database_privilege($1, $2, 'CREATE')", [username, database_name])
  if result[0]["has_database_privilege"] == "t"
    log "✅ User '#{username}' has CREATE permissions on '#{database_name}'"
  else
    log "Granting permissions to '#{username}'..."
    conn.exec("GRANT ALL PRIVILEGES ON DATABASE #{database_name} TO #{username}")
    log "✅ Permissions granted to '#{username}'"
  end
  
  # Close the connection
  conn.close
  
  log "Database setup complete! You can now run your Rails application."
  
rescue PG::Error => e
  log "❌ PostgreSQL Error: #{e.message}"
  log "This could be due to:"
  log "1. PostgreSQL server is not running"
  log "2. Invalid username or password"
  log "3. Network connectivity issues"
  log "4. Server configuration issues (check pg_hba.conf)"
  
  log "\nPossible solutions:"
  log "1. Ensure PostgreSQL is installed and running"
  log "2. Check your PostgreSQL credentials"
  log "3. Verify pg_hba.conf allows connections from 127.0.0.1"
  log "4. Try connecting via 'psql -U postgres -h 127.0.0.1'"
  exit 1
end
