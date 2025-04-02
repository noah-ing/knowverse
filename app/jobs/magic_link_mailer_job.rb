class MagicLinkMailerJob < ApplicationJob
  queue_as :default
  
  def perform(user_id, token, url, expires_at)
    user = User.find_by(id: user_id)
    
    unless user
      Rails.logger.error "[MagicLinkJob] User not found: #{user_id}"
      return
    end
    
    # Create a login token object that the mailer expects
    require 'ostruct'
    login_token = OpenStruct.new(
      url: url,
      token: token,
      created_at: Time.now,
      expires_at: expires_at
    )
    
    Rails.logger.info "[MagicLinkJob] Sending magic link email to: #{user.email}"
    UserMailer.magic_link(user, login_token).deliver_now
  end
end
