class SsoConfigsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :authorize_admin!
  before_action :set_sso_config, only: [:show, :edit, :update, :destroy, :test]

  def show
    # Display current SSO configuration
  end

  def new
    @sso_config = @organization.build_sso_config
  end

  def create
    @sso_config = @organization.build_sso_config(sso_config_params)

    if @sso_config.save
      redirect_to organization_sso_config_path(@organization),
        notice: 'SSO configuration created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @sso_config.update(sso_config_params)
      redirect_to organization_sso_config_path(@organization),
        notice: 'SSO configuration updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @sso_config.destroy
    redirect_to organization_path(@organization),
      notice: 'SSO configuration removed.'
  end

  def test
    # Test SSO configuration without logging in
    if @sso_config.ready?
      redirect_to sso_login_path(@organization.slug), allow_other_host: true
    else
      redirect_to organization_sso_config_path(@organization),
        alert: 'SSO configuration is incomplete. Please fill in all required fields.'
    end
  end

  private

  def set_organization
    @organization = current_user.organizations.find_by!(slug: params[:organization_id])
  end

  def set_sso_config
    @sso_config = @organization.sso_config || @organization.build_sso_config
  end

  def authorize_admin!
    org_user = @organization.organization_users.find_by(user: current_user)
    unless org_user&.role.in?(%w[owner admin])
      redirect_to organization_path(@organization), alert: 'Only organization owners and admins can manage SSO.'
    end
  end

  def sso_config_params
    params.require(:sso_config).permit(
      :provider_type,
      :enabled,
      # SAML fields
      :idp_metadata_url,
      :idp_sso_target_url,
      :idp_cert,
      :idp_cert_fingerprint,
      :name_identifier_format,
      # OIDC fields
      :issuer,
      :client_id,
      :client_secret,
      :discovery_url,
      :scope,
      # Common fields
      :auto_provision,
      :default_role,
      domain_allowlist: []
    )
  end

  def sso_login_path(org_slug)
    if @sso_config.saml?
      "/auth/saml/#{org_slug}"
    else
      "/auth/openid_connect/#{org_slug}"
    end
  end
  helper_method :sso_login_path
end
