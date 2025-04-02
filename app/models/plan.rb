class Plan < ApplicationRecord
  # features column is now a PostgreSQL string array (no need for serialize)
  
  # Validations
  validates :name, presence: true
  validates :stripe_price_id, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :interval, presence: true, inclusion: { in: %w[month year] }
  
  # Scopes
  scope :active, -> { where(active: true) }

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
end
