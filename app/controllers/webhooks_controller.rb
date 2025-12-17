class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def stripe
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = Rails.configuration.stripe[:signing_secret]

    begin
      event = Stripe::Webhook.construct_event(
        payload, sig_header, endpoint_secret
      )
    rescue JSON::ParserError => e
      # Invalid payload
      render json: {error: e.message}, status: 400
      return
    rescue Stripe::SignatureVerificationError => e
      # Invalid signature
      render json: {error: e.message}, status: 400
      return
    end

    # Handle the event
    case event.type
    when 'customer.subscription.created'
      handle_subscription_created(event.data.object)
    when 'customer.subscription.updated'
      handle_subscription_updated(event.data.object)
    when 'customer.subscription.deleted'
      handle_subscription_deleted(event.data.object)
    when 'invoice.payment_succeeded'
      handle_payment_succeeded(event.data.object)
    when 'invoice.payment_failed'
      handle_payment_failed(event.data.object)
    end

    render json: {status: 'success'}
  end

  private

  def handle_subscription_created(subscription)
    user = find_user_by_customer(subscription.customer)
    return unless user

    user.update(
      stripe_subscription_id: subscription.id,
      subscription_status: subscription.status
    )

    # Handle trial period if applicable
    if subscription.trial_end
      user.update(trial_ends_at: Time.at(subscription.trial_end))
    end
  end

  def handle_subscription_updated(subscription)
    user = find_user_by_customer(subscription.customer)
    return unless user

    user.update(subscription_status: subscription.status)

    # Handle trial period updates if applicable
    if subscription.trial_end
      user.update(trial_ends_at: Time.at(subscription.trial_end))
    end
  end

  def handle_subscription_deleted(subscription)
    user = find_user_by_customer(subscription.customer)
    return unless user

    user.update(
      subscription_status: 'canceled',
      stripe_subscription_id: nil
    )
  end

  def handle_payment_succeeded(invoice)
    user = find_user_by_customer(invoice.customer)
    return unless user

    if user.subscription_status == 'past_due'
      user.update(subscription_status: 'active')
    end

    # Could notify user of successful payment if desired
  end

  def handle_payment_failed(invoice)
    user = find_user_by_customer(invoice.customer)
    return unless user

    user.update(subscription_status: 'past_due')

    # Notify user of payment failure - could send an email here
  end

  def find_user_by_customer(customer_id)
    User.find_by(stripe_customer_id: customer_id)
  end
end
