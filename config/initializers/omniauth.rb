# OmniAuth configuration for SSO (SAML 2.0 and OIDC)
#
# Providers are dynamically configured per-organization using the setup lambda.
# Each organization can have its own IdP configuration stored in sso_configs table.

Rails.application.config.middleware.use OmniAuth::Builder do
  # Configure OmniAuth
  OmniAuth.config.logger = Rails.logger
  OmniAuth.config.allowed_request_methods = [:post, :get]
  OmniAuth.config.silence_get_warning = true

  # SAML 2.0 provider - dynamically configured per organization
  provider :saml,
    name: 'saml',
    setup: lambda { |env|
      request = Rack::Request.new(env)
      strategy = env['omniauth.strategy']

      # Extract organization slug from path: /auth/saml/:org_slug
      path_parts = request.path.split('/')
      org_slug_index = path_parts.index('saml')
      org_slug = path_parts[org_slug_index + 1] if org_slug_index

      org = Organization.find_by(slug: org_slug)
      sso_config = org&.sso_config

      if sso_config&.saml? && sso_config.enabled?
        strategy.options.merge!(
          idp_sso_target_url: sso_config.idp_sso_target_url,
          idp_cert: sso_config.idp_cert,
          idp_cert_fingerprint: sso_config.idp_cert_fingerprint,
          name_identifier_format: sso_config.name_identifier_format,
          assertion_consumer_service_url: "#{request.base_url}/auth/saml/#{org_slug}/callback",
          issuer: "#{request.base_url}/auth/saml/#{org_slug}",
          security: {
            authn_requests_signed: false,
            want_assertions_signed: true,
            want_assertions_encrypted: false
          }
        )

        # Store organization info for callback
        env['omniauth.params'] ||= {}
        env['omniauth.params']['org_slug'] = org_slug
      else
        strategy.fail!(:sso_not_configured, StandardError.new('SSO not configured for this organization'))
      end
    }

  # OpenID Connect provider - dynamically configured per organization
  provider :openid_connect,
    name: 'openid_connect',
    setup: lambda { |env|
      request = Rack::Request.new(env)
      strategy = env['omniauth.strategy']

      # Extract organization slug from path: /auth/oidc/:org_slug
      path_parts = request.path.split('/')
      org_slug_index = path_parts.index('oidc') || path_parts.index('openid_connect')
      org_slug = path_parts[org_slug_index + 1] if org_slug_index

      org = Organization.find_by(slug: org_slug)
      sso_config = org&.sso_config

      if sso_config&.oidc? && sso_config.enabled?
        client_options = {
          identifier: sso_config.client_id,
          secret: sso_config.client_secret,
          redirect_uri: "#{request.base_url}/auth/openid_connect/#{org_slug}/callback"
        }

        # Use discovery if available
        if sso_config.discovery_url.present?
          client_options[:discovery] = true
          client_options[:host] = URI.parse(sso_config.issuer).host
        end

        strategy.options.merge!(
          issuer: sso_config.issuer,
          scope: sso_config.scope.split.map(&:to_sym),
          client_options: client_options,
          discovery: sso_config.discovery_url.present?
        )

        # Store organization info for callback
        env['omniauth.params'] ||= {}
        env['omniauth.params']['org_slug'] = org_slug
      else
        strategy.fail!(:sso_not_configured, StandardError.new('SSO not configured for this organization'))
      end
    }
end

# Handle OmniAuth failures
OmniAuth.config.on_failure = Proc.new { |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
}
