#!/usr/bin/env ruby
# KnowVerse PostgreSQL Connection Pooling Setup (Phase 2)
# This script implements phase 2 of the enterprise PostgreSQL solution:
# - Diagnoses current PostgreSQL connectivity issues
# - Prepares for pgBouncer installation
# - Creates necessary configuration files

require 'fileutils'
require 'yaml'
require 'erb'
require 'pg'

# Set appropriate colors for terminal output
RESET = "\e[0m"
GREEN = "\e[32m"
RED = "\e[31m"
YELLOW = "\e[33m"
BLUE = "\e[34m"

def print_header(text)
  puts "\n#{BLUE}=== #{text} ==#{RESET}\n\n"
end

def print_success(text)
  puts "#{GREEN}✓ #{text}#{RESET}"
end

def print_error(text)
  puts "#{RED}✗ #{text}#{RESET}"
end

def print_warning(text)
  puts "#{YELLOW}! #{text}#{RESET}"
end

def print_info(text)
  puts "  #{text}"
end

print_header("KnowVerse PostgreSQL Connection Pooling Setup (Phase 2)")
print_info("This script diagnoses database connectivity and prepares for pgBouncer setup.")

# Step 1: Check if PostgreSQL is running
print_header("PostgreSQL Service Check")

begin
  # Try to connect with a simple pg_isready
  isready_result = `pg_isready -h 127.0.0.1 -d knowverse_development`
  
  if isready_result.include?("accepting connections")
    print_success("PostgreSQL server is accepting connections")
  else
    print_error("PostgreSQL server is not accepting connections")
    print_info("Attempting to diagnose connection issues...")
    
    # Check if we can get more details about the service status
    if RUBY_PLATFORM =~ /mswin|mingw|cygwin/
      # Windows service check
      status = `sc query postgresql`
      if status.include?("RUNNING")
        print_success("PostgreSQL service is running according to Windows Service Control")
      else
        print_warning("PostgreSQL service is not running. Consider starting it with: sc start postgresql")
      end
    elsif RUBY_PLATFORM =~ /darwin/
      # macOS check
      status = `brew services list | grep postgres`
      if status.include?("started")
        print_success("PostgreSQL service is running according to Homebrew")
      else
        print_warning("PostgreSQL service is not running. Consider starting it with: brew services start postgresql")
      end
    else
      # Linux check
      status = `systemctl status postgresql 2>&1`
      if status.include?("active (running)")
        print_success("PostgreSQL service is running according to systemctl")
      else
        print_warning("PostgreSQL service is not running. Consider starting it with: sudo systemctl start postgresql")
      end
    end
  end
rescue => e
  print_error("Error checking PostgreSQL status: #{e.message}")
end

# Step 2: Verify connection parameters
print_header("Connection Parameter Verification")

