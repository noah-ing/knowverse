class ConversationMessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :set_conversation
  
  # List messages for a conversation
  def index
    @messages = @conversation.conversation_messages.order(created_at: :asc)
    
    respond_to do |format|
      format.html
      format.json { render json: @messages }
      format.turbo_stream
    end
  end
  
  # Create a new message
  def create
    @message = @conversation.conversation_messages.new(message_params)
    
    if @message.save
      # Update conversation last_message_at
      @conversation.update(last_message_at: Time.current)
      
      respond_to do |format|
        format.html { redirect_to organization_conversation_path(@organization, @conversation) }
        format.json { render json: @message, status: :created }
        format.turbo_stream { render turbo_stream: turbo_stream.append("conversation_messages", partial: "conversation_messages/message", locals: { message: @message }) }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @message.errors, status: :unprocessable_entity }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("new_message_form", partial: "conversation_messages/form", locals: { message: @message }) }
      end
    end
  end
  
  # Bulk create messages
  def bulk_create
    @messages = []
    
    # Wrap in a transaction for atomicity
    ConversationMessage.transaction do
      message_params_collection.each do |message_attrs|
        @messages << @conversation.conversation_messages.create!(message_attrs)
      end
      
      # Update conversation last_message_at
      @conversation.update!(last_message_at: Time.current)
    end
    
    respond_to do |format|
      format.html { redirect_to organization_conversation_path(@organization, @conversation) }
      format.json { render json: @messages, status: :created }
      format.turbo_stream do
        @messages.map do |message|
          turbo_stream.append("conversation_messages", partial: "conversation_messages/message", locals: { message: message })
        end
      end
    end
  rescue => e
    # Handle error
    respond_to do |format|
      format.html { redirect_to organization_conversation_path(@organization, @conversation), alert: "Error creating messages: #{e.message}" }
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
      format.turbo_stream { render turbo_stream: turbo_stream.replace("new_message_form", html: "<div class='alert alert-danger'>#{e.message}</div>") }
    end
  end
  
  private
  
  def set_organization
    @organization = Current.organization
  end
  
  def set_conversation
    @conversation = ConversationSession.find(params[:conversation_id])
    
    # Ensure conversation belongs to current user and organization
    unless @conversation.user_id == current_user.id && @conversation.organization_id == @organization.id
      respond_to do |format|
        format.html { redirect_to organization_conversations_path(@organization), alert: "Conversation not found" }
        format.json { render json: { error: "Conversation not found" }, status: :not_found }
        format.turbo_stream { head :not_found }
      end
    end
  end
  
  def message_params
    params.require(:message).permit(:role, :content, metadata: {})
  end
  
  def message_params_collection
    params.require(:messages).map do |message_params|
      message_params.permit(:role, :content, metadata: {})
    end
  end
end
