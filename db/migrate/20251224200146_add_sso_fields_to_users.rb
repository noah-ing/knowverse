class AddSsoFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :provider, :string
    add_column :users, :uid, :string
    add_column :users, :sso_organization_id, :bigint

    add_index :users, [:provider, :uid], unique: true, where: "provider IS NOT NULL"
    add_foreign_key :users, :organizations, column: :sso_organization_id
  end
end
