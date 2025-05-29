class AddVectorEmbeddingIdToVectorProjections < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:vector_projections, :vector_embedding_id)
      add_column :vector_projections, :vector_embedding_id, :bigint
      add_index :vector_projections, :vector_embedding_id
      add_foreign_key :vector_projections, :vector_embeddings, on_delete: :cascade
    end
  end
end
