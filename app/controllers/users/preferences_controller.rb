module Users
  class PreferencesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_user
    
    # GET /users/preferences
    def show
    end
    
    # PATCH/PUT /users/preferences
    def update
      # Handle preferences update - expecting a hash of preference toggles
      if params[:preferences]
        params[:preferences].each do |pref_type, enabled|
          # Convert "1"/"0" strings from form checkboxes to boolean values
          enabled_bool = enabled == "1"
          # Only update if the value changed
          if @user.notification_enabled?(pref_type) != enabled_bool
            @user.notification_preferences[pref_type.to_sym] = enabled_bool
          end
        end
        
        if @user.save
          redirect_to users_preferences_path, notice: "Notification preferences updated successfully."
        else
          render :show, status: :unprocessable_entity
        end
      else
        redirect_to users_preferences_path, alert: "No preference changes provided."
      end
    end
    
    private
    
    def set_user
      @user = current_user
    end
  end
end
