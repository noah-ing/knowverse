class CreateDocumentClusters < ActiveRecord::Migration[8.0]
  def change
    create_table :document_clusters do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :algorithm, null: false
      t.jsonb :parameters, default: {}
      t.jsonb :centroid, null: false
      t.integer :document_count, null: false, default: 0
      t.jsonb :metadata, default: {}
      t.integer :parent_cluster_id, null: true

      t.timestamps
    end
    
    # Self-referential foreign key for hierarchical clusters
    add_foreign_key :document_clusters, :document_clusters, column: :parent_cluster_id
    
    # Indexes for efficient querying
    add_index :document_clusters, [:organization_id, :algorithm], name: 'idx_document_clusters_org_alg'
    add_index :document_clusters, :parent_cluster_id

    # Create the join table for documents and clusters
    create_table :cluster_memberships do |t|
      t.references :document_cluster, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true
      t.float :membership_strength, null: false, default: 1.0

      t.timestamps
    end

    # Ensure no duplicate memberships
    add_index :cluster_memberships, [:document_cluster_id, :document_id],
              name: 'index_cluster_memberships_on_cluster_and_document', unique: true
  end
end
