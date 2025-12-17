class CreateVectorProjections < ActiveRecord::Migration[8.0]
  def change
    create_table :vector_projections do |t|
      t.references :vector_embedding, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :algorithm, null: false
      t.jsonb :parameters, default: {}
      t.jsonb :coordinates, null: false
      t.integer :dimensions, null: false, default: 3
      t.integer :lod_level, null: false, default: 0

      t.timestamps
    end
    
    # Indexes for efficient querying by organization, algorithm, and LOD level
    add_index :vector_projections, [:organization_id, :algorithm, :lod_level], name: 'idx_vector_projections_org_alg_lod'
    add_index :vector_projections, [:vector_embedding_id, :algorithm], name: 'idx_vector_projections_vec_alg'
  end
end
