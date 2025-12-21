class AddMissingColumnsToVectorProjections < ActiveRecord::Migration[8.0]
  def change
    add_column :vector_projections, :organization_id, :bigint
    add_column :vector_projections, :coordinates, :jsonb
    add_column :vector_projections, :dimensions, :integer, default: 3
    add_column :vector_projections, :lod_level, :integer, default: 0
    add_column :vector_projections, :parameters, :jsonb, default: {}

    add_index :vector_projections, :organization_id
    add_index :vector_projections, [:algorithm, :lod_level]
  end
end
