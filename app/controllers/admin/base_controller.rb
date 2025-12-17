 class Admin::BaseController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!
  before_action :require_admin

  private

  def require_admin
    unless current_user.admin?
      flash[:alert] = "You don't have permission to access this area."
      redirect_to root_path
    end
  end
end
