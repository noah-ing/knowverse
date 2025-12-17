module Subscriptions
  class PlansController < ApplicationController
    before_action :authenticate_user!
    
    def index
      @plans = Plan.active.order(amount: :asc)
      @current_plan = current_user.current_plan
    end
    
    def show
      @plan = Plan.find(params[:id])
    end
    
    def create
      @plan = Plan.find(params[:plan_id])
      
      # If the user already has a subscription
      if current_user.stripe_subscription_id.present?
        update_subscription
      else
        create_subscription
      end
    end
    
    private
    
    def create_subscription
      # Create the customer in Stripe if not exists
      customer = current_user.stripe_customer
      
      # Create a subscription with the selected plan
      subscription = Stripe::Subscription.create({
        customer: customer.id,
        items: [{ price: @plan.stripe_price_id }],
        expand: ['latest_invoice.payment_intent']
      })
      
      # Update the user record with subscription info
      current_user.update(
        stripe_subscription_id: subscription.id,
        subscription_status: subscription.status
      )
      
      # Handle trial period if applicable
      if subscription.trial_end
        current_user.update(trial_ends_at: Time.at(subscription.trial_end))
      end
      
      # Track subscription creation with Ahoy
      ahoy.track "subscription_changed", 
        user_id: current_user.id, 
        action: "subscribed",
        plan: @plan.name,
        plan_id: @plan.id,
        subscription_id: subscription.id,
        amount: @plan.amount,
        interval: @plan.interval,
        status: subscription.status,
        has_trial: subscription.trial_end.present?
      
      flash[:notice] = "You have successfully subscribed to the #{@plan.name} plan!"
      redirect_to dashboard_path
    rescue Stripe::CardError => e
      flash[:alert] = e.message
      redirect_to subscriptions_plans_path
    end
    
    def update_subscription
      # Update existing subscription in Stripe
      subscription = Stripe::Subscription.retrieve(current_user.stripe_subscription_id)
      
      updated_subscription = Stripe::Subscription.update(
        subscription.id,
        {
          cancel_at_period_end: false,
          proration_behavior: 'create_prorations',
          items: [
            {
              id: subscription.items.data[0].id,
              price: @plan.stripe_price_id,
            },
          ],
        }
      )
      
      # Track plan change with Ahoy
      ahoy.track "subscription_changed", 
        user_id: current_user.id, 
        action: "changed_plan",
        previous_plan: current_user.current_plan&.name,
        new_plan: @plan.name,
        plan_id: @plan.id,
        subscription_id: subscription.id,
        amount: @plan.amount,
        interval: @plan.interval
      
      flash[:notice] = "Your subscription has been updated to the #{@plan.name} plan!"
      redirect_to dashboard_path
    rescue Stripe::CardError => e
      flash[:alert] = e.message
      redirect_to subscriptions_plans_path
    end
  end
end
