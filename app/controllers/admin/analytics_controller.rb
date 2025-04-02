class Admin::AnalyticsController < Admin::BaseController
  def index
    @visits_count = Ahoy::Visit.count
    @events_count = Ahoy::Event.count
    @users_count = User.count
    
    # Get recent visits
    @recent_visits = Ahoy::Visit.order(started_at: :desc).includes(:user).limit(10)
    
    # Get page view counts
    @page_views = Ahoy::Event.where(name: '$view').group(:properties).count
    
    # Get the top referring domains
    @top_referrers = Ahoy::Visit.group(:referring_domain).count.sort_by { |_domain, count| -count }.first(5)
    
    # Get visit counts per day for the past 30 days
    @visits_per_day = Ahoy::Visit.where('started_at >= ?', 30.days.ago)
                               .group_by_day(:started_at)
                               .count
    
    # Get events per day for the past 30 days
    @events_per_day = Ahoy::Event.where('time >= ?', 30.days.ago)
                              .group_by_day(:time)
                              .count
    
    # Get subscription metrics
    @subscription_events = Ahoy::Event.where(name: 'subscription_changed').order(time: :desc).limit(10)
    @subscription_counts = {}
    User::SUBSCRIPTION_STATUSES.each do |status|
      @subscription_counts[status] = User.where(subscription_status: status).count
    end
    
    # Get profile update metrics
    @profile_updates = Ahoy::Event.where(name: 'profile_updated').order(time: :desc).limit(10)
    
    # Get magic link login metrics
    @magic_link_logins = Ahoy::Event.where(name: 'magic_link_login').order(time: :desc).limit(10)
  end
  
  def user_activity
    @user = User.find(params[:id])
    @visits = @user.visits.order(started_at: :desc).page(params[:page]).per(20)
    @events = @user.events.order(time: :desc).page(params[:page]).per(20)
  end
  
  def events
    @events = Ahoy::Event.order(time: :desc).page(params[:page]).per(20)
    
    if params[:name].present?
      @events = @events.where(name: params[:name])
    end
    
    @event_names = Ahoy::Event.distinct.pluck(:name)
  end
end
