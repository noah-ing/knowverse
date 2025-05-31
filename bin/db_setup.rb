#!/usr/bin/env ruby
# This script sets up the database connection for Windows compatibility

# Force IPv4 and set the PostgreSQL environment variables
ENV["DATABASE_HOST"] = "127.0.0.1"
ENV["DATABASE_USERNAME"] = "postgres" 
ENV["DATABASE_PASSWORD"] = "postgres"
ENV["DATABASE_URL"] = "postgresql://postgres:postgres@127.0.0.1:5432/knowverse_development?sslmode=disable"
ENV["PGHOST"] = "127.0.0.1"
ENV["PGUSER"] = "postgres"
ENV["PGPASSWORD"] = "postgres"

# Print the configured environment
puts "Using database configuration:"
puts "  Host: #{ENV['DATABASE_HOST']}"
puts "  Username: #{ENV['DATABASE_USERNAME']}"
puts "  Database URL: #{ENV['DATABASE_URL']}"

# Run the migrations
require File.expand_path('../config/environment', __dir__)
require 'active_record/migration'

puts "Running database migrations..."
ActiveRecord::Base.establish_connection
ActiveRecord::MigrationContext.new("db/migrate/", ActiveRecord::Base.connection).migrate
puts "Migrations complete!"
