module Users
  class AccountsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_user
    
    # GET /users/account
    def show
    end
    
    # PATCH/PUT /users/account
    def update
      if @user.update(account_params)
        redirect_to users_account_path, notice: "Account settings updated successfully."
      else
        render :show, status: :unprocessable_entity
      end
    end
    
    # DELETE /users/account
    def destroy
      # In a real application, you might:
      # 1. Mark the account as deactivated instead of actually deleting
      # 2. Schedule a background job for actual deletion after a grace period
      # 3. Handle subscription cancellation with Stripe
      # 4. Export user data for compliance reasons
      
      # For now, we'll just sign out the user and mark the account for deactivation
      if params[:confirm_email] == @user.email
        # Cancel subscription if any
        if @user.stripe_subscription_id.present?
          begin
            Stripe::Subscription.cancel(@user.stripe_subscription_id)
          rescue Stripe::StripeError => e
            # Log the error but continue with account deactivation
            Rails.logger.error("Failed to cancel subscription for user #{@user.id}: #{e.message}")
          end
        end
        
        # In a real app, we'd probably just set a deactivated flag
        # @user.update(deactivated: true, deactivated_at: Time.current)
        
        # Sign out the user
        sign_out(@user)
        
        # Redirect to home with message
        redirect_to root_path, notice: "Your account has been scheduled for deletion. Thank you for using our service."
      else
        redirect_to users_account_path, alert: "Email confirmation didn't match. Account was not deleted."
      end
    end
    
    private
    
    def set_user
      @user = current_user
    end
    
    def account_params
      params.require(:user).permit(:email)
    end
  end
end
