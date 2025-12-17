StripeEvent.signing_secret = ENV['STRIPE_WEBHOOK_SECRET']

StripeEvent.configure do |events|
  # Customer subscription events
  events.subscribe 'customer.subscription.created' do |event|
    # Handle subscription creation
    subscription = event.data.object
    user = Pay::Customer.find_by(processor_id: subscription.customer)&.owner
    # Additional subscription creation handling
  end

  events.subscribe 'customer.subscription.updated' do |event|
    # Handle subscription updates
    subscription = event.data.object
    user = Pay::Customer.find_by(processor_id: subscription.customer)&.owner
    # Additional subscription update handling
  end

  events.subscribe 'customer.subscription.deleted' do |event|
    # Handle subscription cancellation
    subscription = event.data.object
    user = Pay::Customer.find_by(processor_id: subscription.customer)&.owner
    # Additional subscription cancellation handling
  end

  # Invoice events
  events.subscribe 'invoice.payment_succeeded' do |event|
    # Handle successful payments
    invoice = event.data.object
    user = Pay::Customer.find_by(processor_id: invoice.customer)&.owner
    # Additional payment success handling
  end

  events.subscribe 'invoice.payment_failed' do |event|
    # Handle failed payments
    invoice = event.data.object
    user = Pay::Customer.find_by(processor_id: invoice.customer)&.owner
    # Notify user of payment failure
  end

  # Payment method events
  events.subscribe 'payment_method.attached' do |event|
    # Handle new payment method
    payment_method = event.data.object
    user = Pay::Customer.find_by(processor_id: payment_method.customer)&.owner
    # Additional payment method handling
  end
end
