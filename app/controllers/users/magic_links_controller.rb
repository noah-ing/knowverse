class Users::MagicLinksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:show]
  def create
    # Check for email in both parameter formats
    email = params[:email] || params.dig(:user, :email)
    
    Rails.logger.info "[MagicLink] Attempting to find user with email: #{email}"
    user = User.find_by(email: email)

    # Create a new user if one doesn't exist
    if user.nil? && email.present?
      Rails.logger.info "[MagicLink] Creating new user with email: #{email}"
      begin
        password = SecureRandom.hex(10) # Generate a random password
        user = User.create!(email: email, password: password)
        Rails.logger.info "[MagicLink] New user created: #{user.email} (ID: #{user.id})"
      rescue => e
        Rails.logger.error "[MagicLink] Failed to create user: #{e.message}"
        flash[:alert] = "There was a problem creating your account. Please try again."
        redirect_to root_path and return
      end
    end

    if user.present?
      Rails.logger.info "[MagicLink] Creating login token for #{user.email}"
      
      # The way tokens are created seems to be incorrect
      # Let's try a different approach based on the devise-passwordless gem
      begin
        login_token = Devise::Passwordless::LoginToken.create(resource: user)
        Rails.logger.info "[MagicLink] Login token created via standard method"
      rescue => e
        Rails.logger.error "[MagicLink] Standard login token creation failed: #{e.class.name} - #{e.message}"
        
        # Try to use the magic_link strategy directly
        token = Devise.friendly_token
        user.login_token = token
        user.login_token_valid_until = Time.now.utc + 15.minutes
        user.save!
        
        # Build a login URL that matches the expected format
        host = ENV.fetch("APP_HOST", "localhost:3000")
        login_url = Rails.application.routes.url_helpers.custom_user_magic_link_url(
          login_token: token,
          email: user.email,
          host: host
        )
        
        # Create an object that mimics what the controller expects
        require 'ostruct'
        login_token = OpenStruct.new(
          url: login_url,
          token: token,
          created_at: Time.now,
          expires_at: Time.now + 15.minutes
        )
        
        Rails.logger.info "[MagicLink] Created fallback login token: #{login_token.inspect}"
      end

      Rails.logger.info "[MagicLink] Sending email via Resend..."
      
      begin
        # Add detailed logging around the email delivery
        Rails.logger.info "[MagicLink] Delivery method: #{ActionMailer::Base.delivery_method}"
        Rails.logger.info "[MagicLink] API key present?: #{ENV['RESEND_API_KEY'].present?}"
        
        # Enqueue the email delivery job
        Rails.logger.info "[MagicLink] Enqueuing email job for #{user.email}"
        
        MagicLinkMailerJob.perform_later(
          user.id,
          login_token.token,
          login_token.url,
          login_token.expires_at
        )
        
        Rails.logger.info "[MagicLink] Email job enqueued successfully"
        flash[:notice] = "Magic login link sent to #{user.email}."
      rescue => e
        # Catch and log any exceptions that occur during email delivery
        Rails.logger.error "[MagicLink] Email delivery failed with error: #{e.class.name} - #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        flash[:alert] = "An error occurred while sending the login email. Please try again later."
      end
    else
      Rails.logger.warn "[MagicLink] No user found with email: #{email}"
      flash[:alert] = "No user found with that email address."
    end

    redirect_to root_path
  end
  
  def show
    token = params[:login_token]
    Rails.logger.info "[MagicLink] Processing magic link with token: #{token}"
    
    begin
      user = User.find_by(login_token: token)
      
      if user.nil?
        Rails.logger.warn "[MagicLink] No user found with token: #{token}"
        flash[:alert] = "Invalid login link. Please request a new one."
        redirect_to new_user_session_path and return
      end
      
      # Check if token is expired
      if user.login_token_valid_until.nil? || user.login_token_valid_until < Time.now.utc
        Rails.logger.warn "[MagicLink] Token expired for user: #{user.email}"
        user.update(login_token: nil, login_token_valid_until: nil)
        flash[:alert] = "Login link expired. Please request a new one."
        redirect_to new_user_session_path and return
      end
      
      # Clear the token so it can't be reused
      user.update(login_token: nil, login_token_valid_until: nil)
      
      # Sign in the user
      Rails.logger.info "[MagicLink] Signing in user: #{user.email}"
      sign_in(user)
      
      flash[:notice] = "You have been signed in successfully."
      redirect_to dashboard_path
    rescue => e
      Rails.logger.error "[MagicLink] Error processing magic link: #{e.message}"
      flash[:alert] = "Something went wrong. Please try again or contact support."
      redirect_to new_user_session_path
    end
  end
end
