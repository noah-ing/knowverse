class CreateConversationSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :conversation_sessions do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.boolean :pinned, default: false
      t.jsonb :metadata, default: {}
      t.datetime :last_message_at

      t.timestamps
    end

    add_index :conversation_sessions, [:organization_id, :user_id], name: 'idx_conversation_sessions_org_use'
    add_index :conversation_sessions, :last_message_at
  end
end
