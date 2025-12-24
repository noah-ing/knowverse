class CreateDocumentSources < ActiveRecord::Migration[8.0]
  def change
    create_table :document_sources do |t|
      t.references :organization, null: false, foreign_key: true
      t.integer :source_type, null: false, default: 0
      t.string :name
      t.text :credentials  # Encrypted via Rails encrypts
      t.datetime :last_sync_at
      t.string :sync_status, default: 'disconnected'
      t.text :sync_error
      t.jsonb :settings, default: {}
      t.timestamps
    end

    # Add external tracking columns to documents
    add_column :documents, :document_source_id, :bigint
    add_column :documents, :external_id, :string
    add_column :documents, :external_url, :string

    add_index :documents, :document_source_id
    add_index :documents, [:document_source_id, :external_id], unique: true, where: "document_source_id IS NOT NULL"
    add_foreign_key :documents, :document_sources
  end
end
