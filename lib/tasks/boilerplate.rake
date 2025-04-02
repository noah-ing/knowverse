namespace :boilerplate do
  desc "Verify all core systems are functioning correctly"
  task verify: :environment do
    puts "\n=== Gold SaaS Boilerplate Verification ===\n\n"
    
    # Track overall status
    all_systems_go = true
    
    # Database check
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      puts "✅ Database connection: VERIFIED"
    rescue => e
      puts "❌ Database connection: FAILED (#{e.message})"
      all_systems_go = false
    end
    
    # Redis check
    begin
      if defined?(Redis)
        redis = Redis.new(Rails.application.config_for(:cable)[:adapter] == 'redis' ? 
                 Rails.application.config_for(:cable)[:url] : {})
        redis.ping
        puts "✅ Redis connection: VERIFIED"
      else
        puts "❓ Redis connection: NOT CONFIGURED"
      end
    rescue => e
      puts "❌ Redis connection: FAILED (#{e.message})"
      all_systems_go = false
    end
    
    # Email configuration check
    begin
      if ENV['RESEND_API_KEY'].present?
        puts "✅ Resend API Key: CONFIGURED"
      else
        puts "❌ Resend API Key: MISSING"
        all_systems_go = false
      end
      
      from_address = Rails.application.config.action_mailer.default_options&.[](:from)
      if from_address.present?
        puts "✅ Email From Address: CONFIGURED (#{from_address})"
      else
        puts "❌ Email From Address: MISSING"
        all_systems_go = false
      end
    rescue => e
      puts "❌ Email configuration: FAILED (#{e.message})"
      all_systems_go = false
    end
    
    # Stripe API connectivity check
    begin
      if ENV['STRIPE_SECRET_KEY'].present?
        puts "✅ Stripe Secret Key: CONFIGURED"
      else
        puts "❌ Stripe Secret Key: MISSING"
        all_systems_go = false
      end
      
      if ENV['STRIPE_PUBLISHABLE_KEY'].present?
        puts "✅ Stripe Publishable Key: CONFIGURED"
      else
        puts "❌ Stripe Publishable Key: MISSING"
        all_systems_go = false
      end
      
      if ENV['STRIPE_WEBHOOK_SECRET'].present?
        puts "✅ Stripe Webhook Secret: CONFIGURED"
      else
        puts "❌ Stripe Webhook Secret: MISSING"
        all_systems_go = false
      end
      
      # Verify Stripe connection by getting a simple API response
      if ENV['STRIPE_SECRET_KEY'].present?
        begin
          Stripe::Balance.retrieve
          puts "✅ Stripe API connection: VERIFIED"
        rescue Stripe::AuthenticationError
          puts "❌ Stripe API connection: FAILED (Invalid API key)"
          all_systems_go = false
        rescue => e
          puts "❌ Stripe API connection: FAILED (#{e.message})"
          all_systems_go = false
        end
      end
    rescue => e
      puts "❌ Stripe configuration: FAILED (#{e.message})"
      all_systems_go = false
    end
    
    # Background jobs check
    begin
      if defined?(SolidQueue)
        # Check if the queues table exists
        begin
          SolidQueue::Job.count
          puts "✅ SolidQueue: VERIFIED"
        rescue => e
          puts "❌ SolidQueue: FAILED (#{e.message})"
          all_systems_go = false
        end
      else
        puts "❓ Background jobs: NOT CONFIGURED"
      end
    rescue => e
      puts "❌ Background jobs: FAILED (#{e.message})"
      all_systems_go = false
    end
    
    # Storage configuration check
    begin
      if Rails.application.config.active_storage.service.present?
        puts "✅ Active Storage: CONFIGURED (#{Rails.application.config.active_storage.service})"
      else
        puts "❌ Active Storage: NOT CONFIGURED"
        all_systems_go = false
      end
    rescue => e
      puts "❌ Storage configuration: FAILED (#{e.message})"
      all_systems_go = false
    end
    
    # Models check
    puts "\n=== Data Models ===\n"
    
    begin
      user_count = User.count
      puts "✅ Users: #{user_count} records"
    rescue => e
      puts "❌ Users: FAILED (#{e.message})"
      all_systems_go = false
    end
    
    begin
      plan_count = Plan.count
      puts "✅ Plans: #{plan_count} records"
    rescue => e
      puts "❌ Plans: FAILED (#{e.message})"
      all_systems_go = false
    end
    
    # Analytics check
    begin
      if defined?(Ahoy)
        visit_count = Ahoy::Visit.count
        event_count = Ahoy::Event.count
        puts "✅ Analytics (Ahoy): CONFIGURED (#{visit_count} visits, #{event_count} events)"
      else
        puts "❓ Analytics: NOT CONFIGURED"
      end
    rescue => e
      puts "❌ Analytics: FAILED (#{e.message})"
    end
    
    # Final status
    puts "\n=== Summary ===\n"
    if all_systems_go
      puts "🎉 All core systems are functioning correctly!"
    else
      puts "⚠️ Some systems are not functioning correctly. Please review the output above."
    end
  end
end
