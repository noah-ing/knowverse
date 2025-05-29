class Search::SearchFeedbacksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :set_search_query
  before_action :set_document, except: [:create]
  
  # POST /search/feedbacks
  def create
    @feedback = SearchFeedback.new(feedback_params)
    @feedback.organization = @organization
    @feedback.user = current_user
    
    if @feedback.save
      respond_to do |format|
        format.html { redirect_back fallback_location: results_search_path, notice: 'Feedback recorded. Thank you!' }
        format.json { render json: { success: true, message: 'Feedback recorded' }, status: :created }
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: results_search_path, alert: 'Unable to record feedback.' }
        format.json { render json: { success: false, errors: @feedback.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end
  
  # POST /search/thumbs_up/:search_query_id/:document_id
  def thumbs_up
    feedback = SearchFeedback.find_or_initialize_by(
      search_query_id: @search_query.id,
      document_id: @document.id,
      organization_id: @organization.id,
      user_id: current_user&.id
    )
    
    feedback.relevance_score = 5
    feedback.feedback_type = 'relevance_thumbs_up'
    
    if feedback.save
      respond_to do |format|
        format.html { redirect_back fallback_location: results_search_path, notice: 'Thanks for your positive feedback!' }
        format.json { render json: { success: true, message: 'Thumbs up recorded' } }
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: results_search_path, alert: 'Unable to record feedback.' }
        format.json { render json: { success: false, errors: feedback.errors.full_messages } }
      end
    end
  end
  
  # POST /search/thumbs_down/:search_query_id/:document_id
  def thumbs_down
    feedback = SearchFeedback.find_or_initialize_by(
      search_query_id: @search_query.id,
      document_id: @document.id,
      organization_id: @organization.id,
      user_id: current_user&.id
    )
    
    feedback.relevance_score = 1
    feedback.feedback_type = 'relevance_thumbs_down'
    
    if feedback.save
      respond_to do |format|
        format.html { redirect_back fallback_location: results_search_path, notice: 'Thanks for your feedback. We\'ll improve our results.' }
        format.json { render json: { success: true, message: 'Thumbs down recorded' } }
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: results_search_path, alert: 'Unable to record feedback.' }
        format.json { render json: { success: false, errors: feedback.errors.full_messages } }
      end
    end
  end
  
  private
  
  def set_organization
    @organization = current_user.organizations.find(params[:organization_id]) if params[:organization_id]
    @organization ||= current_user.organizations.first
    
    unless @organization
      respond_to do |format|
        format.html { redirect_to organizations_path, alert: 'Please create or join an organization first.' }
        format.json { render json: { error: 'Organization not found' }, status: :not_found }
      end
    end
  end
  
  def set_search_query
    @search_query = if params[:search_feedback] && params[:search_feedback][:search_query_id]
                      SearchQuery.find(params[:search_feedback][:search_query_id])
                    else
                      SearchQuery.find(params[:search_query_id])
                    end
                    
    unless @search_query && @search_query.organization_id == @organization.id
      respond_to do |format|
        format.html { redirect_to search_path, alert: 'Search query not found.' }
        format.json { render json: { error: 'Search query not found' }, status: :not_found }
      end
    end
  end
  
  def set_document
    @document = @organization.documents.find(params[:document_id])
    
    unless @document
      respond_to do |format|
        format.html { redirect_to search_path, alert: 'Document not found.' }
        format.json { render json: { error: 'Document not found' }, status: :not_found }
      end
    end
  end
  
  def feedback_params
    params.require(:search_feedback).permit(
      :search_query_id, 
      :document_id, 
      :relevance_score, 
      :feedback_type, 
      :comments,
      metadata: {}
    )
  end
end
