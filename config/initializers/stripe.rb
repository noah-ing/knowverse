Rails.configuration.stripe = {
  publishable_key: ENV['STRIPE_PUBLISHABLE_KEY'],
  secret_key: ENV['STRIPE_SECRET_KEY'],
  signing_secret: ENV['STRIPE_WEBHOOK_SECRET']
}

Stripe.api_key = Rails.configuration.stripe[:secret_key]
Stripe.api_version = '2023-10-16' # Using a specific API version for stability
