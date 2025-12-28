class CreateBulkUploads < ActiveRecord::Migration[8.0]
  def change
    create_table :bulk_uploads do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, default: 'pending', null: false
      t.integer :total_files, default: 0
      t.integer :processed_files, default: 0
      t.integer :failed_files, default: 0
      t.jsonb :metadata, default: {}
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :bulk_uploads, :status
    add_index :bulk_uploads, [:organization_id, :status]

    # Add bulk_upload reference to documents
    add_reference :documents, :bulk_upload, foreign_key: true, null: true
  end
end
