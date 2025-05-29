class AddStripeFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :stripe_customer_id, :string
    add_column :users, :stripe_subscription_id, :string
    add_column :users, :card_brand, :string
    add_column :users, :card_last4, :string
    add_column :users, :card_exp_month, :string
    add_column :users, :card_exp_year, :string
    add_column :users, :subscription_status, :string
    add_column :users, :trial_ends_at, :datetime
  end
end
