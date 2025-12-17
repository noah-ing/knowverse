module Subscriptions
  class SubscriptionsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_subscription, only: [:show, :cancel, :resume]
    
    def show
      # Show subscription details
    end
    
    def cancel
      begin
        # Cancel the subscription at period end
        Stripe::Subscription.update(
          current_user.stripe_subscription_id,
          { cancel_at_period_end: true }
        )
        
        # Update the subscription status
        current_user.update(subscription_status: 'canceled')
        
        # Track subscription cancellation
        ahoy.track "subscription_changed", 
          user_id: current_user.id, 
          action: "canceled", 
          plan: current_user.current_plan&.name,
          subscription_id: current_user.stripe_subscription_id
        
        flash[:notice] = "Your subscription has been canceled. You will still have access until the end of your billing period."
        redirect_to dashboard_path
      rescue Stripe::StripeError => e
        flash[:alert] = e.message
        redirect_to dashboard_path
      end
    end
    
    def resume
      begin
        # Resume a canceled subscription if it's not expired
        Stripe::Subscription.update(
          current_user.stripe_subscription_id,
          { cancel_at_period_end: false }
        )
        
        # Update the subscription status
        current_user.update(subscription_status: 'active')
        
        # Track subscription resumption
        ahoy.track "subscription_changed", 
          user_id: current_user.id, 
          action: "resumed", 
          plan: current_user.current_plan&.name,
          subscription_id: current_user.stripe_subscription_id
        
        flash[:notice] = "Your subscription has been resumed."
        redirect_to dashboard_path
      rescue Stripe::StripeError => e
        flash[:alert] = e.message
        redirect_to dashboard_path
      end
    end
    
    private
    
    def set_subscription
      unless current_user.stripe_subscription_id.present?
        flash[:alert] = "You don't have an active subscription."
        redirect_to subscriptions_plans_path
      end
      
      begin
        @subscription = Stripe::Subscription.retrieve(current_user.stripe_subscription_id)
      rescue Stripe::StripeError => e
        flash[:alert] = e.message
        redirect_to dashboard_path
      end
    end
  end
end
