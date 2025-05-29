class AddLoginTokenToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :login_token, :string
    add_column :users, :login_token_valid_until, :datetime
  end
end
