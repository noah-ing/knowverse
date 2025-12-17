class CreateVectorEmbeddings < ActiveRecord::Migration[8.0]
  def change
    create_table :vector_embeddings do |t|
      t.references :document, null: false, foreign_key: true
      t.integer :dimension, null: false
      t.string :model_name, null: false
      t.vector :embedding, null: false
      t.boolean :indexed_in_hnsw, default: false
      t.string :hnsw_index_reference
      t.datetime :indexed_at
      t.string :status, default: 'pending'
      t.text :error_message

      t.timestamps
    end
    
    add_index :vector_embeddings, [:document_id, :dimension], name: 'idx_vector_embeddings_doc_dim', unique: true
    add_index :vector_embeddings, [:document_id, :model_name], name: 'idx_vector_embeddings_doc_mod', unique: true
    
    # Add primary embedding type to documents
    add_column :documents, :primary_embedding_type, :string, default: 'base'
  end
end
