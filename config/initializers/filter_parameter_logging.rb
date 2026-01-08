# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  # Authentication & passwords
  :passw, :password, :password_confirmation,
  # Personal identifiable information
  :email, :ssn, :social_security,
  # Tokens & secrets
  :secret, :token, :_key, :api_key, :auth_token, :login_token, :access_token, :refresh_token,
  :bearer, :jwt, :session_id, :reset_password_token, :unlock_token,
  # Cryptographic data
  :crypt, :salt, :certificate, :private_key, :signing_key,
  # Payment & financial
  :otp, :cvv, :cvc, :card_number, :credit_card, :account_number, :routing_number,
  # OAuth & SSO
  :client_secret, :authorization_code, :oauth_token,
  # Rails-specific
  :authenticity_token
]
