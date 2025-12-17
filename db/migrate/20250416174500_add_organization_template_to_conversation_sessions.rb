class AddOrganizationTemplateToConversationSessions < ActiveRecord::Migration[7.0]
  def change
    # Only add this reference if the conversation_sessions table exists
    if ActiveRecord::Base.connection.table_exists?(:conversation_sessions)
      # Add template_id to conversation_sessions table
      add_reference :conversation_sessions, :organization_template, null: true, foreign_key: true
    end
  end
end
