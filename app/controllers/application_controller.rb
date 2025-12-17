class ApplicationController < ActionController::Base
  # Check if a database table exists
  def table_exists?(table_name)
    ActiveRecord::Base.connection.table_exists?(table_name)
  rescue
    false
  end
  helper_method :current_organization, :ensure_user_authenticated, :user_authenticated?
  
  # Find the current user's organization
  def current_organization
    return nil unless user_authenticated?
    
    @current_organization ||= begin
      # Try to find a default organization for the user
      if current_user && current_user.respond_to?(:organizations)
        # Check for a default organization if that relationship exists
        default_org = current_user.organizations.find_by(default: true) if Organization.column_names.include?('default')
        
        # Fall back to the first organization if no default
        default_org || current_user.organizations.first
      else
        nil
      end
    end
  end
  
  # Ensure user is authenticated with resilient fallback
  def ensure_user_authenticated
    # Primary check using Devise
    if respond_to?(:authenticate_user!)
      authenticate_user!
    else
      # Fallback authentication check
      unless user_authenticated?
        flash[:alert] = "You need to sign in before continuing."
        redirect_to new_user_session_path if defined?(new_user_session_path)
      end
    end
  end
  
  # Resilient method to check if user is authenticated
  def user_authenticated?
    # Perform multiple checks to ensure accurate authentication detection
    is_authenticated = false
    
    # Primary check - Devise user_signed_in?
    is_authenticated ||= user_signed_in? if respond_to?(:user_signed_in?)
    
    # Secondary check - current_user presence
    is_authenticated ||= !current_user.nil? if respond_to?(:current_user)
    
    # Tertiary check - session based
    is_authenticated ||= !session[:user_id].nil? if session && session[:user_id]
    
    # User class ID check
    if !is_authenticated && defined?(User) && respond_to?(:current_user)
      is_authenticated = User.exists?(id: current_user.id) if current_user
    end
    
    is_authenticated
  end
  
  # Skip migration check if RAILS_SKIP_MIGRATIONS is set
  if ENV["RAILS_SKIP_MIGRATIONS"] == "true"
    def self.ensure_proper_version
      # Skip migration check entirely
      yield
    end
  end
end
