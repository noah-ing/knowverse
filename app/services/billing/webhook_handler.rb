module Billing
  class WebhookHandler
    class WebhookError < StandardError; end

    HANDLED_EVENTS = %w[
      customer.subscription.created
      customer.subscription.updated
      customer.subscription.deleted
      invoice.payment_succeeded
      invoice.payment_failed
      customer.subscription.trial_will_end
    ].freeze

    attr_reader :event

    def initialize(event)
      @event = event
    end

    def process!
      return { status: :ignored, message: "Event type not handled" } unless HANDLED_EVENTS.include?(event.type)

      organization = find_organization
      return { status: :ignored, message: "Organization not found" } unless organization

      # Check for idempotency
      if BillingEvent.already_processed?(event.id)
        return { status: :skipped, message: "Event already processed" }
      end

      # Record the event
      billing_event = BillingEvent.record_event(organization, event)

      begin
        result = handle_event(organization)
        billing_event.mark_processed!
        { status: :processed, result: result }
      rescue StandardError => e
        billing_event.mark_failed!(e)
        raise WebhookError, "Failed to process #{event.type}: #{e.message}"
      end
    end

    private

    def find_organization
      case event.type
      when /^customer\.subscription\./
        find_by_subscription
      when /^invoice\./
        find_by_customer
      else
        nil
      end
    end

    def find_by_subscription
      subscription_id = event.data.object.id
      Organization.find_by(stripe_subscription_id: subscription_id) ||
        find_by_metadata(event.data.object.metadata)
    end

    def find_by_customer
      customer_id = event.data.object.customer
      Organization.find_by(stripe_customer_id: customer_id)
    end

    def find_by_metadata(metadata)
      return nil unless metadata&.organization_id
      Organization.find_by(id: metadata.organization_id)
    end

    def handle_event(organization)
      case event.type
      when "customer.subscription.created"
        handle_subscription_created(organization)
      when "customer.subscription.updated"
        handle_subscription_updated(organization)
      when "customer.subscription.deleted"
        handle_subscription_deleted(organization)
      when "invoice.payment_succeeded"
        handle_payment_succeeded(organization)
      when "invoice.payment_failed"
        handle_payment_failed(organization)
      when "customer.subscription.trial_will_end"
        handle_trial_ending(organization)
      end
    end

    def handle_subscription_created(organization)
      subscription = event.data.object

      organization.update!(
        stripe_subscription_id: subscription.id,
        subscription_status: subscription.status,
        trial_ends_at: subscription.trial_end ? Time.at(subscription.trial_end) : nil,
        current_period_end: Time.at(subscription.current_period_end)
      )

      # Find and set plan from price
      if subscription.items.data.first
        price_id = subscription.items.data.first.price.id
        plan = Plan.find_by(stripe_price_id: price_id)
        organization.update!(plan: plan) if plan
      end

      { action: :subscription_created, status: subscription.status }
    end

    def handle_subscription_updated(organization)
      subscription = event.data.object
      previous_status = organization.subscription_status

      organization.update!(
        subscription_status: subscription.status,
        trial_ends_at: subscription.trial_end ? Time.at(subscription.trial_end) : nil,
        current_period_end: Time.at(subscription.current_period_end),
        canceled_at: subscription.cancel_at_period_end ? Time.current : nil
      )

      # Check for plan change
      if subscription.items.data.first
        price_id = subscription.items.data.first.price.id
        new_plan = Plan.find_by(stripe_price_id: price_id)
        if new_plan && organization.plan_id != new_plan.id
          organization.update!(plan: new_plan)
        end
      end

      { action: :subscription_updated, from: previous_status, to: subscription.status }
    end

    def handle_subscription_deleted(organization)
      organization.update!(
        subscription_status: 'canceled',
        stripe_subscription_id: nil,
        canceled_at: Time.current
      )

      # Downgrade to free plan or remove plan
      free_plan = Plan.find_by(amount: 0)
      if free_plan
        organization.update!(plan: free_plan)
      else
        organization.update!(plan: nil)
      end

      { action: :subscription_canceled }
    end

    def handle_payment_succeeded(organization)
      invoice = event.data.object

      # Update period end if this is a subscription invoice
      if invoice.subscription
        subscription = Stripe::Subscription.retrieve(invoice.subscription)
        organization.update!(
          subscription_status: 'active',
          current_period_end: Time.at(subscription.current_period_end)
        )
      end

      { action: :payment_succeeded, amount: invoice.amount_paid }
    end

    def handle_payment_failed(organization)
      invoice = event.data.object

      organization.update!(subscription_status: 'past_due')

      # Could trigger email notification here
      # BillingMailer.payment_failed(organization, invoice).deliver_later

      { action: :payment_failed, amount: invoice.amount_due }
    end

    def handle_trial_ending(organization)
      subscription = event.data.object

      organization.update!(
        trial_ends_at: Time.at(subscription.trial_end)
      )

      # Could trigger email notification here
      # BillingMailer.trial_ending(organization).deliver_later

      { action: :trial_ending, ends_at: Time.at(subscription.trial_end) }
    end
  end
end
