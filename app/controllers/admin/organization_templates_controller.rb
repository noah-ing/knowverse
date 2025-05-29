module Admin
  class OrganizationTemplatesController < AdminController
    before_action :set_organization
    before_action :set_template, only: [:show, :edit, :update, :destroy, :set_default, :test, :analytics]
    
    def index
      @templates = @organization.organization_templates.order(name: :asc)
    end
    
    def show
      @template_service = TemplateService.new(@organization)
      @variables = @template_service.extract_variables(@template)
      @usage_metrics = @template_service.get_usage_metrics(@template)
      @recent_usages = @template_service.get_recent_usages(@template, 5)
    end
    
    def new
      @template = @organization.organization_templates.new
    end
    
    def create
      @template = @organization.organization_templates.new(template_params)
      
      # If this is the first template of its type, make it the default
      if @organization.organization_templates.where(template_type: @template.template_type).count == 0
        @template.is_default = true
      end
      
      if @template.save
        # If it's marked as default, ensure no other template of the same type is default
        if @template.is_default?
          @organization.organization_templates
            .where(template_type: @template.template_type)
            .where.not(id: @template.id)
            .update_all(is_default: false)
        end
        
        redirect_to admin_organization_organization_template_path(@organization, @template),
                    notice: "Template was successfully created."
      else
        render :new
      end
    end
    
    def edit
      @template_service = TemplateService.new(@organization)
      @variables = @template_service.extract_variables(@template)
    end
    
    def update
      was_default = @template.is_default?
      
      if @template.update(template_params)
        # If it's now marked as default and wasn't before, ensure no other template of the same type is default
        if @template.is_default? && !was_default
          @organization.organization_templates
            .where(template_type: @template.template_type)
            .where.not(id: @template.id)
            .update_all(is_default: false)
        end
        
        # If it was default and now isn't, we need to set a new default
        if was_default && !@template.is_default?
          # Get other templates of the same type
          other_templates = @organization.organization_templates
            .where(template_type: @template.template_type)
            .where.not(id: @template.id)
          
          # If there are any, set the first one as default
          if other_templates.any?
            other_templates.first.update(is_default: true)
          end
        end
        
        redirect_to admin_organization_organization_template_path(@organization, @template),
                    notice: "Template was successfully updated."
      else
        render :edit
      end
    end
    
    def destroy
      was_default = @template.is_default?
      template_type = @template.template_type
      
      @template.destroy
      
      # If it was the default, set a new default
      if was_default
        # Get other templates of the same type
        other_template = @organization.organization_templates
          .where(template_type: template_type)
          .first
        
        # If there are any, set the first one as default
        other_template&.update(is_default: true)
      end
      
      redirect_to admin_organization_organization_templates_path(@organization),
                  notice: "Template was successfully deleted."
    end
    
    def set_default
      # Ensure no other template of the same type is default
      @organization.organization_templates
        .where(template_type: @template.template_type)
        .where.not(id: @template.id)
        .update_all(is_default: false)
      
      @template.update(is_default: true)
      
      redirect_to admin_organization_organization_template_path(@organization, @template),
                  notice: "Template has been set as the default for #{@template.template_type.humanize} interactions."
    end
    
    def test
      @template_service = TemplateService.new(@organization)
      @variables = @template_service.extract_variables(@template)
      
      if request.post?
        # Handle the submission of test variables
        test_variables = params[:variables] || {}
        @rendered_content = @template_service.render_template(@template, test_variables)
        
        # If it's an AJAX request, return JSON
        respond_to do |format|
          format.html
          format.json { render json: { rendered_content: @rendered_content } }
        end
      end
    end
    
    def analytics
      @template_service = TemplateService.new(@organization)
      @usage_metrics = @template_service.get_usage_metrics(@template)
      
      # Date range for analytics
      @start_date = params[:start_date] ? Date.parse(params[:start_date]) : 30.days.ago.to_date
      @end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.today
      
      # Fetch usages within the date range
      @usages = @template.template_usages
        .where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
        .order(created_at: :desc)
      
      # Calculate daily usage statistics
      @daily_stats = @usages
        .group_by { |u| u.created_at.to_date }
        .transform_values do |day_usages|
          {
            count: day_usages.count,
            avg_response_time: day_usages.map(&:response_time).compact.sum / day_usages.count.to_f,
            avg_token_count: day_usages.map(&:token_count).compact.sum / day_usages.count.to_f,
            ratings: day_usages.map(&:rating).compact
          }
        end
    end
    
    private
    
    def set_organization
      @organization = Organization.find(params[:organization_id])
    end
    
    def set_template
      @template = @organization.organization_templates.find(params[:id])
    end
    
    def template_params
      params.require(:organization_template).permit(
        :name, :description, :content, :template_type, :is_default,
        variables: {}
      )
    end
  end
end
