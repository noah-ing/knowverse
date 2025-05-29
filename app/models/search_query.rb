class SearchQuery < ApplicationRecord
  # Associations
  belongs_to :organization
  belongs_to :user, optional: true
  has_many :search_feedbacks, dependent: :destroy
  
  # Validations
  validates :query_text, presence: true
  validates :latency, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :result_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  # Scopes
  scope :today, -> { where('created_at >= ?', Time.zone.now.beginning_of_day) }
  scope :recent, -> { order(created_at: :desc) }
  scope :high_latency, -> { where('latency > ?', 1000) }
  scope :zero_results, -> { where(result_count: 0) }
  scope :with_feedback, -> { joins(:search_feedbacks).distinct }
  
  # Scopes by provider
  scope :by_provider, ->(provider) { where(search_provider: provider) }
  
  # Query methods
  def has_feedback?
    search_feedbacks.exists?
  end
  
  def feedback_count
    search_feedbacks.count
  end
  
  def average_feedback_score
    search_feedbacks.average(:relevance_score).to_f.round(2)
  end
  
  def execution_time_seconds
    latency ? (latency / 1000.0).round(2) : nil
  end
  
  # Class methods for analytics
  def self.provider_comparison
    providers = distinct.pluck(:search_provider).compact
    
    result = {}
    
    providers.each do |provider|
      provider_queries = by_provider(provider)
      avg_latency = provider_queries.average(:latency).to_f.round(2)
      avg_results = provider_queries.average(:result_count).to_f.round(2)
      query_count = provider_queries.count
      
      # Get feedback for queries with this provider
      provider_feedback = SearchFeedback.joins(:search_query)
                                       .where(search_queries: { search_provider: provider })
      
      avg_feedback = provider_feedback.average(:relevance_score).to_f.round(2)
      
      result[provider] = {
        avg_latency: avg_latency,
        avg_results: avg_results,
        query_count: query_count,
        avg_feedback: avg_feedback
      }
    end
    
    result
  end
  
  def self.time_distribution(days = 30)
    start_date = days.days.ago.beginning_of_day
    
    where('created_at >= ?', start_date)
      .group("DATE(created_at)")
      .count
  end
end
