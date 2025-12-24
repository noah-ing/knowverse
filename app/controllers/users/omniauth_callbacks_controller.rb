module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    skip_before_action :verify_authenticity_token, only: [:saml, :openid_connect]

    # SAML callback
    def saml
      handle_sso_callback('SAML')
    end

    # OIDC callback
    def openid_connect
      handle_sso_callback('OpenID Connect')
    end

    # Handle SSO failures
    def failure
      error_message = failure_message || 'Authentication failed'
      redirect_to new_user_session_path, alert: "SSO login failed: #{error_message}"
    end

    private

    def handle_sso_callback(provider_name)
      auth = request.env['omniauth.auth']
      params = request.env['omniauth.params'] || {}
      org_slug = params['org_slug'] || extract_org_slug_from_path

      organization = Organization.find_by(slug: org_slug)

      if organization.nil?
        redirect_to new_user_session_path, alert: 'Organization not found'
        return
      end

      unless organization.sso_enabled?
        redirect_to new_user_session_path, alert: 'SSO is not enabled for this organization'
        return
      end

      # Provision user
      result = Sso::UserProvisioner.new(auth, organization).provision!

      if result.success?
        user = result.user
        sign_in_and_redirect user, event: :authentication
        set_flash_message(:notice, :success, kind: provider_name) if is_navigational_format?
      else
        redirect_to new_user_session_path, alert: result.error
      end
    end

    def extract_org_slug_from_path
      # Extract org slug from callback path: /auth/:provider/:org_slug/callback
      path_parts = request.path.split('/')
      callback_index = path_parts.index('callback')
      path_parts[callback_index - 1] if callback_index && callback_index > 0
    end

    def failure_message
      exception = request.env['omniauth.error']
      return exception.message if exception.respond_to?(:message)

      error_type = request.env['omniauth.error.type']
      case error_type
      when :sso_not_configured
        'SSO is not configured for this organization'
      when :invalid_credentials
        'Invalid credentials'
      when :timeout
        'Request timed out'
      else
        error_type.to_s.humanize if error_type
      end
    end
  end
end
