class SsoController < ApplicationController
  before_action :find_organization, only: [:login, :initiate]

  # GET /sso - SSO organization lookup page
  def index
    # Render SSO login page where users enter their organization
  end

  # GET /sso/:org_slug - SSO login page for specific organization
  def login
    unless @organization.sso_enabled?
      redirect_to new_user_session_path, alert: 'SSO is not enabled for this organization.'
      return
    end

    @sso_config = @organization.sso_config
  end

  # POST /sso/:org_slug/initiate - Start SSO flow
  def initiate
    unless @organization.sso_enabled?
      redirect_to new_user_session_path, alert: 'SSO is not enabled for this organization.'
      return
    end

    sso_config = @organization.sso_config

    if sso_config.saml?
      redirect_to "/auth/saml/#{@organization.slug}", allow_other_host: true
    else
      redirect_to "/auth/openid_connect/#{@organization.slug}", allow_other_host: true
    end
  end

  # POST /sso/lookup - Find organization by slug or domain
  def lookup
    query = params[:query].to_s.strip.downcase

    # Try to find by slug
    organization = Organization.find_by(slug: query)

    # If not found, try to find by email domain
    if organization.nil? && query.include?('@')
      domain = query.split('@').last
      sso_config = SsoConfig.enabled.find do |config|
        config.domain_allowlist.map(&:downcase).include?(domain)
      end
      organization = sso_config&.organization
    end

    if organization&.sso_enabled?
      redirect_to sso_login_path(organization.slug)
    else
      redirect_to sso_path, alert: 'No SSO-enabled organization found. Please check the organization name or contact your administrator.'
    end
  end

  private

  def find_organization
    @organization = Organization.find_by!(slug: params[:org_slug])
  rescue ActiveRecord::RecordNotFound
    redirect_to sso_path, alert: 'Organization not found.'
  end
end
