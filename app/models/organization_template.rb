class OrganizationTemplate < ApplicationRecord
  belongs_to :organization
  has_many :template_usages, dependent: :destroy
  has_many :conversation_sessions
  
  validates :name, presence: true, uniqueness: { scope: :organization_id }
  validates :content, presence: true
  validates :template_type, presence: true
  
  # Scopes
  scope :rag_templates, -> { where(template_type: 'rag') }
  scope :default_templates, -> { where(is_default: true) }
  
  # Only one default template per organization and type
  validate :only_one_default_per_type
  
  def only_one_default_per_type
    if is_default? && organization.organization_templates
                                 .where.not(id: id)
                                 .where(template_type: template_type, is_default: true)
                                 .exists?
      errors.add(:is_default, "can only be set for one template per type")
    end
  end
  
  # Get variables from the template content
  # Format: {{variable_name}} or {{variable_name:default_value}}
  def extract_variables
    variable_matches = content.scan(/\{\{([^}]+)\}\}/)
    variables = {}
    
    variable_matches.each do |match|
      parts = match[0].split(':')
      var_name = parts[0].strip
      var_default = parts[1]&.strip
      
      variables[var_name] = {
        default: var_default,
        description: var_name.humanize
      }
    end
    
    variables
  end
  
  # Apply variables to the template content
  def apply_variables(var_values = {})
    result = content.dup
    extract_variables.each do |var_name, var_info|
      value = var_values[var_name] || var_info[:default] || ""
      result.gsub!(/\{\{#{var_name}(:.*?)?\}\}/, value)
    end
    result
  end
  
  # Update usage statistics
  def record_usage(user, session, metrics = {})
    usage = template_usages.create!(
      user: user,
      conversation_session: session,
      response_time: metrics[:response_time],
      token_count: metrics[:token_count],
      metrics: metrics
    )
    
    # Update the usage count
    update_column(:usage_count, usage_count + 1)
    
    usage
  end
  
  # Record a rating for this template
  def record_rating(usage, rating)
    return false unless usage && rating.between?(1, 5)
    
    usage.update(rating: rating)
    
    # Update the average rating
    total_ratings = template_usages.where.not(rating: nil).count
    return false if total_ratings == 0
    
    new_average = template_usages.where.not(rating: nil).average(:rating).to_f
    update_column(:average_rating, new_average)
    
    true
  end
end
