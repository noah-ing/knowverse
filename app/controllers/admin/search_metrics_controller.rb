class Admin::SearchMetricsController < Admin::BaseController
  before_action :require_admin
  
  # GET /admin/search_metrics
  def index
    @stats = {
      total_queries: SearchQuery.count,
      total_feedback: SearchFeedback.count,
      feedback_percentage: feedback_percentage,
      average_relevance: SearchFeedback.average(:relevance_score).to_f.round(2),
      queries_today: SearchQuery.today.count,
      queries_by_provider: SearchQuery.group(:search_provider).count,
      feedback_by_type: SearchFeedback.feedback_count_by_type,
    }
    
    @timeline = {
      queries_by_day: queries_by_day(30),
      feedback_by_day: feedback_by_day(30)
    }
    
    @top_organizations = Organization
      .joins(:search_queries)
      .select('organizations.id, organizations.name, COUNT(search_queries.id) as query_count')
      .group('organizations.id, organizations.name')
      .order('query_count DESC')
      .limit(10)
      
    @recent_queries = SearchQuery
      .includes(:organization, :user)
      .order(created_at: :desc)
      .limit(20)
  end
  
  # GET /admin/search_metrics/provider_comparison
  def provider_comparison
    @providers = SearchQuery.distinct.pluck(:search_provider).compact
    
    @metrics = {
      query_count: SearchQuery.group(:search_provider).count,
      avg_latency: SearchQuery.group(:search_provider).average(:latency),
      avg_results: SearchQuery.group(:search_provider).average(:result_count),
      feedback_score: SearchFeedback.average_relevance_by_provider
    }
    
    # For charts
    @chart_data = {
      providers: @providers,
      query_counts: @providers.map { |p| @metrics[:query_count][p] || 0 },
      avg_latencies: @providers.map { |p| (@metrics[:avg_latency][p] || 0).round(2) },
      feedback_scores: @providers.map { |p| (@metrics[:feedback_score][p] || 0).round(2) }
    }
  end
  
  # GET /admin/search_metrics/feedback_analysis
  def feedback_analysis
    @feedback_distribution = SearchFeedback.feedback_distribution
    
    @feedback_by_type = SearchFeedback.group(:feedback_type).count
    
    @top_documents_positive = Document
      .with_positive_feedback
      .select('documents.id, documents.title, COUNT(search_feedbacks.id) as feedback_count')
      .joins(:search_feedbacks)
      .where('search_feedbacks.relevance_score >= ?', 4)
      .group('documents.id, documents.title')
      .order('feedback_count DESC')
      .limit(10)
      
    @top_documents_negative = Document
      .with_negative_feedback
      .select('documents.id, documents.title, COUNT(search_feedbacks.id) as feedback_count')
      .joins(:search_feedbacks)
      .where('search_feedbacks.relevance_score <= ?', 2)
      .group('documents.id, documents.title')
      .order('feedback_count DESC')
      .limit(10)
      
    @feedback_trend = SearchFeedback.feedback_trend(30)
    
    # Format for chart visualization
    @trend_data = {
      dates: @feedback_trend.keys.map(&:first).uniq.sort,
      positive: [],
      neutral: [],
      negative: []
    }
  end
  
  # GET /admin/search_metrics/problem_queries
  def problem_queries
    @problem_queries = SearchQuery
      .joins(:search_feedbacks)
      .select('search_queries.*, AVG(search_feedbacks.relevance_score) as avg_score, COUNT(search_feedbacks.id) as feedback_count')
      .group('search_queries.id')
      .having('AVG(search_feedbacks.relevance_score) < 3 AND COUNT(search_feedbacks.id) > 1')
      .order('avg_score ASC')
      .limit(50)
      .includes(:organization, :user)
      
    @zero_results_queries = SearchQuery
      .where(result_count: 0)
      .order(created_at: :desc)
      .limit(50)
      .includes(:organization, :user)
      
    @high_latency_queries = SearchQuery
      .where('latency > ?', 1000) # Over 1 second
      .order(latency: :desc)
      .limit(50)
      .includes(:organization, :user)
  end
  
  private
  
  def feedback_percentage
    total_queries = SearchQuery.count
    return 0 if total_queries == 0
    
    queries_with_feedback = SearchQuery
      .joins(:search_feedbacks)
      .select('DISTINCT search_queries.id')
      .count
      
    (queries_with_feedback.to_f / total_queries * 100).round(2)
  end
  
  def queries_by_day(days = 30)
    start_date = days.days.ago.beginning_of_day
    
    # Get counts by day
    results = SearchQuery
      .where('created_at >= ?', start_date)
      .group("DATE(created_at)")
      .count
      
    # Fill in missing dates with zeros
    date_range = (start_date.to_date..Date.today).map { |date| date.strftime('%Y-%m-%d') }
    
    date_range.each_with_object({}) do |date, hash|
      hash[date] = results[date] || 0
    end
  end
  
  def feedback_by_day(days = 30)
    start_date = days.days.ago.beginning_of_day
    
    # Get counts by day and type
    results = SearchFeedback
      .where('created_at >= ?', start_date)
      .group("DATE(created_at)", :feedback_type)
      .count
      
    # Format for chart display
    date_range = (start_date.to_date..Date.today).map { |date| date.strftime('%Y-%m-%d') }
    
    feedback_types = SearchFeedback::FEEDBACK_TYPES
    
    data = {}
    
    date_range.each do |date|
      data[date] = {}
      
      feedback_types.each do |type|
        data[date][type] = results[[date, type]] || 0
      end
    end
    
    data
  end
end
