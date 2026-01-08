# frozen_string_literal: true

class DocumentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :ensure_organization_member
  before_action :set_document, only: [:show, :edit, :update, :destroy, :status, :content]

  def index
    return handle_missing_table("documents") unless table_exists?("documents")
    apply_filters_and_sorting(@organization.documents)
  end

  def show; end
  def edit; end

  def new
    return handle_missing_table("documents") unless table_exists?("documents")
    @document = @organization.documents.new
  end

  def create
    service = Documents::ProcessingService.new(@organization)
    @document = service.create_document(document_params)
    return render(:new, status: :unprocessable_entity) unless @document.save

    begin
      service.process_document_sync(@document)
      redirect_to organization_document_path(@organization, @document), notice: service.processing_notice(@document)
    rescue StandardError => e
      log_error("DOCUMENT PROCESSING FAILED", e)
      redirect_to organization_document_path(@organization, @document), alert: "Document saved but processing failed: #{e.message.first(100)}"
    end
  end

  def update
    if @document.update(document_params)
      redirect_to organization_document_path(@organization, @document), notice: 'Document was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def bulk_destroy
    result = Documents::DeletionService.new(@organization).bulk_delete(params[:ids])
    notice = result[:success] ? "#{result[:count]} document(s) deleted successfully." : nil
    redirect_to organization_documents_path(@organization), notice: notice, alert: result[:error]
  end

  def destroy
    Documents::DeletionService.new(@organization).delete_document(@document)
    redirect_to organization_documents_path(@organization), notice: 'Document was successfully destroyed.'
  rescue StandardError => e
    log_error("Error deleting document", e)
    redirect_to organization_documents_path(@organization), alert: "Could not delete document. Error: #{e.message.split("\n").first}"
  end

  def upload
    if @organization.documents.count >= @organization.max_documents.to_i
      return redirect_to organization_documents_path(@organization), alert: 'Organization has reached maximum number of documents.'
    end

    service = Documents::ProcessingService.new(@organization)
    saved = service.upload_files(params[:files])

    if saved.any?
      service.queue_for_processing(saved)
      redirect_to organization_documents_path(@organization), notice: "#{saved.size} document(s) uploaded and queued for processing."
    else
      redirect_to organization_documents_path(@organization), alert: 'No files were selected for upload.'
    end
  end

  def status
    render json: { id: @document.id, title: @document.title, status: @document.status,
                   embedding_status: @document.embedding_status, word_count: @document.word_count,
                   created_at: @document.created_at, updated_at: @document.updated_at }
  end

  def content
    render json: { id: @document.id, title: @document.title, content: @document.content, word_count: @document.word_count }
  end

  def start_processing
    @document.update(status: 'processing')
    DocumentProcessing::TextExtractionWorker.perform_async(@document.id)
    redirect_to organization_document_path(@organization, @document), notice: 'Document processing started.'
  end

  def retry_processing
    @document.update(status: 'processing')
    DocumentProcessing::TextExtractionWorker.perform_async(@document.id)
    redirect_to organization_document_path(@organization, @document), notice: 'Document processing restarted.'
  end

  def search
    @query = params[:q]
    if @query.present?
      filter_service = Documents::FilterService.new(params)
      @documents = filter_service.apply_all(filter_service.search(@organization.documents, @query))
      @filter_params, @sort_field, @sort_direction = filter_service.filter_params, filter_service.sort_field, filter_service.sort_direction
    else
      @documents = Document.none
    end
    render :index
  end

  private

  def set_organization
    @organization = params[:organization_id].present? ? Organization.find(params[:organization_id]) : current_user.organizations.first
    redirect_to organizations_path, alert: 'Please create or join an organization first.' unless @organization
  end

  def set_document
    @document = @organization.documents.find(params[:id])
  end

  def document_params
    params.require(:document).permit(:title, :description, :file, metadata: {})
  end

  def ensure_organization_member
    redirect_to organizations_path, alert: 'You do not have access to this organization.' unless @organization.users.include?(current_user)
  end

  def handle_missing_table(table)
    @documents = []
    @document = OpenStruct.new
    @table_missing = true
    @missing_table = table
  end

  def apply_filters_and_sorting(documents)
    filter_service = Documents::FilterService.new(params)
    @documents = filter_service.apply_all(documents)
    @filter_params, @sort_field, @sort_direction = filter_service.filter_params, filter_service.sort_field, filter_service.sort_direction
  end

  def log_error(prefix, error)
    Rails.logger.error("#{prefix}: #{error.message}")
    Rails.logger.error(error.backtrace.first(10).join("\n"))
  end
end
