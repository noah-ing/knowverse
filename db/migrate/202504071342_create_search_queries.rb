class CreateSearchQueries < ActiveRecord::Migration[8.0]
  def change
    create_table :search_queries do |t|
      t.string :query_text
      t.string :search_provider
      t.jsonb :parameters
      t.float :latency
      t.integer :result_count
      t.references :organization, null: false, foreign_key: true, index: true
      t.references :user, null: true, foreign_key: true, index: true

      t.timestamps
      
      t.index :query_text
      t.index :search_provider
      t.index :created_at
    end
  end
end
