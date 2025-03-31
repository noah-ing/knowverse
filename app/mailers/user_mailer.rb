# app/mailers/user_mailer.rb

class UserMailer < ApplicationMailer
    default from: 'no-reply@alpinedigital.io' # Must be a Resend verified sender
  
    def magic_link(user, login_token)
      @user = user
      @login_url = login_token.url
  
      mail(to: @user.email, subject: 'Your magic sign-in link')
    end
  end
  