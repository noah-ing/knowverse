class CreateConversationMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :conversation_messages do |t|
      t.references :conversation_session, null: false, foreign_key: true, index: true
      t.string :role, null: false
      t.text :content, null: false
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :conversation_messages, [:conversation_session_id, :created_at], name: 'idx_conv_msgs_on_conv_session_id_and_created_at'
    add_index :conversation_messages, :role
  end
end
