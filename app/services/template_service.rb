class TemplateService
  attr_reader :organization

  def initialize(organization)
    @organization = organization
  end

  # Find a template by type, optionally looking for a default one
  def find_template(template_type, template_id = nil)
    if template_id.present?
      # If a specific template ID is provided, use that
      template = @organization.organization_templates.find_by(id: template_id)
      return template if template&.template_type == template_type
    end

    # If no template ID or the template with that ID wasn't found or doesn't match the type,
    # look for the default template for this type
    @organization.organization_templates.find_by(template_type: template_type, is_default: true)
  end

  # Render a template with variable substitutions
  def render_template(template, variables = {})
    content = template.content.dup
    
    # Replace variables in format {{variable_name}}
    content.gsub!(/\{\{([^}]+)\}\}/) do |match|
      variable_name = $1.strip
      variables[variable_name] || variables[variable_name.to_sym] || "{{#{variable_name}}}"
    end
    
    content
  end

  # Extract variable names from a template
  def extract_variables(template)
    variables = {}
    template_json = template.variables || {}
    
    # Extract variables from the template content
    template.content.scan(/\{\{([^}]+)\}\}/) do |match|
      variable_name = match[0].strip
      variables[variable_name] = template_json[variable_name] || { description: "No description available" }
    end
    
    variables
  end
  
  # Track template usage
  def track_usage(template, user, conversation_session = nil, options = {})
    usage = TemplateUsage.create!(
      organization_template: template,
      user: user,
      conversation_session_id: conversation_session&.id,
      response_time: options[:response_time],
      token_count: options[:token_count],
      metrics: options[:metrics] || {}
    )
    
    # Update template usage statistics
    template.increment!(:usage_count)
    
    # Return the usage record
    usage
  end
  
  # Rate a template usage
  def rate_template_usage(template_usage, rating)
    return false unless (1..5).include?(rating)
    
    template_usage.update(rating: rating)
    template = template_usage.organization_template
    
    # Update template average rating
    rated_usages = template.template_usages.where.not(rating: nil)
    avg_rating = rated_usages.average(:rating)
    template.update(average_rating: avg_rating)
    
    true
  end
  
  # Get template usage metrics
  def get_usage_metrics(template)
    usages = template.template_usages
    
    {
      total_usages: usages.count,
      average_response_time: usages.average(:response_time)&.round(2),
      average_token_count: usages.average(:token_count)&.round(0),
      average_rating: usages.where.not(rating: nil).average(:rating)&.round(1),
      rated_usages: usages.where.not(rating: nil).count
    }
  end
  
  # Get recent template usages
  def get_recent_usages(template, limit = 10)
    template.template_usages.includes(:user).order(created_at: :desc).limit(limit)
  end
end
