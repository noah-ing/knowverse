module Admin
  class DomainEmbeddingModelsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin_role
    before_action :set_organization
    before_action :set_domain_model, only: [:show, :edit, :update, :destroy, :toggle_active, :retrain]
    
    def index
      @domain_models = @organization.domain_embedding_models.order(created_at: :desc)
    end
    
    def show
      @documents_count = @organization.documents
                                      .joins(:vector_embeddings)
                                      .where(vector_embeddings: { domain_embedding_model_id: @domain_model.id })
                                      .distinct
                                      .count
    end
    
    def new
      @domain_model = @organization.domain_embedding_models.new
    end
    
    def create
      @domain_model = @organization.domain_embedding_models.new(domain_model_params)
      @domain_model.performance_metrics = { accuracy: 0.0, latency: 0.0 }
      @domain_model.active = false
      
      respond_to do |format|
        if @domain_model.save
          format.html { redirect_to admin_organization_domain_embedding_model_path(@organization, @domain_model), 
                        notice: "Domain embedding model was successfully created." }
        else
          format.html { render :new, status: :unprocessable_entity }
        end
      end
    end
    
    def edit
    end
    
    def update
      respond_to do |format|
        if @domain_model.update(domain_model_params)
          format.html { redirect_to admin_organization_domain_embedding_model_path(@organization, @domain_model), 
                        notice: "Domain embedding model was successfully updated." }
        else
          format.html { render :edit, status: :unprocessable_entity }
        end
      end
    end
    
    def destroy
      if @domain_model.vector_embeddings.exists?
        redirect_to admin_organization_domain_embedding_models_path(@organization), 
                    alert: "Cannot delete a domain model that has associated embeddings."
        return
      end
      
      @domain_model.destroy
      
      redirect_to admin_organization_domain_embedding_models_path(@organization), 
                  notice: "Domain embedding model was successfully deleted."
    end
    
    def toggle_active
      @domain_model.update(active: !@domain_model.active)
      
      redirect_to admin_organization_domain_embedding_model_path(@organization, @domain_model), 
                  notice: "Domain model #{@domain_model.active? ? 'activated' : 'deactivated'} successfully."
    end
    
    def retrain
      # Enqueue a job to retrain the model
      DocumentProcessing::DomainModelTrainingJob.perform_later(
        @domain_model.id, 
        @organization.id
      )
      
      redirect_to admin_organization_domain_embedding_model_path(@organization, @domain_model), 
                  notice: "Domain model retraining job queued successfully."
    end
    
    # Generate embeddings for a batch of documents using this domain model
    def generate_embeddings
      document_ids = params[:document_ids]
      domain = params[:domain]
      model_name = params[:model_name]
      
      if document_ids.blank?
        redirect_to admin_organization_domain_embedding_models_path(@organization), 
                    alert: "No documents selected for embedding generation."
        return
      end
      
      # Enqueue job to generate domain-specific embeddings
      DocumentProcessing::DomainEmbeddingWorker.perform_async(
        document_ids, 
        domain, 
        model_name, 
        @organization.id
      )
      
      redirect_to admin_organization_domain_embedding_models_path(@organization), 
                  notice: "Domain-specific embedding generation started for #{document_ids.size} documents."
    end
    
    private
    
    def set_organization
      @organization = Organization.find(params[:organization_id])
    end
    
    def set_domain_model
      @domain_model = @organization.domain_embedding_models.find(params[:id])
    end
    
    def domain_model_params
      params.require(:domain_embedding_model).permit(
        :name, :domain, :description, :base_model, :dimension, :version,
        :configuration
      )
    end
    
    def require_admin_role
      unless current_user.admin? || current_user.organization_admin?(@organization)
        redirect_to root_path, alert: "You don't have permission to access this page."
      end
    end
  end
end
