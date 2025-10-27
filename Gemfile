source "https://rubygems.org"

gem "rails", "~> 8.0.2"
gem "propshaft"
gem "pg", "~> 1.1"
gem "sqlite3", "~> 1.4"
gem "puma", ">= 5.0"
gem "tailwindcss-rails"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

gem "devise"
gem "devise-passwordless"
gem "resend"
gem "dotenv-rails"

# Stripe and subscription management
gem "stripe", "~> 17.0"
gem "pay", "~> 6.8"
gem "stripe_event"

gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails", "~> 6.0"
  gem "factory_bot_rails"
  gem "faker"
  
  # Testing tools for distributed system
  gem "benchmark-ips", "~> 2.12" # Performance benchmarking
  gem "memory_profiler", "~> 1.0" # Memory usage profiling
  gem "ruby-progressbar", "~> 1.13" # Progress reporting for long tests
  gem "rspec-benchmark", "~> 0.6" # Performance expectations in tests
  gem "timecop", "~> 0.9" # Time manipulation for tests
  gem "connection_pool", "~> 2.4" # Connection pooling for tests
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  gem "webmock"
  gem "vcr"
  gem "shoulda-matchers"
  gem "database_cleaner-active_record"
end

gem "kaminari", "~> 1.2"

# Analytics
gem "ahoy_matey"
gem "groupdate"
gem "chartkick"

# KnowVerse additions - Enterprise Docker Environment
gem "sidekiq", "~> 7.2" # Background job processing
gem "redis", "~> 5.0" # Required for Redis operations and distributed locking
gem "redis-namespace", "~> 1.11" # Namespace support for Redis
gem "oj", "~> 3.16" # Fast JSON serialization/deserialization
gem "concurrent-ruby", "~> 1.2" # Thread-safe concurrent operations
gem "websocket-client-simple", "~> 0.6" # WebSocket client for node communication
gem "websocket-driver", "~> 0.7" # WebSocket protocol implementation
gem "pgvector", "~> 0.2" # PostgreSQL vector extension support
gem "pundit", "~> 2.3" # Authorization policies for multi-tenancy
gem "view_component", "~> 3.9" # Component-based UI
gem "pagy", "~> 7.0" # Pagination

gem "colorize", "~> 1.1"
