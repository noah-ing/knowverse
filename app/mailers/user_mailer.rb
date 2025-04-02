class UserMailer < ApplicationMailer
  def magic_link(user, login_token)
    @user = user
    @login_url = login_token.url

    mail(
      to: @user.email,
      from: "no-reply@alpinedigital.io", # use your verified domain
      subject: "Your Magic Login Link"
    )
  end
end