def load_database_config
  config = {}
  
  # Try Rails database.yml if available
  begin
    if File.exist?('config/database.yml')
      db_config = YAML.load_file('config/database.yml')
      env = ENV['RAILS_ENV'] || 'development'
      config = db_config[env] || {}
      print_success("Loaded configuration from Rails database.yml")
    end
  rescue => e
    print_error("Failed to load Rails database configuration: #{e.message}")
  end
  
  # Environment variables take precedence
  config['host'] = ENV['PGHOST'] if ENV['PGHOST']
  config['port'] = ENV['PGPORT'].to_i if ENV['PGPORT']
  config['database'] = ENV['PGDATABASE'] if ENV['PGDATABASE']
  config['username'] = ENV['PGUSER'] if ENV['PGUSER']
  config['password'] = ENV['PGPASSWORD'] if ENV['PGPASSWORD']
  
  # Parse DATABASE_URL if available
  if ENV['DATABASE_URL']
    begin
      require 'uri'
      uri = URI.parse(ENV['DATABASE_URL'])
      config['host'] = uri.host if uri.host
      config['port'] = uri.port if uri.port
      config['username'] = uri.user if uri.user
      config['password'] = uri.password if uri.password
      config['database'] = uri.path.sub(/^\//, '') if uri.path
      print_success("Parsed DATABASE_URL environment variable")
    rescue => e
      print_error("Failed to parse DATABASE_URL: #{e.message}")
    end
  end
  
  # Default values if nothing is set
  config['host'] ||= '127.0.0.1'
  config['port'] ||= 5432
  config['database'] ||= 'knowverse_development'
  config['username'] ||= 'postgres'
  
  # Force IPv4 by ensuring host is not 'localhost'
  if config['host'] == 'localhost'
    config['host'] = '127.0.0.1'
    print_info("Converting 'localhost' to '127.0.0.1' for explicit IPv4")
  end
  
  config
end

db_config = load_database_config

# Display the configuration (without password)
print_info("Database configuration:")
db_config.each do |key, value|
  if key.to_s == 'password'
    print_info("  #{key}: [FILTERED]")
  else
    print_info("  #{key}: #{value}")
  end
end

# Step 3: Try different connection approaches
print_header("Connection Tests")

# Try direct PG connection
begin
  print_info("Attempting direct PG connection...")
  
  connection_params = {
    host: db_config['host'],
    port: db_config['port'],
    dbname: db_config['database'],
    user: db_config['username'],
    password: db_config['password'],
    connect_timeout: 5
  }
  
  start_time = Time.now
  conn = PG.connect(connection_params)
  
  if conn
    elapsed = Time.now - start_time
    print_success("Direct PG connection succeeded in #{elapsed.round(3)}s")
    
    # Try a simple query
    result = conn.exec("SELECT 1 as test")
    if result[0]["test"] == "1"
      print_success("Query executed successfully")
    else
      print_warning("Query returned unexpected result: #{result[0]["test"]}")
    end
    
    print_info("PostgreSQL version: #{conn.server_version}")
    conn.close
  end
rescue => e
  print_error("Direct PG connection failed: #{e.message}")
  
  # Provide troubleshooting steps
  if e.message.include?("role")
    print_warning("This may be a role/user authentication issue. Check that the user '#{db_config['username']}' exists.")
  elsif e.message.include?("password")
    print_warning("This may be a password authentication issue. Verify the password for '#{db_config['username']}'.")
  elsif e.message.include?("connection")
    print_warning("This may be a connection issue. Verify PostgreSQL is running and listening on #{db_config['host']}:#{db_config['port']}.")
  end
end

# Step 4: Check PostgreSQL configuration
print_header("PostgreSQL Configuration Check")

begin
  # Try to get PostgreSQL configuration
  conn = PG.connect(
    host: db_config['host'], 
    port: db_config['port'], 
    dbname: db_config['database'], 
    user: db_config['username'], 
    password: db_config['password'],
    connect_timeout: 3
  )
  
  # Check important PostgreSQL settings
  settings_to_check = [
    'listen_addresses',
    'max_connections',
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'max_worker_processes',
    'max_parallel_workers',
    'tcp_keepalives_idle',
    'tcp_keepalives_interval',
    'tcp_keepalives_count'
  ]
  
  print_info("PostgreSQL configuration:")
  
  settings_to_check.each do |setting|
    begin
      result = conn.exec("SHOW #{setting}")
      value = result[0][setting]
      print_info("  #{setting}: #{value}")
    rescue => e
      print_warning("  Could not read #{setting}: #{e.message}")
    end
  end
  
  conn.close
rescue => e
  print_error("Could not check PostgreSQL configuration: #{e.message}")
end

# Step 5: pgBouncer preparation
print_header("pgBouncer Preparation")

# Check if pgBouncer is already installed
pgbouncer_installed = false

begin
  pgb_version = `pgbouncer --version 2>&1`
  if pgb_version.include?("version")
    pgbouncer_installed = true
    print_success("pgBouncer is already installed: #{pgb_version.strip}")
  else
    print_warning("pgBouncer is not installed")
    
    # Provide installation instructions based on platform
    if RUBY_PLATFORM =~ /mswin|mingw|cygwin/
      print_info("To install pgBouncer on Windows:")
      print_info("  1. Download from https://www.pgbouncer.org/downloads/")
      print_info("  2. Extract to a directory (e.g., C:\\pgbouncer)")
      print_info("  3. Create a pgbouncer.ini file with the configuration below")
    elsif RUBY_PLATFORM =~ /darwin/
      print_info("To install pgBouncer on macOS:")
      print_info("  brew install pgbouncer")
    else
      print_info("To install pgBouncer on Linux:")
      print_info("  sudo apt-get install pgbouncer    # Debian/Ubuntu")
      print_info("  sudo yum install pgbouncer        # RHEL/CentOS")
    end
  end
rescue => e
  print_warning("Could not determine if pgBouncer is installed: #{e.message}")
end

# Generate pgBouncer configuration
pgbouncer_config_dir = 'config/pgbouncer'
FileUtils.mkdir_p(pgbouncer_config_dir) unless Dir.exist?(pgbouncer_config_dir)

# Create pgbouncer.ini
pgbouncer_ini = <<-INI
[databases]
#{db_config['database']} = host=#{db_config['host']} port=#{db_config['port']} dbname=#{db_config['database']}

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = md5
auth_file = config/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 100
reserve_pool_size = 25
reserve_pool_timeout = 5
server_reset_query = DISCARD ALL
server_check_query = select 1
server_check_delay = 30
tcp_keepalive = 1
tcp_keepidle = 60
tcp_keepintvl = 10
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60
INI

File.write(File.join(pgbouncer_config_dir, 'pgbouncer.ini'), pgbouncer_ini)
print_success("Created pgbouncer.ini configuration file")

# Create userlist.txt (with hashed password)
username = db_config['username'] || 'postgres'
password = db_config['password'] || ''

# Use PostgreSQL's MD5 password format if we can connect
begin
  require 'digest/md5'
  
  # If we have a password, create a properly hashed entry
  if password && !password.empty?
    md5_pass = "md5" + Digest::MD5.hexdigest(password + username)
    userlist = %Q{"#{username}" "#{md5_pass}"}
  else
    # No password case
    userlist = %Q{"#{username}" ""}
  end
  
  File.write(File.join(pgbouncer_config_dir, 'userlist.txt'), userlist)
  print_success("Created userlist.txt authentication file")
rescue => e
  print_error("Could not create userlist.txt: #{e.message}")
end

# Update database.yml with pgBouncer configuration
pgbouncer_database_yml = <<-YAML
# PostgreSQL Connection Pooling Configuration
# This configuration uses pgBouncer for connection pooling

default: &default
  adapter: postgresql
  encoding: unicode
  # For details on connection pooling, see Rails configuration guide
  # https://guides.rubyonrails.org/configuring.html#database-pooling
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  # pgBouncer connection details
  host: 127.0.0.1
  port: 6432
  username: #{db_config['username']}
  password: <%= ENV["KNOWVERSE_DATABASE_PASSWORD"] %>
  # Important for pgBouncer
  prepared_statements: false
  advisory_locks: false

development:
  <<: *default
  database: #{db_config['database']}

# Warning: The database defined as "test" will be erased and
# re-generated from your development database when you run "rake".
# Do not set this db to the same as development or production.
test:
  <<: *default
  database: #{db_config['database']}_test

production:
  primary: &primary_production
    <<: *default
    database: #{db_config['database']}_production
    username: <%= ENV["KNOWVERSE_DATABASE_USERNAME"] %>
    password: <%= ENV["KNOWVERSE_DATABASE_PASSWORD"] %>
  cache:
    <<: *primary_production
    database: #{db_config['database']}_production_cache
    migrations_paths: db/cache_migrate
  queue:
    <<: *primary_production
    database: #{db_config['database']}_production_queue
    migrations_paths: db/queue_migrate
  cable:
    <<: *primary_production
    database: #{db_config['database']}_production_cable
    migrations_paths: db/cable_migrate
YAML

# Write to a new file to avoid overwriting existing config
File.write(File.join(pgbouncer_config_dir, 'database_with_pgbouncer.yml'), pgbouncer_database_yml)
print_success("Created database_with_pgbouncer.yml configuration template")

print_header("Next Steps")
print_info("1. Ensure PostgreSQL server is correctly configured with 'listen_addresses = '*'' in postgresql.conf")
print_info("2. Install pgBouncer if not already installed")
print_info("3. Copy configuration files from the #{pgbouncer_config_dir} directory to the appropriate location")
print_info("4. Start pgBouncer service")
print_info("5. Update the application to use pgBouncer by replacing config/database.yml or setting DATABASE_URL")

if !pgbouncer_installed
  print_warning("pgBouncer is not installed. Please install it before proceeding to the next steps.")
end

print_header("Summary")
print_info("Diagnostic script completed. This script has prepared configurations for pgBouncer setup.")
print_info("See the documentation in docs/enterprise_postgres_solution.md for detailed implementation instructions.")
