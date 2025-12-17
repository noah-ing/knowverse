class AddMissingColumnsToVectorEmbeddings < ActiveRecord::Migration[8.0]
  def change
    # Check if status column exists before adding it
    unless column_exists?(:vector_embeddings, :status)
      add_column :vector_embeddings, :status, :string, default: 'pending'
      add_index :vector_embeddings, :status
    end

    # Check if error_message column exists before adding it
    unless column_exists?(:vector_embeddings, :error_message)
      add_column :vector_embeddings, :error_message, :text
    end
  end
end
