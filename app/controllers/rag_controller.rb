class RagController < ApplicationController
  include ActionController::Live
  
  before_action :authenticate_user!
  before_action :set_organization
  
  # Set organization from params
  private def set_organization
    @organization = Organization.find(params[:organization_id])
  end
  
  # Display RAG interface
  def index
    # Get available LLM providers
    providers_response = haystack_client.list_llm_providers
    @providers = providers_response.success? ? providers_response.data : []
    
    # Set default options
    @retrieval_options = {
      max_documents: 5,
      min_similarity: 0.75,
      strategy: "auto"
    }
    
    @generation_options = {
      temperature: 0.7,
      max_tokens: 500
    }
    
    # Get organization templates for RAG
    template_service = TemplateService.new(@organization)
    @templates = @organization.organization_templates.where(template_type: 'rag').order(name: :asc)
    @default_template = @templates.find_by(is_default: true)
    
    # If there's a template_id in params, use that template
    if params[:template_id].present?
      @selected_template = @organization.organization_templates.find_by(id: params[:template_id])
    end
    
    # Use the selected template, default template, or nil
    @template = @selected_template || @default_template
    
    # Extract variables if template exists
    @template_variables = @template ? template_service.extract_variables(@template) : {}
    
    # Check for conversation ID
    @conversation_id = params[:conversation_id]
    
    # If conversation ID is provided, load the conversation messages
    if @conversation_id.present?
      conversation = ConversationSession.find_by(
        id: @conversation_id,
        organization_id: @organization.id,
        user_id: current_user.id
      )
      
      # If conversation exists, load its messages
      if conversation.present?
        @messages = conversation.conversation_messages.order(created_at: :asc)
      else
        @messages = []
      end
    else
      @messages = []
    end
  end
  
  # Stream RAG response using Server-Sent Events (SSE)
  def stream
    # Set headers for SSE
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["Connection"] = "keep-alive"
    
    # Get query from params
    @query = params[:query]
    
    if @query.blank?
      # Send error event and close connection
      response.stream.write("event: error\n")
      response.stream.write("data: #{JSON.generate({error: "Question cannot be blank"})}\n\n")
      response.stream.close
      return
    end
    
    # Extract provider from params
    provider = params[:provider].presence
    
    # Extract retrieval options from params
    retrieval_options = {
      max_documents: params[:max_documents].presence&.to_i || 5,
      min_similarity: params[:min_similarity].presence&.to_f || 0.75,
      strategy: params[:strategy].presence || "auto"
    }
    
    # Extract generation options from params
    generation_options = {
      temperature: params[:temperature].presence&.to_f || 0.7,
      max_tokens: params[:max_tokens].presence&.to_i || 500,
      model: params[:model].presence
    }
    
    # Get template if specified
    template_id = params[:template_id]
    template_service = TemplateService.new(@organization)
    template = template_service.find_template('rag', template_id)
    
    # Prepare template variables from params
    template_variables = {}
    if params[:template_variables].present? && params[:template_variables].is_a?(Hash)
      template_variables = params[:template_variables]
    end
    
    # Render the template with variables if available
    if template.present?
      system_prompt = template_service.render_template(template, template_variables.merge({
        query: @query,
        organization: @organization.name,
        user: current_user.email
      }))
      generation_options[:system_prompt] = system_prompt
    elsif params[:system_prompt].present?
      # If no template but system prompt provided, use that
      generation_options[:system_prompt] = params[:system_prompt]
    end
    
    # Extract or create conversation, with template association if specified
    conversation = find_or_create_conversation(params[:conversation_id], template&.id)
    
    # Add user message to conversation
    user_message = conversation.add_user_message(@query)
    
    # Set initial metadata for tracking
    response_metadata = {}
    
    # Prepare complete response buffer
    complete_response = ""
    sources = []
    
    # Set options for streaming
    options = {
      provider: provider,
      retrieval_strategy: retrieval_options[:strategy],
      max_documents: retrieval_options[:max_documents],
      similarity_threshold: retrieval_options[:min_similarity],
      temperature: generation_options[:temperature],
      max_tokens: generation_options[:max_tokens],
      model: generation_options[:model],
      system_prompt: generation_options[:system_prompt],
      conversation_id: conversation.id
    }
    
    # Start streaming response
    begin
      haystack_client.generate_answer_stream(@query, @organization.id, options) do |event|
        # Process each event type
        case event[:type]
        when :metadata
          # Store metadata for later reference
          response_metadata = event[:data]
          response.stream.write("event: metadata\n")
          response.stream.write("data: #{JSON.generate(event[:data].merge(conversation_id: conversation.id))}\n\n")
        
        when :token
          # Add token to complete response
          complete_response += event[:data][:token]
          
          # Store token in StreamingElement if conversation exists
          if conversation
            token_index = event[:data][:id] || conversation.streaming_elements.count
            # Check for source reference in this token
            has_source = event[:data][:has_source] || false
            
            # Add to streaming elements
            conversation.add_streaming_token(
              event[:data][:token],
              token_index,
              false, # not complete
              has_source ? sources : nil
            )
          end
          
          # Forward token to browser
          response.stream.write("event: token\n")
          response.stream.write("data: #{JSON.generate(event[:data])}\n\n")
          
        when :sources
          # Store sources for highlighting and message metadata
          sources = event[:data][:sources] || []
          
          # Forward sources to browser
          response.stream.write("event: sources\n")
          response.stream.write("data: #{JSON.generate(event[:data])}\n\n")
        
        when :complete
          # Store sources for message metadata
          sources = event[:data][:sources] || []
          
          # Mark streaming as complete for the last token
          if conversation && conversation.streaming_elements.any?
            StreamingElement.mark_complete(conversation.id)
          end
          
          # Convert streaming tokens to a message or create a new message
          assistant_message = if conversation && conversation.streaming_elements.any?
            # Create message from streaming tokens and their source references
            conversation.finalize_streaming({
              sources: sources,
              metrics: event[:data][:metrics],
              provider: event[:data][:provider]
            })
          else
            # Fallback to direct message creation (for compatibility)
            conversation.add_assistant_message(
              complete_response,
              {
                sources: sources,
                metrics: event[:data][:metrics],
                provider: event[:data][:provider]
              }
            )
          end
          
          # Include the message ID in the response
          event_data = event[:data].merge(
            conversation_id: conversation.id,
            message_id: assistant_message.id
          )
          
          # Forward to browser
          response.stream.write("event: complete\n")
          response.stream.write("data: #{JSON.generate(event_data)}\n\n")
        
        when :error
          # Forward error to browser
          response.stream.write("event: error\n")
          response.stream.write("data: #{JSON.generate(event[:data])}\n\n")
        
        when :fallback
          # Forward fallback event to browser
          response.stream.write("event: fallback\n")
          response.stream.write("data: #{JSON.generate(event[:data])}\n\n")
        
        when :metric
          # Forward metrics to browser
          response.stream.write("event: metric\n")
          response.stream.write("data: #{JSON.generate(event[:data])}\n\n")
        
        else
          # Generic event handler
          response.stream.write("event: #{event[:type]}\n")
          response.stream.write("data: #{JSON.generate(event[:data])}\n\n")
        end
      end
    rescue => e
      # Handle exceptions during streaming
      error_message = "Streaming error: #{e.message}"
      Rails.logger.error(error_message)
      Rails.logger.error(e.backtrace.join("\n"))
      
      # Add error message to conversation
      conversation.add_system_message("Error: #{error_message}", { error: true })
      
      # Send error to browser
      response.stream.write("event: error\n")
      response.stream.write("data: #{JSON.generate({error: error_message})}\n\n")
    ensure
      # Always close the stream
      response.stream.close
    end
  end
  
  # Get conversation messages for multi-turn context
  def conversation
    conversation_id = params[:conversation_id]
    
    if conversation_id.blank?
      render json: { error: "Conversation ID is required" }, status: :bad_request
      return
    end
    
    # Find conversation
    conversation = ConversationSession.find_by(
      id: conversation_id,
      organization_id: @organization.id,
      user_id: current_user.id
    )
    
    if conversation.nil?
      render json: { error: "Conversation not found" }, status: :not_found
      return
    end
    
    # Get messages
    messages = conversation.conversation_messages.order(created_at: :asc)
    
    # Return conversation context
    render json: {
      conversation: {
        id: conversation.id,
        title: conversation.title,
        created_at: conversation.created_at,
        updated_at: conversation.updated_at,
        last_message_at: conversation.last_message_at
      },
      messages: messages.map do |msg|
        {
          id: msg.id,
          role: msg.role,
          content: msg.content,
          created_at: msg.created_at,
          metadata: msg.metadata
        }
      end
    }
  end
  # Find or create a conversation based on ID
  private def find_or_create_conversation(conversation_id, template_id = nil)
    if conversation_id.present?
      # Try to find existing conversation
      conversation = ConversationSession.find_by(
        id: conversation_id,
        organization_id: @organization.id,
        user_id: current_user.id
      )
      
      # If template_id is provided and conversation exists, update its template
      if conversation.present? && template_id.present? && conversation.organization_template_id != template_id
        conversation.update(organization_template_id: template_id)
      end
      
      return conversation if conversation.present?
    end
    
    # Create a new conversation if not found
    ConversationSession.create!(
      organization: @organization,
      user: current_user,
      organization_template_id: template_id,
      title: "Q&A #{Time.current.strftime('%Y-%m-%d %H:%M')}",
      last_message_at: Time.current
    )
  end
  
  # Helper to track template usage after completion
  private def track_template_usage(template, conversation, start_time, metrics)
    return unless template.present?
    
    # Calculate response time
    response_time = (Time.current - start_time).to_f
    
    # Get token count from metrics if available
    token_count = metrics['token_count'] if metrics.present?
    
    # Track the usage
    template_service = TemplateService.new(@organization)
    template_service.track_usage(
      template,
      current_user,
      conversation,
      {
        response_time: response_time,
        token_count: token_count,
        metrics: metrics
      }
    )
  end
  
  # Helper method to get the Haystack client
  private def haystack_client
    HaystackClient.new
  end
end
