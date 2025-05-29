class ConversationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :set_conversation, only: [:show, :update, :destroy]
  
  # List conversations for the current organization and user
  def index
    @conversations = ConversationSession
      .where(organization: @organization, user: current_user)
      .order(last_message_at: :desc, created_at: :desc)
      .page(params[:page])
      .per(20)
    
    respond_to do |format|
      format.html
      format.json { render json: @conversations }
      format.turbo_stream
    end
  end
  
  # Show conversation details and history
  def show
    @messages = @conversation.conversation_messages.order(created_at: :asc)
    
    respond_to do |format|
      format.html
      format.json { render json: { conversation: @conversation, messages: @messages } }
      format.turbo_stream
    end
  end
  
  # Create a new conversation
  def create
    @conversation = ConversationSession.new(conversation_params)
    @conversation.organization = @organization
    @conversation.user = current_user
    @conversation.last_message_at = Time.current
    
    # Add initial system message if provided
    if params[:system_message].present?
      @conversation.conversation_messages.build(
        role: 'system',
        content: params[:system_message]
      )
    end
    
    if @conversation.save
      respond_to do |format|
        format.html { redirect_to organization_conversation_path(@organization, @conversation), notice: "Conversation created" }
        format.json { render json: @conversation, status: :created }
        format.turbo_stream { render turbo_stream: turbo_stream.append("conversations", partial: "conversations/conversation", locals: { conversation: @conversation }) }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @conversation.errors, status: :unprocessable_entity }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("new_conversation_form", partial: "conversations/form", locals: { conversation: @conversation }) }
      end
    end
  end
  
  # Update conversation details (title, pinned status)
  def update
    if @conversation.update(conversation_params)
      respond_to do |format|
        format.html { redirect_to organization_conversation_path(@organization, @conversation), notice: "Conversation updated" }
        format.json { render json: @conversation }
        format.turbo_stream { render turbo_stream: turbo_stream.replace(@conversation, partial: "conversations/conversation", locals: { conversation: @conversation }) }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @conversation.errors, status: :unprocessable_entity }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("edit_conversation_form", partial: "conversations/form", locals: { conversation: @conversation }) }
      end
    end
  end
  
  # Delete a conversation
  def destroy
    @conversation.destroy
    
    respond_to do |format|
      format.html { redirect_to organization_conversations_path(@organization), notice: "Conversation deleted" }
      format.json { head :no_content }
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@conversation) }
    end
  end
  
  # Get or create a conversation by ID
  def find_or_create
    conversation_id = params[:conversation_id]
    
    if conversation_id.present?
      @conversation = ConversationSession.find_by(id: conversation_id)
      
      # If conversation exists but doesn't belong to current user/org, create a new one
      if @conversation && (@conversation.user_id != current_user.id || @conversation.organization_id != @organization.id)
        @conversation = nil
      end
    end
    
    # Create new conversation if not found
    if @conversation.nil?
      @conversation = ConversationSession.create(
        organization: @organization,
        user: current_user,
        title: "New Conversation #{Time.current.strftime('%Y-%m-%d %H:%M')}",
        last_message_at: Time.current
      )
    end
    
    render json: @conversation
  end
  
  private
  
  def set_organization
    @organization = Current.organization
  end
  
  def set_conversation
    @conversation = ConversationSession.find(params[:id])
    
    # Ensure conversation belongs to current user and organization
    unless @conversation.user_id == current_user.id && @conversation.organization_id == @organization.id
      redirect_to organization_conversations_path(@organization), alert: "Conversation not found"
    end
  end
  
  def conversation_params
    params.require(:conversation).permit(:title, :pinned)
  end
end
