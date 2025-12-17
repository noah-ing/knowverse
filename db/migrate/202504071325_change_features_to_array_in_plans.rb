class ChangeFeaturesToArrayInPlans < ActiveRecord::Migration[8.0]
  def up
    # First, remove the old column
    remove_column :plans, :features
    
    # Then, add the new array column
    add_column :plans, :features, :string, array: true, default: []
  end
  
  def down
    # Remove the array column
    remove_column :plans, :features
    
    # Add back the original text column
    add_column :plans, :features, :text
  end
end
