class CreateOrganizationUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :organization_users do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: 'viewer'
      t.string :invitation_token
      t.datetime :invitation_accepted_at

      t.timestamps
    end
    
    # Add unique constraint to ensure a user can only have one role per organization
    add_index :organization_users, [:organization_id, :user_id], {name: 'idx_organization_users_org_use'}, unique: true
  end
end
