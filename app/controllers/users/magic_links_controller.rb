# app/controllers/users/magic_links_controller.rb

module Users
    class MagicLinksController < ApplicationController
      def create
        user = User.find_by(email: params[:email])
  
        if user.present?
          Rails.logger.info "[MagicLink] Creating login token for #{user.email}"
          login_token = Devise::Passwordless::LoginToken.create(resource: user)
  
          Rails.logger.info "[MagicLink] Sending email via Resend..."
          UserMailer.magic_link(user, login_token).deliver_now
  
          flash[:notice] = "Magic login link sent to #{user.email}."
        else
          flash[:alert] = "No user found with that email address."
        end
  
        redirect_to root_path
      end
    end
  end
  