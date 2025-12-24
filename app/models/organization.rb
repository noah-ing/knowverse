class Organization < ApplicationRecord
  # Default settings
  DEFAULTS = {
    max_documents: 50,
    max_queries_per_month: 1000,
    advanced_search: false,
    api_access: false
  }.freeze

  # Settings configuration
  store_accessor :settings, :max_documents, :max_queries_per_month, :advanced_search, :api_access,
                :default_search_provider
  
  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :slug, presence: true, uniqueness: true, length: { maximum: 50 },
            format: { with: /\A[a-z0-9-]+\z/, message: "can only contain lowercase letters, numbers, and hyphens" }
  validates :active, inclusion: { in: [true, false] }
  
  # Callbacks
  before_validation :generate_slug, if: -> { slug.blank? && name.present? }
  before_create :set_default_settings
  before_create :generate_mcp_api_key, if: -> { mcp_api_key.blank? }

  # MCP API key methods
  def regenerate_mcp_api_key!
    update!(mcp_api_key: generate_mcp_api_key_value)
  end

  def self.find_by_mcp_api_key(key)
    return nil if key.blank?
    find_by(mcp_api_key: key)
  end
  
  # Associations
  has_many :organization_users, dependent: :destroy
  has_many :users, through: :organization_users
  has_many :documents, dependent: :destroy
  has_many :search_queries, dependent: :destroy
  has_many :search_feedbacks, dependent: :destroy
  has_many :domain_embedding_models, dependent: :destroy
  has_many :domain_confidence_scores, dependent: :destroy
  has_many :organization_templates, dependent: :destroy
  has_many :document_sources, dependent: :destroy
  has_one :sso_config, dependent: :destroy
  
  # Scopes
  scope :active, -> { where(active: true) }
  
  # Instance methods
  def owner
    organization_users.find_by(role: 'owner')&.user
  end

  def self.roles
    %w[owner admin editor viewer]
  end

  # SSO helpers
  def sso_enabled?
    sso_config&.ready?
  end

  def sso_provider_type
    sso_config&.provider_type
  end
  
  def usage_percent(type = :documents)
    case type
    when :documents
      return 0 if max_documents.to_i == 0
      (documents.count.to_f / max_documents.to_i * 100).round(1)
    when :queries
      return 0 if max_queries_per_month.to_i == 0
      # Calculate query usage with search_queries
      current_month_queries = search_queries.where('created_at >= ?', Time.zone.now.beginning_of_month).count
      (current_month_queries.to_f / max_queries_per_month.to_i * 100).round(1)
    end
  end
  
  # Search feedback analytics
  def search_analytics(timeframe = 30)
    {
      total_queries: search_queries.where('created_at >= ?', timeframe.days.ago).count,
      average_latency: search_queries.where('created_at >= ?', timeframe.days.ago).average(:latency).to_f.round(2),
      provider_distribution: search_queries.where('created_at >= ?', timeframe.days.ago).group(:search_provider).count,
      feedback_score: search_feedbacks.where('created_at >= ?', timeframe.days.ago).average(:relevance_score).to_f.round(2),
      feedback_distribution: search_feedbacks.where('created_at >= ?', timeframe.days.ago).group(:feedback_type).count,
      domain_confidence: domain_confidence_analytics(timeframe)
    }
  end
  
  # Domain confidence methods
  def domain_confidence_analytics(timeframe = 30)
    scores = domain_confidence_scores.where('created_at >= ?', timeframe.days.ago)
    
    {
      average_confidence: scores.average(:total_score).to_f.round(2),
      success_rate: calculate_confidence_success_rate(scores),
      by_domain: scores.group(:domain).average(:total_score).transform_values { |v| v.to_f.round(2) },
      factor_averages: calculate_factor_averages(scores)
    }
  end
  
  def calculate_confidence_success_rate(scores)
    total = scores.count
    return 0 if total == 0
    
    (scores.where(was_successful: true).count.to_f / total * 100).round(2)
  end
  
  def calculate_factor_averages(scores)
    {
      semantic_similarity: scores.average(:semantic_similarity).to_f.round(2),
      corpus_coverage: scores.average(:corpus_coverage).to_f.round(2),
      query_characteristics: scores.average(:query_characteristics).to_f.round(2),
      historical_performance: scores.average(:historical_performance).to_f.round(2)
    }
  end
  
  # Domain-specific methods
  def available_domains
    domain_embedding_models.pluck(:domain).uniq
  end
  
  def active_domain_embedding_models
    domain_embedding_models.active
  end
  
  def domain_models_by_domain(domain)
    domain_embedding_models.where(domain: domain, active: true)
  end
  
  def vector_domains
    # Combine domains from domain models and existing vector embeddings
    (
      domain_embedding_models.pluck(:domain) + 
      documents.joins(:vector_embeddings).distinct.pluck('vector_embeddings.domain')
    ).uniq
  end
  
  private
  
  def generate_slug
    base_slug = name.downcase.strip.gsub(/[^\w-]/, '-').gsub(/-+/, '-')
    self.slug = base_slug
    
    # Ensure uniqueness
    counter = 2
    while Organization.where(slug: self.slug).where.not(id: self.id).exists?
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end
  
  def set_default_settings
    self.settings = DEFAULTS.merge(settings || {})
    self.active = true if active.nil?

    # Only set domain confidence thresholds if the fields exist
    if respond_to?(:domain_confidence_primary_threshold)
      self.domain_confidence_primary_threshold ||= 0.7
      self.domain_confidence_secondary_threshold ||= 0.4
      self.enable_domain_fallback = true if enable_domain_fallback.nil?
    end
  end

  def generate_mcp_api_key
    self.mcp_api_key = generate_mcp_api_key_value
  end

  def generate_mcp_api_key_value
    "kv_#{SecureRandom.hex(24)}"
  end
end
