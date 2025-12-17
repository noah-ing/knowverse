namespace :email do
  desc "Test Resend email delivery directly"
  task test_resend: :environment do
    # Load OpenStruct for our test
    require 'ostruct'
    
    puts "Running Resend email test"
    
    puts "Environment:"
    puts "  RESEND_API_KEY present?: #{ENV['RESEND_API_KEY'].present?}"
    puts "  RESEND_API_KEY first 5 chars: #{ENV['RESEND_API_KEY']&.first(5)}"
    puts "  Rails.env: #{Rails.env}"
    puts "  ActionMailer delivery method: #{ActionMailer::Base.delivery_method}"
    
    # Find or create a test user
    user = User.first || User.create!(email: "test@testing-resend.com", password: SecureRandom.hex(10))
    puts "  Test user: #{user.email}"
    
    puts "\nAttempting to send test email via Resend..."
    begin
      # First verify the Resend.api_key is set
      puts "  Resend.api_key present?: #{Resend.api_key.present?}"
      puts "  Resend.api_key first 5 chars: #{Resend.api_key&.first(5)}"
      
      # Create a simple login token mock for testing
      login_token = OpenStruct.new(url: "https://alpinedigital.io/test-magic-link")
      
      # Try to send an email using deliver_now
      email = UserMailer.magic_link(user, login_token)
      puts "  Email object created with to: #{email.to}, from: #{email.from}, subject: #{email.subject}"
      
      result = email.deliver_now
      puts "  Email delivery result: #{result.inspect}"
      puts "✅ Test email sent successfully!"
    rescue => e
      puts "❌ Error sending test email: #{e.class.name} - #{e.message}"
      puts e.backtrace
    end
    
    puts "\nTesting direct Resend API access..."
    begin
      # Test direct API access as well
      require 'net/http'
      require 'uri'
      require 'json'
      
      uri = URI.parse('https://api.resend.com/emails')
      request = Net::HTTP::Post.new(uri)
      request.content_type = 'application/json'
      request['Authorization'] = "Bearer #{ENV['RESEND_API_KEY']}"
      
      request.body = JSON.dump({
        'from' => 'no-reply@alpinedigital.io',
        'to' => user.email, # Use the real test user email
        'subject' => 'Test Email from Direct API',
        'html' => '<p>This is a test email sent directly via the Resend API.</p>'
      })
      
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end
      
      puts "  API Response: #{response.code} #{response.message}"
      puts "  Response body: #{response.body}"
      
      if response.code.to_i < 300
        puts "✅ Direct API test successful!"
      else
        puts "❌ Direct API test failed with response code #{response.code}"
        puts "  Error: #{response.body}"
      end
    rescue => e
      puts "❌ Error with direct API access: #{e.class.name} - #{e.message}"
      puts e.backtrace
    end
  end
end
