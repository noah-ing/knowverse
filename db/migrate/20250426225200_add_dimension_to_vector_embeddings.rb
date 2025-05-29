 class AddDimensionToVectorEmbeddings < ActiveRecord::Migration[8.0]
  def change
    # Check if dimension column exists before adding it
    unless column_exists?(:vector_embeddings, :dimension)
      add_column :vector_embeddings, :dimension, :integer, default: 768
      add_index :vector_embeddings, :dimension
    end
  end
end
