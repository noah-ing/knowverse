class CreateBillingEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :billing_events do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :stripe_event_id, null: false
      t.string :event_type, null: false
      t.jsonb :data, default: {}
      t.datetime :processed_at
      t.string :status, default: 'pending'
      t.text :error_message

      t.timestamps
    end
    add_index :billing_events, :stripe_event_id, unique: true
    add_index :billing_events, [:organization_id, :event_type]
    add_index :billing_events, :status
  end
end
