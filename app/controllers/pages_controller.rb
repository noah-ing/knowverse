class PagesController < ApplicationController
  # Allow access to static pages without authentication
  skip_before_action :authenticate_user!, only: [:privacy, :terms, :cookies, :documentation], raise: false

  def privacy
  end

  def terms
  end

  def cookies
  end

  def documentation
  end
end
