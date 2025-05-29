class AddNotificationPreferencesToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :notification_preferences, :jsonb, default: {
      product_updates: true,
      marketing_emails: false, 
      billing_alerts: true,
      weekly_summary: false
    }
  end
end
