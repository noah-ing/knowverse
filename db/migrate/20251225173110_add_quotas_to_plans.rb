class AddQuotasToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :max_documents, :integer, default: 50
    add_column :plans, :max_queries_per_month, :integer, default: 1000
    add_column :plans, :max_team_members, :integer, default: 5
    add_column :plans, :advanced_search, :boolean, default: false
    add_column :plans, :api_access, :boolean, default: false
    add_column :plans, :trial_days, :integer, default: 0
    add_column :plans, :description, :text
    add_column :plans, :display_order, :integer, default: 0
  end
end
