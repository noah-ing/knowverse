module Organizations
  class SubscriptionsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_organization
    before_action :ensure_organization_owner
    before_action :set_subscription_service

    # GET /organizations/:organization_id/subscription
    def show
      @quota_enforcer = Billing::QuotaEnforcer.new(@organization)
      @quota_summary = @quota_enforcer.quota_summary
      @billing_events = @organization.billing_events.recent.limit(20)
      @plans = Plan.active.monthly.ordered
    end

    # GET /organizations/:organization_id/subscription/new
    def new
      @plans = Plan.active.monthly.ordered
      @selected_plan = Plan.find_by(id: params[:plan_id]) || @plans.reject(&:free?).first
    end

    # POST /organizations/:organization_id/subscription
    def create
      plan = Plan.find(params[:plan_id])

      if plan.free?
        # For free plan, just assign without payment
        @organization.update!(plan: plan, subscription_status: 'active')
        redirect_to organization_subscription_path(@organization),
                    notice: "You're now on the #{plan.name} plan."
        return
      end

      # Create Stripe Checkout session for paid plans
      begin
        session = @subscription_service.create_checkout_session(
          plan,
          success_url: organization_subscription_url(@organization, checkout: 'success'),
          cancel_url: organization_subscription_url(@organization, checkout: 'canceled')
        )
        redirect_to session.url, allow_other_host: true
      rescue Billing::SubscriptionService::SubscriptionError => e
        redirect_to new_organization_subscription_path(@organization),
                    alert: "Could not start checkout: #{e.message}"
      end
    end

    # PATCH /organizations/:organization_id/subscription
    def update
      new_plan = Plan.find(params[:plan_id])

      if new_plan.free?
        # Downgrade to free - cancel subscription
        @subscription_service.cancel_subscription(at_period_end: false) if @organization.stripe_subscription_id
        @organization.update!(plan: new_plan, subscription_status: 'active')
        redirect_to organization_subscription_path(@organization),
                    notice: "You've been downgraded to the #{new_plan.name} plan."
        return
      end

      begin
        if @organization.stripe_subscription_id
          @subscription_service.update_subscription(new_plan)
          redirect_to organization_subscription_path(@organization),
                      notice: "You've been upgraded to the #{new_plan.name} plan."
        else
          # No existing subscription, redirect to checkout
          redirect_to new_organization_subscription_path(@organization, plan_id: new_plan.id)
        end
      rescue Billing::SubscriptionService::SubscriptionError => e
        redirect_to organization_subscription_path(@organization),
                    alert: "Could not update subscription: #{e.message}"
      end
    end

    # PATCH /organizations/:organization_id/subscription/cancel
    def cancel
      begin
        @subscription_service.cancel_subscription(at_period_end: true)
        redirect_to organization_subscription_path(@organization),
                    notice: "Your subscription will be canceled at the end of the billing period."
      rescue Billing::SubscriptionService::SubscriptionError => e
        redirect_to organization_subscription_path(@organization),
                    alert: "Could not cancel subscription: #{e.message}"
      end
    end

    # PATCH /organizations/:organization_id/subscription/resume
    def resume
      begin
        @subscription_service.resume_subscription
        redirect_to organization_subscription_path(@organization),
                    notice: "Your subscription has been resumed."
      rescue Billing::SubscriptionService::SubscriptionError => e
        redirect_to organization_subscription_path(@organization),
                    alert: "Could not resume subscription: #{e.message}"
      end
    end

    # POST /organizations/:organization_id/subscription/start_trial
    def start_trial
      plan = Plan.find(params[:plan_id])

      unless plan.has_trial?
        redirect_to organization_subscription_path(@organization),
                    alert: "This plan does not offer a trial period."
        return
      end

      begin
        @subscription_service.start_trial(plan)
        redirect_to organization_subscription_path(@organization),
                    notice: "Your #{plan.trial_days}-day trial has started!"
      rescue Billing::SubscriptionService::SubscriptionError => e
        redirect_to organization_subscription_path(@organization),
                    alert: "Could not start trial: #{e.message}"
      end
    end

    # GET /organizations/:organization_id/subscription/portal
    def portal
      begin
        portal_url = @subscription_service.billing_portal_url(
          return_url: organization_subscription_url(@organization)
        )
        redirect_to portal_url, allow_other_host: true
      rescue Billing::SubscriptionService::SubscriptionError => e
        redirect_to organization_subscription_path(@organization),
                    alert: "Could not open billing portal: #{e.message}"
      end
    end

    private

    def set_organization
      @organization = Organization.find(params[:organization_id])
    end

    def ensure_organization_owner
      role = @organization.organization_users.find_by(user: current_user)&.role
      unless role == 'owner'
        redirect_to organization_path(@organization),
                    alert: 'Only the organization owner can manage billing.'
      end
    end

    def set_subscription_service
      @subscription_service = Billing::SubscriptionService.new(@organization)
    end
  end
end
