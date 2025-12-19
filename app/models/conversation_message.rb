class ConversationMessage < ApplicationRecord
  belongs_to :conversation_session
  
  # Valid roles for conversation messages
  VALID_ROLES = ['system', 'user', 'assistant'].freeze
  
  validates :conversation_session_id, presence: true
  validates :role, presence: true, inclusion: { in: VALID_ROLES }
  validates :content, presence: true
  
  # metadata column is PostgreSQL JSONB - serialization handled natively
  
  # Get approximate token count
  def token_count
    # Simple approximation: ~4 chars per token
    (content.length / 4.0).ceil
  end
  
  # Extract source references if present in metadata
  def source_references
    metadata['sources'] || []
  end
  
  # Check if this is a user message
  def user_message?
    role == 'user'
  end
  
  # Check if this is a system message
  def system_message?
    role == 'system'
  end
  
  # Check if this is an assistant message
  def assistant_message?
    role == 'assistant'
  end
  
  # Format for display
  def display_role
    case role
    when 'user'
      'User'
    when 'assistant'
      'KnowVerse'
    when 'system'
      'System'
    else
      role.capitalize
    end
  end
  
  # Format for LLM context
  def as_llm_context
    {
      role: role,
      content: content
    }
  end
end
