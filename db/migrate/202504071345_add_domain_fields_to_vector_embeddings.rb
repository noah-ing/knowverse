class AddDomainFieldsToVectorEmbeddings < ActiveRecord::Migration[8.0]
  def change
    add_column :vector_embeddings, :domain, :string, default: 'general'
    add_reference :vector_embeddings, :domain_embedding_model, null: true, foreign_key: true
    
    add_index :vector_embeddings, :domain
    add_index :vector_embeddings, [:domain, :model_name], {name: 'idx_vector_embeddings_dom_mod'}
  end
end
