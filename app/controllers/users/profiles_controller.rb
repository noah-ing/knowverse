module Users
  class ProfilesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_user

    # GET /users/profile
    def show
    end

    # GET /users/profile/edit
    def edit
    end

    # PATCH/PUT /users/profile
    def update
      old_name = @user.name
      had_avatar = @user.avatar.attached?
      
      if @user.update(user_params)
        # Track profile update with Ahoy
        changes = {}
        changes[:name_changed] = old_name != @user.name if old_name != @user.name
        changes[:avatar_added] = !had_avatar && @user.avatar.attached?
        changes[:avatar_changed] = had_avatar && @user.avatar.attached? && @user.avatar.blob_id != @user.avatar_before_last_save&.blob_id
        changes[:avatar_removed] = had_avatar && !@user.avatar.attached?
        
        ahoy.track "profile_updated", 
          user_id: @user.id,
          changes: changes
        
        redirect_to users_profile_path, notice: "Profile was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_user
      @user = current_user
    end

    def user_params
      params.require(:user).permit(:name, :avatar)
    end
  end
end
