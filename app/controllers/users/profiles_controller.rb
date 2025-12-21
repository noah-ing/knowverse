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
      old_blob_id = @user.avatar.attached? ? @user.avatar.blob_id : nil

      if @user.update(user_params)
        # Track profile update with Ahoy
        changes = {}
        changes[:name_changed] = true if old_name != @user.name
        changes[:avatar_added] = true if !had_avatar && @user.avatar.attached?
        changes[:avatar_changed] = true if had_avatar && @user.avatar.attached? && @user.avatar.blob_id != old_blob_id
        changes[:avatar_removed] = true if had_avatar && !@user.avatar.attached?

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
