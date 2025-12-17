class Admin::DashboardController < Admin::BaseController
  def index
    @total_users = User.count
    @active_subscriptions = User.where(subscription_status: 'active').count
    @trialing_users = User.where(subscription_status: 'trialing').count
    @past_due_users = User.where(subscription_status: 'past_due').count
  end
end
