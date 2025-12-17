class CreateStreamingElementsV2 < ActiveRecord::Migration[8.0]
  def change
    # Instead of creating the table again, add additional functionality
    # to the existing streaming_elements table
    
    add_column :streaming_elements, :conversation_session_id, :integer, null: true
    add_index :streaming_elements, :conversation_session_id
    
    # Add additional fields that might be useful
    add_column :streaming_elements, :metadata, :jsonb, default: {}
  end
end
