class DomainConfidenceScore < ApplicationRecord
  # Associations
  belongs_to :organization
  
  # Validations
  validates :query_text, presence: true
  validates :domain, presence: true
  validates :total_score, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  
  # Scopes
  scope :successful, -> { where(was_successful: true) }
  scope :unsuccessful, -> { where(was_successful: false) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_domain, ->(domain) { where(domain: domain) }
  
  # Store factor scores as a hash in the jsonb column
  store_accessor :factor_scores, :semantic_factor, :corpus_factor, :query_factor, :historical_factor
  
  # Class methods for analytics
  def self.average_score_for_domain(domain, organization_id)
    where(domain: domain, organization_id: organization_id).average(:total_score)
  end
  
  def self.success_rate_for_domain(domain, organization_id)
    total = where(domain: domain, organization_id: organization_id).count
    return 0 if total == 0
    
    successful = where(domain: domain, organization_id: organization_id, was_successful: true).count
    (successful.to_f / total) * 100
  end
  
  def self.recent_scores_for_domain(domain, organization_id, limit = 10)
    where(domain: domain, organization_id: organization_id).order(created_at: :desc).limit(limit)
  end
  
  # Methods to help categorize confidence
  def confidence_category
    case total_score
    when 0.8..1.0
      'high'
    when 0.5...0.8
      'medium'
    else
      'low'
    end
  end
  
  # Serialize the full factor data
  def factor_breakdown
    {
      semantic_similarity: semantic_similarity,
      corpus_coverage: corpus_coverage,
      query_characteristics: query_characteristics,
      historical_performance: historical_performance,
      total_score: total_score
    }
  end
end
