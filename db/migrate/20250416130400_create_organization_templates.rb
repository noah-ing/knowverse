class CreateOrganizationTemplates < ActiveRecord::Migration[7.0]
  def change
    create_table :organization_templates do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.text :content, null: false
      t.jsonb :variables, default: {}
      t.jsonb :configuration, default: {}
      t.string :template_type, null: false, default: 'rag'
      t.boolean :is_default, default: false
      t.integer :usage_count, default: 0
      t.float :average_rating, default: 0.0
      t.timestamps
    end
    
    add_index :organization_templates, [:organization_id, :name], unique: true
    add_index :organization_templates, [:organization_id, :template_type, :is_default], name: 'idx_org_templates_on_org_type_default'
    
    create_table :template_usages do |t|
      t.references :organization_template, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :conversation_session_id  # Just store the ID without foreign key constraint
      t.integer :rating
      t.float :response_time # in seconds
      t.integer :token_count
      t.jsonb :metrics, default: {}
      t.timestamps
    end
    
    add_index :template_usages, [:organization_template_id, :created_at], name: 'idx_template_usages_on_org_template_and_date'
    
    # We'll add the reference to conversation_sessions in a separate migration
    # after ensuring the conversation_sessions table exists
  end
end
