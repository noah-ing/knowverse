class ConversationSession < ApplicationRecord
  belongs_to :organization
  belongs_to :user
  belongs_to :organization_template, optional: true
  
  has_many :conversation_messages, -> { order(created_at: :asc) }, dependent: :destroy
  has_many :streaming_elements, -> { order(token_index: :asc) }, dependent: :destroy
  
  validates :organization_id, presence: true
  validates :user_id, presence: true
  validates :title, presence: true
  
  # Generate a title based on the first message if not provided
  before_validation :generate_title, on: :create
  
  # Maximum messages to keep in active memory context
  MAX_CONTEXT_MESSAGES = 10
  
  # Get conversation context for LLM
  def context_for_llm(max_messages = MAX_CONTEXT_MESSAGES)
    # Get the most recent messages up to the limit
    recent_messages = conversation_messages.order(created_at: :desc).limit(max_messages).reverse
    
    # Format context for the LLM
    context = []
    recent_messages.each do |message|
      context << {
        role: message.role,
        content: message.content
      }
    end
    
    context
  end
  
  # Add a new message to the conversation
  def add_message(role, content, metadata = {})
    conversation_messages.create!(
      role: role,
      content: content,
      metadata: metadata
    )
  end
  
  # Add user message
  def add_user_message(content, metadata = {})
    add_message('user', content, metadata)
  end
  
  # Add assistant message
  def add_assistant_message(content, metadata = {})
    add_message('assistant', content, metadata)
  end
  
  # Check if streaming elements are available
  def streaming_available?
    begin
      # Check if the streaming elements table exists
      StreamingElement.table_exists?
    rescue
      false
    end
  end

  # Add streaming token to the conversation (safely)
  def add_streaming_token(token, index, complete = false, sources = nil)
    return nil unless streaming_available?
    StreamingElement.add_token(id, token, index, complete, sources)
  rescue => e
    Rails.logger.error("Error adding streaming token: #{e.message}")
    nil
  end
  
  # Get all streaming tokens as a text (safely)
  def streaming_text
    return "" unless streaming_available?
    StreamingElement.tokens_text(id)
  rescue => e
    Rails.logger.error("Error getting streaming text: #{e.message}")
    ""
  end
  
  # Convert streaming tokens to a full message and clear the stream (safely)
  def finalize_streaming(metadata = {})
    # Default metadata if streaming not available
    if !streaming_available?
      return add_assistant_message("Response not available", metadata.merge(error: "Streaming functionality unavailable"))
    end
    
    begin
      # Get the text from all tokens
      text = streaming_text
      
      # Use empty string if no text was retrieved
      text = "Response was empty" if text.blank?
      
      # Get any source references
      sources = StreamingElement.conversation_sources(id)
      
      # Add sources to metadata
      metadata[:sources] = sources if sources.present?
      
      # Create the full message
      message = add_assistant_message(text, metadata)
      
      # Optionally clear streaming tokens to save space
      # streaming_elements.delete_all
      
      message
    rescue => e
      # Fallback in case of error
      Rails.logger.error("Error finalizing streaming: #{e.message}")
      add_assistant_message("Error processing response", metadata.merge(error: e.message))
    end
  end
  
  # Add system message
  def add_system_message(content, metadata = {})
    add_message('system', content, metadata)
  end
  
  # Smart truncation based on token count
  def truncate_history(max_tokens = 4000)
    # Simple approximation: ~4 chars per token
    char_count = 0
    messages_to_keep = []
    
    # Always include the system message if it exists
    system_message = conversation_messages.find_by(role: 'system')
    if system_message
      messages_to_keep << system_message
      char_count += system_message.content.length
    end
    
    # Add remaining messages until we hit the token limit
    remaining_messages = conversation_messages.where.not(id: messages_to_keep.map(&:id)).order(created_at: :desc)
    
    remaining_messages.each do |message|
      # Rough estimation of tokens
      message_chars = message.content.length
      
      # If adding this message would exceed our limit, stop
      if (char_count + message_chars) / 4 > max_tokens
        break
      end
      
      messages_to_keep << message
      char_count += message_chars
    end
    
    # Delete messages not in our keep list
    conversation_messages.where.not(id: messages_to_keep.map(&:id)).destroy_all
  end
  
  private
  
  def generate_title
    return if title.present?
    
    # Find the first user message
    first_message = conversation_messages.find_by(role: 'user')
    
    if first_message
      # Use the first ~30 chars of the first message as the title
      self.title = first_message.content.truncate(30)
    else
      # Default title if no messages yet
      self.title = "Conversation #{Time.now.strftime('%Y-%m-%d %H:%M')}"
    end
  end
end
