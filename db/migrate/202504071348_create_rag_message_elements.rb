class CreateRagMessageElements < ActiveRecord::Migration[8.0]
  def change
    create_table :rag_message_elements do |t|
      t.references :message_id, null: false, foreign_key: true
      t.text :content
      t.integer :token_index
      t.boolean :complete
      t.jsonb :source_references

      t.timestamps
    end
  end
end
