module Sso
  class UserProvisioner
    attr_reader :auth_hash, :organization, :sso_config

    def initialize(auth_hash, organization)
      @auth_hash = auth_hash
      @organization = organization
      @sso_config = organization.sso_config
    end

    def provision!
      return Result.failure('SSO not configured') unless sso_config&.enabled?

      email = extract_email
      return Result.failure('Email not provided by IdP') if email.blank?
      return Result.failure('Email domain not allowed') unless domain_allowed?(email)

      user = find_or_create_user(email)
      ensure_organization_membership(user)
      record_sso_login

      Result.success(user)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure("Failed to create user: #{e.message}")
    rescue StandardError => e
      Rails.logger.error("SSO provisioning error: #{e.message}")
      Result.failure('An error occurred during SSO login')
    end

    private

    def extract_email
      auth_hash.info.email&.downcase
    end

    def extract_name
      auth_hash.info.name || auth_hash.info.first_name
    end

    def domain_allowed?(email)
      sso_config.domain_allowed?(email)
    end

    def find_or_create_user(email)
      # First, try to find by SSO provider/uid
      user = User.find_by(provider: auth_hash.provider, uid: auth_hash.uid)
      return user if user

      # Try to find existing user by email
      user = User.find_by(email: email)

      if user
        # Link existing user to SSO
        link_user_to_sso(user)
      elsif sso_config.auto_provision?
        # Create new user via JIT provisioning
        create_sso_user(email)
      else
        raise ActiveRecord::RecordInvalid.new(User.new), 'Auto-provisioning disabled'
      end
    end

    def link_user_to_sso(user)
      user.update!(
        provider: auth_hash.provider,
        uid: auth_hash.uid,
        sso_organization: organization
      )
      user
    end

    def create_sso_user(email)
      User.create!(
        email: email,
        name: extract_name,
        provider: auth_hash.provider,
        uid: auth_hash.uid,
        sso_organization: organization,
        password: Devise.friendly_token[0, 20]
      )
    end

    def ensure_organization_membership(user)
      return if user.organizations.include?(organization)

      OrganizationUser.create!(
        user: user,
        organization: organization,
        role: sso_config.default_role
      )
    end

    def record_sso_login
      sso_config.record_login!
    end

    # Result object for cleaner error handling
    class Result
      attr_reader :user, :error

      def initialize(success:, user: nil, error: nil)
        @success = success
        @user = user
        @error = error
      end

      def success?
        @success
      end

      def failure?
        !@success
      end

      def self.success(user)
        new(success: true, user: user)
      end

      def self.failure(error)
        new(success: false, error: error)
      end
    end
  end
end
