source "https://rubygems.org"

gem "rails", "~> 8.0.2"
gem "propshaft"
gem "pg", "~> 1.1"
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
gem "stripe", "~> 9.0"
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
