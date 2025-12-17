class AddHnswFieldsToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :indexed_in_hnsw, :boolean, default: false
    add_column :documents, :hnsw_index_reference, :string
    add_column :documents, :vector_dimension, :integer, default: 768
    add_column :documents, :migration_priority, :integer, default: 0
    add_column :documents, :migration_error, :text
    
    add_index :documents, :indexed_in_hnsw
    add_index :documents, :migration_priority
  end
end
