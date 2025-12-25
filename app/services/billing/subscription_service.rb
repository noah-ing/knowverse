module Billing
  class SubscriptionService
    class SubscriptionError < StandardError; end

    attr_reader :organization

    def initialize(organization)
      @organization = organization
    end

    # Create a new subscription for the organization
    def create_subscription(plan, payment_method_id:)
      raise SubscriptionError, "Organization already has an active subscription" if organization.active_subscription?

      customer = organization.stripe_customer
      raise SubscriptionError, "Could not create Stripe customer" unless customer

      # Attach payment method to customer
      Stripe::PaymentMethod.attach(payment_method_id, customer: customer.id)
      Stripe::Customer.update(customer.id, invoice_settings: { default_payment_method: payment_method_id })

      # Create the subscription
      subscription_params = {
        customer: customer.id,
        items: [{ price: plan.stripe_price_id }],
        expand: ['latest_invoice.payment_intent'],
        metadata: { organization_id: organization.id, plan_name: plan.name }
      }

      # Add trial period if plan has one
      if plan.has_trial?
        subscription_params[:trial_period_days] = plan.trial_days
      end

      subscription = Stripe::Subscription.create(subscription_params)

      # Update organization
      organization.update!(
        stripe_subscription_id: subscription.id,
        plan: plan,
        subscription_status: subscription.status,
        trial_ends_at: subscription.trial_end ? Time.at(subscription.trial_end) : nil,
        current_period_end: Time.at(subscription.current_period_end)
      )

      subscription
    rescue Stripe::StripeError => e
      raise SubscriptionError, "Stripe error: #{e.message}"
    end

    # Start a trial without payment method
    def start_trial(plan)
      raise SubscriptionError, "Organization already has an active subscription" if organization.active_subscription?
      raise SubscriptionError, "Plan does not offer a trial" unless plan.has_trial?

      customer = organization.stripe_customer
      raise SubscriptionError, "Could not create Stripe customer" unless customer

      subscription = Stripe::Subscription.create(
        customer: customer.id,
        items: [{ price: plan.stripe_price_id }],
        trial_period_days: plan.trial_days,
        payment_behavior: 'default_incomplete',
        metadata: { organization_id: organization.id, plan_name: plan.name }
      )

      organization.update!(
        stripe_subscription_id: subscription.id,
        plan: plan,
        subscription_status: 'trialing',
        trial_ends_at: Time.at(subscription.trial_end),
        current_period_end: Time.at(subscription.current_period_end)
      )

      subscription
    rescue Stripe::StripeError => e
      raise SubscriptionError, "Stripe error: #{e.message}"
    end

    # Update subscription to a different plan (upgrade/downgrade)
    def update_subscription(new_plan)
      raise SubscriptionError, "No active subscription to update" unless organization.stripe_subscription_id

      subscription = Stripe::Subscription.retrieve(organization.stripe_subscription_id)

      # Update the subscription item
      Stripe::Subscription.update(
        subscription.id,
        {
          items: [{
            id: subscription.items.data[0].id,
            price: new_plan.stripe_price_id
          }],
          proration_behavior: 'create_prorations',
          metadata: { plan_name: new_plan.name }
        }
      )

      organization.update!(plan: new_plan)

      # sync_quotas_from_plan callback will update quotas

      subscription
    rescue Stripe::StripeError => e
      raise SubscriptionError, "Stripe error: #{e.message}"
    end

    # Cancel subscription (at period end by default)
    def cancel_subscription(at_period_end: true)
      raise SubscriptionError, "No active subscription to cancel" unless organization.stripe_subscription_id

      if at_period_end
        subscription = Stripe::Subscription.update(
          organization.stripe_subscription_id,
          { cancel_at_period_end: true }
        )
        organization.update!(canceled_at: Time.current)
      else
        subscription = Stripe::Subscription.cancel(organization.stripe_subscription_id)
        organization.update!(
          subscription_status: 'canceled',
          canceled_at: Time.current,
          stripe_subscription_id: nil
        )
      end

      subscription
    rescue Stripe::StripeError => e
      raise SubscriptionError, "Stripe error: #{e.message}"
    end

    # Resume a canceled subscription (before period end)
    def resume_subscription
      raise SubscriptionError, "No subscription to resume" unless organization.stripe_subscription_id
      raise SubscriptionError, "Subscription not canceled" unless organization.canceled_at.present?

      subscription = Stripe::Subscription.update(
        organization.stripe_subscription_id,
        { cancel_at_period_end: false }
      )

      organization.update!(canceled_at: nil)

      subscription
    rescue Stripe::StripeError => e
      raise SubscriptionError, "Stripe error: #{e.message}"
    end

    # Get billing portal URL for customer
    def billing_portal_url(return_url:)
      customer = organization.stripe_customer
      raise SubscriptionError, "No Stripe customer found" unless customer

      session = Stripe::BillingPortal::Session.create(
        customer: customer.id,
        return_url: return_url
      )

      session.url
    rescue Stripe::StripeError => e
      raise SubscriptionError, "Stripe error: #{e.message}"
    end

    # Create checkout session for new subscription
    def create_checkout_session(plan, success_url:, cancel_url:)
      customer = organization.stripe_customer
      raise SubscriptionError, "Could not create Stripe customer" unless customer

      session_params = {
        customer: customer.id,
        mode: 'subscription',
        line_items: [{ price: plan.stripe_price_id, quantity: 1 }],
        success_url: success_url,
        cancel_url: cancel_url,
        subscription_data: {
          metadata: { organization_id: organization.id, plan_name: plan.name }
        }
      }

      # Add trial if applicable
      if plan.has_trial? && !organization.trialing?
        session_params[:subscription_data][:trial_period_days] = plan.trial_days
      end

      Stripe::Checkout::Session.create(session_params)
    rescue Stripe::StripeError => e
      raise SubscriptionError, "Stripe error: #{e.message}"
    end
  end
end
