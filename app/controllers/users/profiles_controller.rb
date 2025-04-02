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
      if @user.update(user_params)
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
