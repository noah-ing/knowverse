class Admin::DomainConfidenceController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!
  before_action :set_organization, except: [:index]
  
  # GET /admin/domain_confidence
  def index
    @organizations = current_user.organizations.order(:name)
    
    # Select the first organization or the one specified by params
    if params[:organization_id].present?
      @organization = Organization.find(params[:organization_id])
    else
      @organization = @organizations.first
    end
    
    redirect_to admin_domain_confidence_path(@organization) if @organization
  end
  
  # GET /admin/domain_confidence/:id
  def show
    @confidence_scores = @organization.domain_confidence_scores
                                     .group(:domain)
                                     .select('domain, 
                                              AVG(total_score) AS avg_score, 
                                              COUNT(*) AS query_count, 
                                              SUM(CASE WHEN was_successful THEN 1 ELSE 0 END) AS success_count')
                                     .order('avg_score DESC')
                                     
    @domains = @organization.vector_domains
    
    # Recent confidence scores for trends
    @recent_scores = @organization.domain_confidence_scores
                                 .order(created_at: :desc)
                                 .limit(100)
                                 .group_by(&:domain)
  end
  
  # GET /admin/domain_confidence/:id/settings
  def settings
    # Load existing settings
  end
  
  # PATCH /admin/domain_confidence/:id/settings
  def update_settings
    if @organization.update(organization_params)
      flash[:notice] = "Confidence threshold settings updated successfully."
      redirect_to admin_domain_confidence_path(@organization)
    else
      flash.now[:alert] = "Failed to update settings: #{@organization.errors.full_messages.join(', ')}"
      render :settings
    end
  end
  
  # GET /admin/domain_confidence/:id/test
  def test
    @query = params[:query]
    
    if @query.present?
      domain_manager = DomainConfidenceManager.new
      @domains = domain_manager.determine_domains(@query, @organization.id)
      
      @results = []
      
      @domains.each do |domain|
        confidence_scorer = ConfidenceScorer.new
        score_result = confidence_scorer.calculate_score(
          @query, domain, @organization.id, 
          skip_tracking: true
        )
        
        @results << {
          domain: domain,
          score: score_result[:score],
          factors: score_result[:factors]
        }
      end
    end
  end
  
  private
  
  def set_organization
    @organization = Organization.find(params[:id])
    authorize_organization!(@organization)
  end
  
  def organization_params
    params.require(:organization).permit(
      :domain_confidence_primary_threshold,
      :domain_confidence_secondary_threshold,
      :enable_domain_fallback
    )
  end
  
  def require_admin!
    unless current_user.admin? || current_user.organization_users.exists?(role: 'owner')
      flash[:alert] = "You must be an admin to access this page."
      redirect_to root_path
    end
  end
  
  def authorize_organization!(organization)
    unless current_user.admin? || current_user.organizations.include?(organization)
      flash[:alert] = "You don't have access to this organization."
      redirect_to root_path
    end
  end
end
