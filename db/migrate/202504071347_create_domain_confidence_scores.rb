class CreateDomainConfidenceScores < ActiveRecord::Migration[8.0]
  def change
    create_table :domain_confidence_scores do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :query_text, null: false
      t.string :domain, null: false
      t.float :total_score, null: false
      t.jsonb :factor_scores
      t.boolean :was_successful
      t.float :semantic_similarity
      t.float :corpus_coverage
      t.float :query_characteristics
      t.float :historical_performance
      
      t.timestamps
    end
    
    add_index :domain_confidence_scores, [:organization_id, :query_text, :domain], {name: 'idx_domain_confidence_scores_org_que_dom'}
  end
end
