class SearchFeedback < ApplicationRecord
  # Constants
  FEEDBACK_TYPES = %w[
    relevance_thumbs_up
    relevance_thumbs_down
    relevance_rating
    missing_information
    incorrect_information
    general_comment
  ].freeze
  
  # Associations
  belongs_to :organization
  belongs_to :user, optional: true
  belongs_to :search_query
  belongs_to :document, optional: true
  
  # Validations
  validates :feedback_type, inclusion: { in: FEEDBACK_TYPES }
  validates :relevance_score, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }, allow_nil: true
  validates :document, presence: true, if: -> { feedback_type.starts_with?('relevance_') }
  
  # Scopes
  scope :positive, -> { where('relevance_score >= ?', 4) }
  scope :neutral, -> { where(relevance_score: 3) }
  scope :negative, -> { where('relevance_score <= ?', 2) }
  scope :recent, -> { order(created_at: :desc) }
  
  # Feedback distribution methods
  def self.feedback_distribution
    {
      positive: positive.count,
      neutral: neutral.count,
      negative: negative.count
    }
  end
  
  def self.average_relevance_by_provider
    joins(:search_query)
      .group('search_queries.search_provider')
      .average(:relevance_score)
      .transform_values { |avg| avg.to_f.round(2) }
  end
  
  def self.feedback_count_by_type
    group(:feedback_type).count
  end
  
  def self.feedback_trend(days = 30)
    start_date = days.days.ago.beginning_of_day
    
    # Get feedback by day and score type
    where('created_at >= ?', start_date)
      .select("DATE(created_at) as date, 
               CASE 
                 WHEN relevance_score >= 4 THEN 'positive'
                 WHEN relevance_score = 3 THEN 'neutral'
                 WHEN relevance_score <= 2 THEN 'negative'
               END as score_type, 
               COUNT(*) as count")
      .group("DATE(created_at)", "score_type")
      .order("DATE(created_at)")
      .each_with_object({}) do |result, hash|
        date = result.date
        score_type = result.score_type || 'unknown'
        count = result.count
        
        hash[[date, score_type]] = count
      end
  end
  
  # For calculating problem areas
  def self.problematic_queries(min_feedback_count = 2, max_score = 3.0)
    joins(:search_query)
      .select('search_queries.*, AVG(search_feedbacks.relevance_score) as avg_score, COUNT(search_feedbacks.id) as feedback_count')
      .group('search_queries.id')
      .having('AVG(search_feedbacks.relevance_score) < ? AND COUNT(search_feedbacks.id) >= ?', max_score, min_feedback_count)
      .order('avg_score ASC')
  end
  
  def self.documents_with_most_negative_feedback(limit = 10)
    joins(:document)
      .where('relevance_score <= ?', 2)
      .select('documents.*, COUNT(search_feedbacks.id) as negative_feedback_count')
      .group('documents.id')
      .order('negative_feedback_count DESC')
      .limit(limit)
  end
  
  def self.documents_with_most_positive_feedback(limit = 10)
    joins(:document)
      .where('relevance_score >= ?', 4)
      .select('documents.*, COUNT(search_feedbacks.id) as positive_feedback_count')
      .group('documents.id')
      .order('positive_feedback_count DESC')
      .limit(limit)
  end
end
