class AddModelNameToVectorEmbeddings < ActiveRecord::Migration[8.0]
  def change
    # Check if model_name column exists before adding it
    unless column_exists?(:vector_embeddings, :model_name)
      add_column :vector_embeddings, :model_name, :string, default: 'base'
      add_index :vector_embeddings, :model_name
    end
  end
end
