class StreamingElement < ApplicationRecord
  # Table existence check
  def self.table_exists?
    @table_exists ||= ActiveRecord::Base.connection.table_exists?(:streaming_elements)
  rescue
    @table_exists = false
  end
  
  # Only define ActiveRecord relations and validations if table exists
  if table_exists?
    belongs_to :conversation_session

    # Validations
    validates :token_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    # Scopes
    scope :ordered, -> { order(token_index: :asc) }
    scope :for_conversation, ->(conversation_session_id) { where(conversation_session_id: conversation_session_id) }
    scope :completed, -> { where(complete: true) }
  end
  
  # Methods to support streaming - all with table_exists? checks
  
  # Get all tokens for a conversation as a single string
  def self.tokens_text(conversation_id)
    return "" unless table_exists?
    for_conversation(conversation_id).ordered.pluck(:token).join('')
  rescue
    # Return empty string if any error occurs
    ""
  end
  
  # Get all source references for a conversation
  def self.conversation_sources(conversation_id)
    return [] unless table_exists?
    for_conversation(conversation_id).where.not(source_references: nil).pluck(:source_references).flatten
  rescue
    # Return empty array if any error occurs
    []
  end
  
  # Create a new token in the stream
  def self.add_token(conversation_session_id, token, index, complete = false, sources = nil)
    return nil unless table_exists?
    begin
      create(
        conversation_session_id: conversation_session_id,
        token: token,
        token_index: index,
        complete: complete,
        source_references: sources
      )
    rescue => e
      Rails.logger.error("Failed to add streaming token: #{e.message}")
      nil
    end
  end
  
  # Mark a stream as complete
  def self.mark_complete(conversation_session_id)
    return false unless table_exists?
    begin
      last_token = for_conversation(conversation_session_id).ordered.last
      last_token.update(complete: true) if last_token
    rescue => e
      Rails.logger.error("Failed to mark streaming complete: #{e.message}")
      false
    end
  end
end
