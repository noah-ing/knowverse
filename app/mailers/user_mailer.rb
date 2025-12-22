class UserMailer < ApplicationMailer
  def magic_link(user, login_token)
    @user = user
    @login_url = login_token.url

    mail(
      to: @user.email,
      from: ENV.fetch('MAILER_FROM', 'no-reply@knowverse.app'),
      subject: "Your Magic Login Link"
    )
  end
end
