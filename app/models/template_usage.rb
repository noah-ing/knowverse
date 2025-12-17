class TemplateUsage < ApplicationRecord
  belongs_to :organization_template
  belongs_to :user
  belongs_to :conversation_session, optional: true
  
  validates :organization_template, presence: true
  validates :user, presence: true
  validates :rating, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }, allow_nil: true
  
  # Scopes
  scope :with_rating, -> { where.not(rating: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_template, ->(template_id) { where(organization_template_id: template_id) }
  
  # Calculate average metrics for a given template
  def self.metrics_for_template(template_id)
    usages = by_template(template_id)
    return {} if usages.empty?
    
    {
      average_response_time: usages.average(:response_time).to_f.round(2),
      average_token_count: usages.average(:token_count).to_i,
      average_rating: usages.with_rating.average(:rating).to_f.round(2),
      total_usages: usages.count,
      rated_usages: usages.with_rating.count
    }
  end
  
  # Get metrics time series for a template
  def self.time_series_metrics(template_id, days: 30, interval: 'day')
    template = OrganizationTemplate.find_by(id: template_id)
    return [] unless template
    
    end_date = Date.current
    start_date = end_date - days.days
    
    # Group by day
    if interval == 'day'
      results = by_template(template_id)
                .where(created_at: start_date.beginning_of_day..end_date.end_of_day)
                .group("DATE(created_at)")
                .select("DATE(created_at) as date, 
                        AVG(response_time) as avg_response_time, 
                        AVG(token_count) as avg_token_count, 
                        COUNT(*) as usage_count")
                .order("DATE(created_at)")
    # Group by week  
    elsif interval == 'week'
      results = by_template(template_id)
                .where(created_at: start_date.beginning_of_day..end_date.end_of_day)
                .group("DATE_TRUNC('week', created_at)")
                .select("DATE_TRUNC('week', created_at) as date, 
                        AVG(response_time) as avg_response_time, 
                        AVG(token_count) as avg_token_count, 
                        COUNT(*) as usage_count")
                .order("DATE_TRUNC('week', created_at)")
    # Group by month
    else
      results = by_template(template_id)
                .where(created_at: start_date.beginning_of_day..end_date.end_of_day)
                .group("DATE_TRUNC('month', created_at)")
                .select("DATE_TRUNC('month', created_at) as date, 
                        AVG(response_time) as avg_response_time, 
                        AVG(token_count) as avg_token_count, 
                        COUNT(*) as usage_count")
                .order("DATE_TRUNC('month', created_at)")
    end
    
    results.map do |r|
      {
        date: r.date,
        avg_response_time: r.avg_response_time.to_f.round(2),
        avg_token_count: r.avg_token_count.to_i,
        usage_count: r.usage_count
      }
    end
  end
  
  # Get additional metrics
  def detailed_metrics
    return {} unless metrics.is_a?(Hash)
    
    # Calculate metrics for detailed analysis
    metrics_data = metrics.dup
    
    # Token rate (tokens per second)
    if response_time && response_time > 0 && token_count && token_count > 0
      metrics_data[:token_rate] = (token_count / response_time).round(2)
    end
    
    # Add any template-specific metrics
    if organization_template.template_type == 'rag'
      # Add RAG-specific metrics
      metrics_data[:citation_count] = metrics['citation_count'] || 0
      metrics_data[:retrieval_time] = metrics['retrieval_time']&.to_f&.round(2) || 0
      metrics_data[:generation_time] = metrics['generation_time']&.to_f&.round(2) || 0
    end
    
    metrics_data
  end
end
