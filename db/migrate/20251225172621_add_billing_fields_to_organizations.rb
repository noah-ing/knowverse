class AddBillingFieldsToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :stripe_customer_id, :string
    add_column :organizations, :stripe_subscription_id, :string
    add_column :organizations, :subscription_status, :string, default: 'none'
    add_column :organizations, :plan_id, :bigint
    add_column :organizations, :trial_ends_at, :datetime
    add_column :organizations, :current_period_end, :datetime
    add_column :organizations, :canceled_at, :datetime

    add_index :organizations, :stripe_customer_id, unique: true
    add_index :organizations, :stripe_subscription_id
    add_index :organizations, :plan_id
    add_foreign_key :organizations, :plans
  end
end
