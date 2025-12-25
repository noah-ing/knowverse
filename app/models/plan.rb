class Plan < ApplicationRecord
  # Associations
  has_many :organizations

  # Validations
  validates :name, presence: true
  validates :stripe_price_id, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :interval, presence: true, inclusion: { in: %w[month year] }
  validates :max_documents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :max_queries_per_month, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :max_team_members, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :trial_days, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :display_order, numericality: { only_integer: true }, allow_nil: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(display_order: :asc, amount: :asc) }
  scope :monthly, -> { where(interval: 'month') }
  scope :yearly, -> { where(interval: 'year') }

  # Returns a formatted price string (e.g., "$9.99/month")
  def formatted_price
    price = amount.to_f / 100
    interval_text = interval == 'month' ? '/month' : '/year'

    return "Free" if price.zero?
    "$#{sprintf('%.2f', price)}#{interval_text}"
  end

  # Return the features as a string array
  def feature_list
    features || []
  end

  # Plan type helpers
  def free?
    amount.to_i.zero?
  end

  def has_trial?
    trial_days.to_i.positive?
  end

  def has_api_access?
    api_access == true
  end

  def has_advanced_search?
    advanced_search == true
  end

  # Quota summary for display
  def quota_summary
    {
      documents: max_documents || 50,
      queries_per_month: max_queries_per_month || 1000,
      team_members: max_team_members || 5,
      api_access: api_access || false,
      advanced_search: advanced_search || false
    }
  end

  # Annual price calculation (for display)
  def annual_equivalent
    return 0 if free?
    return amount if interval == 'year'
    amount * 12
  end

  def monthly_equivalent
    return 0 if free?
    return amount if interval == 'month'
    (amount / 12.0).round
  end
end
