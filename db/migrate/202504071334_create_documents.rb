class CreateDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :documents do |t|
      t.string :title, null: false
      t.text :description
      t.string :file_type
      t.string :status, default: 'pending', null: false
      t.text :content
      t.string :embedding_status, default: 'pending', null: false
      t.references :organization, null: false, foreign_key: true
      t.integer :word_count, default: 0
      t.jsonb :metadata, default: {}

      t.timestamps
    end
    
    # Add vector column for embeddings
    execute "ALTER TABLE documents ADD COLUMN embedding vector(768)"
    
    # Add standard indexes for better query performance
    add_index :documents, :status
    add_index :documents, :embedding_status
    add_index :documents, :file_type
    add_index :documents, [:organization_id, :status], name: 'idx_documents_org_sta'
    add_index :documents, [:organization_id, :embedding_status], name: 'idx_documents_org_emb'
    
    # Make sure pg_trgm is installed before creating text search indexes
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"
    
    # Now create text search indexes
    execute "CREATE INDEX documents_title_trgm_idx ON documents USING gin (title gin_trgm_ops) WHERE title IS NOT NULL"
    execute "CREATE INDEX documents_content_trgm_idx ON documents USING gin (content gin_trgm_ops) WHERE content IS NOT NULL"
    
    # Create vector index for similarity search
    execute "CREATE INDEX documents_embedding_idx ON documents USING hnsw (embedding vector_l2_ops);"
  end
end
