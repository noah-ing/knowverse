class CreateStreamingElements < ActiveRecord::Migration[8.0]
  def change
    create_table :streaming_elements do |t|
      t.references :conversation_session, null: false, foreign_key: true
      t.string :token
      t.integer :token_index
      t.boolean :complete, default: false
      t.jsonb :source_references

      t.timestamps
    end

    add_index :streaming_elements, :token_index
  end
end
