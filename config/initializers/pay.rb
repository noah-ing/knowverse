Pay.setup do |config|
  # For use in the receipt/refund/renewal mailers
  config.business_name = "Gold SaaS"
  config.application_name = "Gold SaaS Boilerplate"
  config.support_email = "support@example.com"

  # Use Stripe as the primary payment processor
  config.enabled_processors = [:stripe]
  
  # Automatically sync and update data with the payment processor
  config.automount_routes = true
  config.routes_path = "/billing"
end
