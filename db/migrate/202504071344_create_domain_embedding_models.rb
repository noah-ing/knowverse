class CreateDomainEmbeddingModels < ActiveRecord::Migration[8.0]
  def change
    create_table :domain_embedding_models do |t|
      t.string :name, null: false
      t.references :organization, null: false, foreign_key: true
      t.string :base_model, null: false
      t.string :domain, null: false
      t.integer :dimension, null: false
      t.string :version
      t.text :description
      t.jsonb :configuration, default: {}
      t.jsonb :performance_metrics, default: {}
      t.boolean :active, default: true

      t.timestamps
    end
    
    add_index :domain_embedding_models, :domain
    add_index :domain_embedding_models, [:organization_id, :domain], name: 'idx_domain_models_on_org_and_domain'
    add_index :domain_embedding_models, [:organization_id, :name], {name: 'idx_domain_embedding_models_org_nam'}, unique: true, name: 'idx_domain_models_on_org_and_name'
  end
end
