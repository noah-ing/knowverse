module Users
  class UsagesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_user
    
    # GET /users/usage
    def show
      # In a real app, we would fetch usage statistics from various sources
      # For now, we'll simulate some basic usage data
      @current_period_start = 30.days.ago.beginning_of_day
      @current_period_end = Time.current.end_of_day
      
      # Fake usage data for demonstration
      @usage_stats = {
        api_calls: {
          current: rand(100..500),
          limit: 1000,
          percent: rand(10..50)
        },
        storage: {
          current: rand(50..200),
          limit: 500,
          percent: rand(10..40),
          unit: "MB"
        },
        features_used: [
          { name: "Magic Link Auth", usage_count: rand(5..20) },
          { name: "Profile Management", usage_count: rand(1..10) },
          { name: "Notification Settings", usage_count: rand(1..5) }
        ]
      }
      
      # If the user has a subscription, show the subscription details
      if @user.stripe_subscription_id.present?
        begin
          # In a real app, we would fetch the actual subscription from Stripe
          # For demonstration, we'll use hardcoded values
          @next_billing_date = Time.current + rand(1..28).days
          @subscription_plan = @user.current_plan&.name || "Basic Plan"
        rescue => e
          Rails.logger.error("Failed to fetch subscription for user #{@user.id}: #{e.message}")
        end
      end
    end
    
    private
    
    def set_user
      @user = current_user
    end
  end
end
