class CreateStreamingElementsV2 < ActiveRecord::Migration[8.0]
  def change
    # Instead of creating the table again, add additional functionality
    # to the existing streaming_elements table

    unless column_exists?(:streaming_elements, :conversation_session_id)
      add_column :streaming_elements, :conversation_session_id, :integer, null: true
    end

    unless index_exists?(:streaming_elements, :conversation_session_id)
      add_index :streaming_elements, :conversation_session_id
    end

    # Add additional fields that might be useful
    unless column_exists?(:streaming_elements, :metadata)
      add_column :streaming_elements, :metadata, :jsonb, default: {}
    end
  end
end
