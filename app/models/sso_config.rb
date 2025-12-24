class SsoConfig < ApplicationRecord
  PROVIDER_TYPES = %w[saml oidc].freeze
  ROLES = %w[owner admin editor viewer].freeze

  # Associations
  belongs_to :organization

  # Encrypt sensitive fields
  encrypts :idp_metadata_url
  encrypts :idp_sso_target_url
  encrypts :idp_cert
  encrypts :issuer
  encrypts :client_id
  encrypts :client_secret
  encrypts :discovery_url

  # Validations
  validates :provider_type, presence: true, inclusion: { in: PROVIDER_TYPES }
  validates :default_role, inclusion: { in: ROLES }

  # SAML validations
  validates :idp_sso_target_url, presence: true, if: :saml?
  validates :idp_cert, presence: true, if: -> { saml? && idp_cert_fingerprint.blank? }

  # OIDC validations
  validates :issuer, presence: true, if: :oidc?
  validates :client_id, presence: true, if: :oidc?
  validates :client_secret, presence: true, if: :oidc?

  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :saml, -> { where(provider_type: 'saml') }
  scope :oidc, -> { where(provider_type: 'oidc') }

  # Callbacks
  before_save :parse_metadata_url, if: -> { saml? && idp_metadata_url.present? && idp_metadata_url_changed? }

  # Type helpers
  def saml?
    provider_type == 'saml'
  end

  def oidc?
    provider_type == 'oidc'
  end

  # Domain validation
  def domain_allowed?(email)
    return true if domain_allowlist.blank?

    domain = email.to_s.split('@').last&.downcase
    domain_allowlist.map(&:downcase).include?(domain)
  end

  # SAML configuration for OmniAuth
  def saml_settings
    return {} unless saml?

    settings = {
      idp_sso_target_url: idp_sso_target_url,
      name_identifier_format: name_identifier_format
    }

    if idp_cert.present?
      settings[:idp_cert] = idp_cert
    elsif idp_cert_fingerprint.present?
      settings[:idp_cert_fingerprint] = idp_cert_fingerprint
    end

    settings
  end

  # OIDC configuration for OmniAuth
  def oidc_settings
    return {} unless oidc?

    settings = {
      issuer: issuer,
      client_options: {
        identifier: client_id,
        secret: client_secret
      },
      scope: scope.split.map(&:to_sym)
    }

    if discovery_url.present?
      settings[:discovery] = true
      settings[:client_options][:discovery_document] = discovery_url
    end

    settings
  end

  # Track usage
  def record_login!
    update_columns(
      last_used_at: Time.current,
      login_count: login_count + 1
    )
  end

  # Status helpers
  def status
    if !enabled?
      :disabled
    elsif saml? && idp_sso_target_url.blank?
      :incomplete
    elsif oidc? && (issuer.blank? || client_id.blank?)
      :incomplete
    else
      :ready
    end
  end

  def ready?
    status == :ready && enabled?
  end

  private

  def parse_metadata_url
    # If metadata URL is provided, fetch and parse it to extract IdP settings
    # This is a placeholder - in production you'd fetch the metadata XML
    # and extract idp_sso_target_url, idp_cert, etc.
    #
    # For now, we just validate the URL format
    return unless idp_metadata_url.present?

    begin
      uri = URI.parse(idp_metadata_url)
      unless uri.is_a?(URI::HTTPS) || uri.is_a?(URI::HTTP)
        errors.add(:idp_metadata_url, 'must be a valid URL')
      end
    rescue URI::InvalidURIError
      errors.add(:idp_metadata_url, 'must be a valid URL')
    end
  end
end
