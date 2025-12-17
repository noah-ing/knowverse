namespace :auth do
  desc "Debug the entire magic link email flow"
  task debug_flow: :environment do
    puts "🧪 TESTING MAGIC LINK AUTHENTICATION FLOW 🧪"
    
    # 1. Create a test user if one doesn't exist
    email = "test-magic-link@testing-resend.com"
    user = User.find_by(email: email) || User.create!(email: email, password: SecureRandom.hex(10))
    puts "✅ Test user: #{user.email}"
    
    # 2. Create a login token (same as in MagicLinksController)
    puts "\n📝 Creating login token..."
    # Look at the source code for MagicLinksController to see how it creates tokens
    puts "  Finding devise modules for user..."
    puts "  User devise modules: #{user.class.devise_modules}"
    
    # Try to use the same method as in the controller
    begin
      login_token = Devise::Passwordless::LoginToken.create(resource: user)
      puts "✅ Login token created: #{login_token.inspect}"
      puts "✅ Login URL: #{login_token.url}"
    rescue => e
      puts "❌ Error creating login token: #{e.class.name} - #{e.message}"
      puts "  Trying alternative approach..."
      
      # Create a simplified mock token for testing email only
      require 'ostruct'
      login_token = OpenStruct.new(
        url: "https://alpinedigital.io/users/magic_link/test-token",
        token: "test-token",
        created_at: Time.now,
        expires_at: Time.now + 15.minutes
      )
      puts "✅ Created mock login token for testing: #{login_token.inspect}"
    end
    
    # 3. Generate the email
    puts "\n📧 Generating email..."
    mail = UserMailer.magic_link(user, login_token)
    puts "✅ Mail object generated:"
    puts "  From: #{mail.from}"
    puts "  To: #{mail.to}"
    puts "  Subject: #{mail.subject}"
    
    # 4. Attempt delivery
    puts "\n📤 Attempting email delivery..."
    puts "  ActionMailer delivery method: #{ActionMailer::Base.delivery_method}"
    puts "  Resend API key present?: #{ENV['RESEND_API_KEY'].present?}"
    puts "  Resend API key first 5 chars: #{ENV['RESEND_API_KEY']&.first(5)}"
    
    begin
      result = mail.deliver_now
      puts "✅ Email delivery successful!"
      puts "  Result: #{result.inspect}"
    rescue => e
      puts "❌ Email delivery failed with error: #{e.class.name} - #{e.message}"
      puts e.backtrace
    end
    
    puts "\n🔍 DEBUGGING INFO"
    puts "- If the email was not received, check your spam folder"
    puts "- Verify the domain 'alpinedigital.io' is properly verified in Resend"
    puts "- Check Rails logs for any additional error information"
    puts "- Try the direct API test: rake email:test_resend"
    
    puts "\n✨ TO TEST IN BROWSER ✨"
    puts "1. Start the server: bin/dev"
    puts "2. Visit the login page"
    puts "3. Enter the email: #{user.email}"
    puts "4. Submit the form and check the server logs for detailed debugging"
  end
end
