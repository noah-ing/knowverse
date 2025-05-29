class CreatePlans < ActiveRecord::Migration[8.0]
  def change
    create_table :plans do |t|
      t.string :name
      t.string :stripe_price_id
      t.integer :amount
      t.string :interval
      t.text :features
      t.boolean :active

      t.timestamps
    end
  end
end
