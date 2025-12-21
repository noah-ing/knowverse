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

    # Build recent activities feed
    @recent_activities = build_recent_activities
  end

  def build_recent_activities
    activities = []

    # Document uploads (last 30 days)
    begin
      @organization.documents.where('created_at > ?', 30.days.ago).order(created_at: :desc).limit(10).each do |doc|
        activities << OpenStruct.new(
          title: "Document uploaded",
          description: doc.title.truncate(50),
          created_at: doc.created_at,
          icon: "document",
          color: "indigo"
        )
      end
    rescue => e
      Rails.logger.debug "Could not load document activities: #{e.message}"
    end

    # Document processing completions
    begin
      @organization.documents.where(status: 'processed').where('updated_at > ?', 30.days.ago)
        .where('updated_at != created_at').order(updated_at: :desc).limit(5).each do |doc|
        activities << OpenStruct.new(
          title: "Document processed",
          description: "#{doc.title.truncate(40)} is ready for search",
          created_at: doc.updated_at,
          icon: "check",
          color: "green"
        )
      end
    rescue => e
      Rails.logger.debug "Could not load processing activities: #{e.message}"
    end

    # Search queries
    begin
      if defined?(SearchQuery) && SearchQuery.table_exists?
        SearchQuery.where(organization_id: @organization.id).where('created_at > ?', 30.days.ago)
          .order(created_at: :desc).limit(10).each do |query|
          activities << OpenStruct.new(
            title: "Search performed",
            description: query.query_text.truncate(50),
            created_at: query.created_at,
            icon: "search",
            color: "blue"
          )
        end
      end
    rescue => e
      Rails.logger.debug "Could not load search activities: #{e.message}"
    end

    # Conversation sessions (RAG chats)
    begin
      if defined?(ConversationSession) && ConversationSession.table_exists?
        ConversationSession.where(organization_id: @organization.id).where('created_at > ?', 30.days.ago)
          .order(created_at: :desc).limit(10).each do |convo|
          activities << OpenStruct.new(
            title: "RAG conversation started",
            description: convo.title.present? ? convo.title.truncate(50) : "New conversation",
            created_at: convo.created_at,
            icon: "chat",
            color: "purple"
          )
        end
      end
    rescue => e
      Rails.logger.debug "Could not load conversation activities: #{e.message}"
    end

    # Embedding completions
    begin
      if defined?(VectorEmbedding) && VectorEmbedding.table_exists?
        VectorEmbedding.joins(:document).where(documents: { organization_id: @organization.id })
          .where(status: 'processed').where('vector_embeddings.updated_at > ?', 7.days.ago)
          .order('vector_embeddings.updated_at DESC').limit(5).each do |emb|
          activities << OpenStruct.new(
            title: "Embeddings generated",
            description: "#{emb.document&.title&.truncate(40)} (#{emb.embedding_model})",
            created_at: emb.updated_at,
            icon: "sparkles",
            color: "amber"
          )
        end
      end
    rescue => e
      Rails.logger.debug "Could not load embedding activities: #{e.message}"
    end

    # Sort all activities by created_at and take most recent
    activities.sort_by { |a| -a.created_at.to_i }.first(10)
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
