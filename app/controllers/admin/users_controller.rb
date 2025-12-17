class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [:show, :edit, :update, :update_subscription, :deactivate, :reactivate, :send_magic_link]
  before_action :set_plans, only: [:show, :edit, :update, :update_subscription]

  def index
    @users = User.all.order(created_at: :desc).page(params[:page]).per(15)
  end

  def search
    if params[:query].present?
      @users = User.where("email ILIKE ?", "%#{params[:query]}%")
                   .order(created_at: :desc)
                   .page(params[:page]).per(15)
    else
      @users = User.all.order(created_at: :desc).page(params[:page]).per(15)
    end
    
    render :index
  end

  def show
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to admin_user_path(@user), notice: "User was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def update_subscription
    plan = Plan.find(params[:plan_id])
    
    # Logic to update the user's subscription through Stripe
    # This is a simplified version - in a real implementation, you would use the Stripe API
    begin
      # If there's an existing subscription, update it
      if @user.stripe_subscription_id.present?
        # Update the subscription in Stripe (simplified)
        @user.update(
          stripe_subscription_id: plan.stripe_price_id,
          subscription_status: 'active',
          trial_ends_at: nil
        )
      else
        # Create a new subscription in Stripe (simplified)
        @user.update(
          stripe_subscription_id: plan.stripe_price_id,
          subscription_status: 'active',
          trial_ends_at: nil
        )
      end
      
      redirect_to admin_user_path(@user), notice: "Subscription updated to #{plan.name} plan."
    rescue => e
      redirect_to admin_user_path(@user), alert: "Failed to update subscription: #{e.message}"
    end
  end

  def deactivate
    @user.update(subscription_status: 'canceled')
    redirect_to admin_user_path(@user), notice: "User account deactivated."
  end

  def reactivate
    @user.update(subscription_status: 'active')
    redirect_to admin_user_path(@user), notice: "User account reactivated."
  end

  def send_magic_link
    MagicLinkMailerJob.perform_later(@user.id)
    redirect_to admin_user_path(@user), notice: "Magic link sent to #{@user.email}."
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def set_plans
    @plans = Plan.all.order(:price)
  end

  def user_params
    params.require(:user).permit(:email, :admin)
  end
end
