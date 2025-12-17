# Ensure the resend gem is loaded
require 'resend'

# Set the API key
Resend.api_key = ENV.fetch("RESEND_API_KEY")

# Log information about the configuration for debugging
Rails.logger.info "[Resend] Initialized with API key: #{Resend.api_key.present? ? 'Present (first 5 chars: ' + Resend.api_key.to_s.first(5) + ')' : 'Missing'}"

# Check if ActionMailer is configured to use Resend
if defined?(ActionMailer::Base) && ActionMailer::Base.delivery_methods.key?(:resend)
  Rails.logger.info "[Resend] ActionMailer delivery method :resend is available"
else
  Rails.logger.warn "[Resend] ActionMailer delivery method :resend is NOT available! Email sending may fail."
  
  # The resend gem's delivery method may not have registered with ActionMailer
  # If it's not registered, this is a workaround to manually register it
  if defined?(ActionMailer::Base) && !ActionMailer::Base.delivery_methods.key?(:resend)
    require 'resend/delivery_method'
    ActionMailer::Base.add_delivery_method :resend, Resend::DeliveryMethod
    Rails.logger.info "[Resend] Manually registered Resend::DeliveryMethod with ActionMailer"
  end
end
