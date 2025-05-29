class DocumentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :ensure_organization_member
  before_action :set_document, only: [:show, :edit, :update, :destroy, :status, :content]

  # GET /organizations/:organization_id/documents
  def index
    if table_exists?("documents")
      @documents = @organization.documents
      
      # Apply filters
      @documents = apply_filters(@documents)
      
      # Apply sorting
      @documents = apply_sorting(@documents)
      
      # Paginate results (records per page from params or default to 10)
      per_page = params[:per_page].present? ? params[:per_page].to_i : 10
      @documents = @documents.page(params[:page] || 1).per(per_page)
    else
      # Table doesn't exist, provide empty collection
      @documents = []
      @table_missing = true
      @missing_table = "documents"
    end
  end

  # GET /organizations/:organization_id/documents/:id
  def show
  end

  # GET /organizations/:organization_id/documents/new
  def new
    if table_exists?("documents")
      @document = @organization.documents.new
    else
      # Table doesn't exist, still show the form but set flag
      @document = OpenStruct.new
      @table_missing = true
      @missing_table = "documents"
    end
  end

  # GET /organizations/:organization_id/documents/:id/edit
  def edit
  end

  # POST /organizations/:organization_id/documents
  def create
    @document = @organization.documents.new(document_params)

    if @document.save
      redirect_to organization_document_path(@organization, @document), notice: 'Document was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /organizations/:organization_id/documents/:id
  def update
    if @document.update(document_params)
      redirect_to organization_document_path(@organization, @document), notice: 'Document was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /organizations/:organization_id/documents/:id
  def destroy
    begin
      # Safe deletion strategy that handles missing relationships
      ActiveRecord::Base.transaction do
        # Find vector embeddings for this document
        embeddings = VectorEmbedding.where(document_id: @document.id)
        
        # For each embedding, first delete any related vector projections
        embeddings.each do |embedding|
          # Safely delete projections using direct SQL to avoid missing column errors
          begin
            ActiveRecord::Base.connection.execute(
              "DELETE FROM vector_projections WHERE vector_embedding_id = #{embedding.id}"
            )
          rescue => e
            Rails.logger.error "Error deleting vector projections: #{e.message}"
          end
        end
        
        # Then delete the embeddings directly
        VectorEmbedding.where(document_id: @document.id).delete_all
        
        # Handle other potential relationships
        ClusterMembership.where(document_id: @document.id).delete_all if defined?(ClusterMembership)
        SearchFeedback.where(document_id: @document.id).delete_all if defined?(SearchFeedback)
        
        # Finally delete the document
        @document.destroy!
      end
      
      redirect_to organization_documents_path(@organization), notice: 'Document was successfully destroyed.'
    rescue => e
      Rails.logger.error "Error deleting document: #{e.message}\n#{e.backtrace.join("\n")}"
      redirect_to organization_documents_path(@organization), 
                  alert: "Could not delete document. Error: #{e.message.split("\n").first}"
    end
  end
  
  # POST /organizations/:organization_id/documents/upload
  def upload
    # Check if organization has reached maximum number of documents
    if @organization.documents.count >= @organization.max_documents.to_i
      return redirect_to organization_documents_path(@organization), alert: 'Organization has reached maximum number of documents.'
    end
    
    # Handle file upload
    if params[:files].present?
      files = params[:files]
      
      # Process each uploaded file
      files.each do |file|
        document = @organization.documents.new(
          title: file.original_filename,
          file_type: file.content_type,
          status: 'pending',
          embedding_status: 'pending'
        )
        
        # Attach the file using ActiveStorage
        document.file.attach(file)
        
        if document.save
          # Enqueue background job for text extraction
          DocumentProcessing::TextExtractionWorker.perform_async(document.id)
        end
      end
      
      redirect_to organization_documents_path(@organization), notice: 'Documents were successfully uploaded and are being processed.'
    else
      redirect_to organization_documents_path(@organization), alert: 'No files were selected for upload.'
    end
  end
  
  # GET /organizations/:organization_id/documents/:id/status
  def status
    render json: {
      id: @document.id,
      title: @document.title,
      status: @document.status,
      embedding_status: @document.embedding_status,
      word_count: @document.word_count,
      created_at: @document.created_at,
      updated_at: @document.updated_at
    }
  end
  
  # GET /organizations/:organization_id/documents/:id/content
  def content
    render json: {
      id: @document.id,
      title: @document.title,
      content: @document.content,
      word_count: @document.word_count
    }
  end
  
  # POST /organizations/:organization_id/documents/:id/start_processing
  def start_processing
    @document.update(status: 'processing')
    DocumentProcessing::TextExtractionWorker.perform_async(@document.id)
    redirect_to organization_document_path(@organization, @document), notice: 'Document processing started.'
  end
  
  # POST /organizations/:organization_id/documents/:id/retry_processing
  def retry_processing
    @document.update(status: 'processing')
    DocumentProcessing::TextExtractionWorker.perform_async(@document.id)
    redirect_to organization_document_path(@organization, @document), notice: 'Document processing restarted.'
  end
  
  # GET /organizations/:organization_id/documents/search
  def search
    @query = params[:q]
    
    if @query.present?
      # Placeholder for search functionality
      # In a real implementation, this would use HaystackClient to perform semantic search
      # For now, we'll do a simple text search on title and content
      @documents = @organization.documents.where("title ILIKE ? OR content ILIKE ?", "%#{@query}%", "%#{@query}%")
      
      # Apply filters
      @documents = apply_filters(@documents)
      
      # Apply sorting
      @documents = apply_sorting(@documents)
      
      # Paginate results
      per_page = params[:per_page].present? ? params[:per_page].to_i : 10
      @documents = @documents.page(params[:page] || 1).per(per_page)
    else
      @documents = Document.none
    end
    
    render :index
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_organization
      @organization = Organization.find(params[:organization_id])
    end
    
    def set_document
      @document = @organization.documents.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def document_params
      params.require(:document).permit(:title, :description, :file, metadata: {})
    end
    
    # Check if current user belongs to the organization
    def ensure_organization_member
      unless @organization.users.include?(current_user)
        redirect_to organizations_path, alert: 'You do not have access to this organization.'
      end
    end
    
    # Apply filters to the document query
    def apply_filters(documents)
      # Store filter params for the view
      @filter_params = {}
      
      # Filter by document status
      if params[:status].present?
        documents = documents.where(status: params[:status])
        @filter_params[:status] = params[:status]
      end
      
      # Filter by embedding status
      if params[:embedding_status].present?
        documents = documents.where(embedding_status: params[:embedding_status])
        @filter_params[:embedding_status] = params[:embedding_status]
      end
      
      # Filter by document type
      if params[:file_type].present?
        documents = documents.where(file_type: params[:file_type])
        @filter_params[:file_type] = params[:file_type]
      end
      
      # Filter by date range (created_at)
      if params[:date_from].present?
        begin
          date_from = Date.parse(params[:date_from]).beginning_of_day
          documents = documents.where("created_at >= ?", date_from)
          @filter_params[:date_from] = params[:date_from]
        rescue ArgumentError
          # Invalid date format, ignore filter
        end
      end
      
      if params[:date_to].present?
        begin
          date_to = Date.parse(params[:date_to]).end_of_day
          documents = documents.where("created_at <= ?", date_to)
          @filter_params[:date_to] = params[:date_to]
        rescue ArgumentError
          # Invalid date format, ignore filter
        end
      end
      
      # Filter by search term
      if params[:q].present?
        documents = documents.where("title ILIKE ? OR content ILIKE ?", "%#{params[:q]}%", "%#{params[:q]}%")
        @filter_params[:q] = params[:q]
      end
      
      documents
    end
    
    # Apply sorting to the document query
    def apply_sorting(documents)
      @sort_field = params[:sort_by] || 'created_at'
      @sort_direction = params[:sort_direction] || 'desc'
      
      # Ensure sort_field is valid
      valid_sort_fields = ['created_at', 'title', 'status', 'embedding_status', 'file_type', 'word_count', 'updated_at']
      @sort_field = 'created_at' unless valid_sort_fields.include?(@sort_field)
      
      # Ensure sort_direction is valid
      @sort_direction = @sort_direction.downcase == 'asc' ? 'asc' : 'desc'
      
      documents.order("#{@sort_field} #{@sort_direction}")
    end
end
