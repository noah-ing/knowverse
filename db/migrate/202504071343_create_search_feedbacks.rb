class CreateSearchFeedbacks < ActiveRecord::Migration[8.0]
  def change
    create_table :search_feedbacks do |t|
      t.references :search_query, null: false, foreign_key: true, index: true
      t.references :document, null: false, foreign_key: true, index: true
      t.references :user, null: true, foreign_key: true, index: true
      t.references :organization, null: false, foreign_key: true, index: true
      t.integer :relevance_score, null: false, default: 3
      t.string :feedback_type, null: false
      t.text :comments
      t.jsonb :metadata

      t.timestamps
      
      t.index :feedback_type
      t.index :created_at
      t.index :relevance_score
      
      t.check_constraint "relevance_score >= 1 AND relevance_score <= 5", name: "check_relevance_score_range"
    end
  end
end
