module Billing
  class QuotaEnforcer
    class QuotaExceededError < StandardError
      attr_reader :quota_type, :current, :limit

      def initialize(quota_type, current, limit)
        @quota_type = quota_type
        @current = current
        @limit = limit
        super("#{quota_type.to_s.humanize} quota exceeded: #{current}/#{limit}")
      end
    end

    class FeatureNotAvailableError < StandardError
      attr_reader :feature

      def initialize(feature)
        @feature = feature
        super("Feature not available on current plan: #{feature}")
      end
    end

    GRACE_PERCENT = 10 # Allow 10% overage before hard block
    WARN_THRESHOLDS = [80, 90, 100].freeze

    attr_reader :organization

    def initialize(organization)
      @organization = organization
    end

    # Document quota enforcement
    def enforce_document_quota!
      limit = organization.max_documents.to_i
      return true if limit.zero? # Unlimited

      current = organization.documents.count
      hard_limit = (limit * (1 + GRACE_PERCENT / 100.0)).floor

      if current >= hard_limit
        raise QuotaExceededError.new(:documents, current, limit)
      end

      true
    end

    def can_upload_document?
      enforce_document_quota!
      true
    rescue QuotaExceededError
      false
    end

    def document_quota_status
      limit = organization.max_documents.to_i
      return { status: :unlimited, percent: 0 } if limit.zero?

      current = organization.documents.count
      percent = (current.to_f / limit * 100).round(1)

      {
        status: quota_status_level(percent),
        current: current,
        limit: limit,
        percent: percent,
        remaining: [limit - current, 0].max,
        warning: warning_message(:documents, percent, limit - current)
      }
    end

    # Query quota enforcement
    def enforce_query_quota!
      limit = organization.max_queries_per_month.to_i
      return true if limit.zero? # Unlimited

      current = organization.current_month_queries
      hard_limit = (limit * (1 + GRACE_PERCENT / 100.0)).floor

      if current >= hard_limit
        raise QuotaExceededError.new(:queries, current, limit)
      end

      true
    end

    def can_perform_query?
      enforce_query_quota!
      true
    rescue QuotaExceededError
      false
    end

    def query_quota_status
      limit = organization.max_queries_per_month.to_i
      return { status: :unlimited, percent: 0 } if limit.zero?

      current = organization.current_month_queries
      percent = (current.to_f / limit * 100).round(1)

      {
        status: quota_status_level(percent),
        current: current,
        limit: limit,
        percent: percent,
        remaining: [limit - current, 0].max,
        resets_at: Time.current.end_of_month,
        warning: warning_message(:queries, percent, limit - current)
      }
    end

    # Team member quota enforcement
    def enforce_team_quota!
      limit = organization.plan&.max_team_members.to_i
      return true if limit.zero? # Unlimited

      current = organization.organization_users.count

      if current >= limit
        raise QuotaExceededError.new(:team_members, current, limit)
      end

      true
    end

    def can_add_team_member?
      enforce_team_quota!
      true
    rescue QuotaExceededError
      false
    end

    def team_quota_status
      limit = organization.plan&.max_team_members.to_i
      return { status: :unlimited, percent: 0 } if limit.zero?

      current = organization.organization_users.count
      percent = (current.to_f / limit * 100).round(1)

      {
        status: quota_status_level(percent),
        current: current,
        limit: limit,
        percent: percent,
        remaining: [limit - current, 0].max
      }
    end

    # Feature enforcement
    def enforce_feature!(feature)
      case feature.to_sym
      when :api_access
        raise FeatureNotAvailableError.new(feature) unless organization.api_access
      when :advanced_search
        raise FeatureNotAvailableError.new(feature) unless organization.advanced_search
      else
        raise ArgumentError, "Unknown feature: #{feature}"
      end

      true
    end

    def has_feature?(feature)
      enforce_feature!(feature)
      true
    rescue FeatureNotAvailableError
      false
    end

    # Overall quota summary
    def quota_summary
      {
        documents: document_quota_status,
        queries: query_quota_status,
        team_members: team_quota_status,
        features: {
          api_access: organization.api_access || false,
          advanced_search: organization.advanced_search || false
        },
        subscription: {
          status: organization.subscription_status,
          plan: organization.plan&.name,
          trialing: organization.trialing?,
          trial_ends_at: organization.trial_ends_at
        }
      }
    end

    private

    def quota_status_level(percent)
      if percent >= 100 + GRACE_PERCENT
        :blocked
      elsif percent >= 100
        :exceeded
      elsif percent >= 90
        :critical
      elsif percent >= 80
        :warning
      else
        :ok
      end
    end

    def warning_message(type, percent, remaining)
      return nil if percent < 80

      type_name = type.to_s.humanize.downcase

      if percent >= 100
        "You've reached your #{type_name} limit. Upgrade your plan to continue."
      elsif percent >= 90
        "You're almost at your #{type_name} limit. Only #{remaining} remaining."
      elsif percent >= 80
        "You're approaching your #{type_name} limit. #{remaining} remaining."
      end
    end
  end
end
