class OrganizationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization, except: [:index, :new, :create]
  before_action :ensure_organization_member, except: [:index, :new, :create]
  before_action :ensure_can_manage, only: [:edit, :update, :destroy, :settings, :invite_user]

  # GET /organizations
  def index
    @organizations = current_user.organizations.active
    @owned_organizations = current_user.organizations.active.joins(:organization_users)
                                       .where(organization_users: { user_id: current_user.id, role: 'owner' })
  end

  # GET /organizations/1
  def show
    redirect_to dashboard_organization_path(@organization)
  end

  # GET /organizations/new
  def new
    @organization = Organization.new
  end

  # GET /organizations/1/edit
  def edit
  end

  # POST /organizations
  def create
    @organization = Organization.new(organization_params)

    if @organization.save
      # Create owner role for the current user
      @organization.organization_users.create!(user: current_user, role: 'owner')
      redirect_to @organization, notice: 'Organization was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /organizations/1
  def update
    if @organization.update(organization_params)
      redirect_to @organization, notice: 'Organization was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /organizations/1
  def destroy
    @organization.update(active: false)
    redirect_to organizations_url, notice: 'Organization was successfully deactivated.'
  end

  # GET /organizations/1/dashboard
  def dashboard
    begin
      @documents = @organization.documents.order(created_at: :desc).limit(10)
      @document_count = @organization.documents.count
      @document_by_status = @organization.documents.group(:status).count
      @recent_uploads = @organization.documents.order(created_at: :desc).limit(5)
    rescue ActiveRecord::StatementInvalid => e
      # Handle the case where documents table doesn't exist yet
      @documents = []
      @document_count = 0
      @document_by_status = { "completed" => 0, "processing" => 0, "pending" => 0, "failed" => 0 }
      @recent_uploads = []
    end
    
    # Initialize search and RAG counts if not already set
    @search_count ||= 0
    @rag_count ||= 0
  end

  # GET /organizations/1/settings
  def settings
    @members = @organization.organization_users.includes(:user)
  end

  # POST /organizations/1/invite_user
  def invite_user
    email = params[:email]
    role = params[:role]
    
    # Check if email and role are valid
    unless email.present? && Organization.roles.include?(role)
      return redirect_to settings_organization_path(@organization), alert: 'Invalid email or role.'
    end
    
    # Check if user already exists
    user = User.find_by(email: email)
    
    if user
      # Check if user is already a member
      if @organization.users.include?(user)
        redirect_to settings_organization_path(@organization), alert: 'User is already a member of this organization.'
      else
        # Add user to organization
        @organization.organization_users.create!(user: user, role: role)
        redirect_to settings_organization_path(@organization), notice: 'User was successfully added to the organization.'
      end
    else
      # TODO: Implement invitation for non-existing users
      # For now, just show an alert
      redirect_to settings_organization_path(@organization), alert: 'User does not exist. Invitation functionality coming soon.'
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_organization
      @organization = Organization.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def organization_params
      params.require(:organization).permit(:name, :slug, :active, settings: [:max_documents, :max_queries_per_month, :advanced_search, :api_access])
    end
    
    # Check if current user belongs to the organization
    def ensure_organization_member
      unless @organization.users.include?(current_user)
        redirect_to organizations_path, alert: 'You do not have access to this organization.'
      end
    end
    
    # Check if current user can manage the organization (owner or admin)
    def ensure_can_manage
      role = @organization.organization_users.find_by(user: current_user)&.role
      unless role == 'owner' || role == 'admin'
        redirect_to organization_path(@organization), alert: 'You do not have permission to manage this organization.'
      end
    end
end
