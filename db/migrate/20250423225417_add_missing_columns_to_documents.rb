class AddMissingColumnsToDocuments < ActiveRecord::Migration[8.0]
  def up
    # Add the new columns
    add_column :documents, :embedding_status, :string, default: 'pending'
    add_column :documents, :word_count, :integer, default: 0
    add_column :documents, :primary_embedding_type, :string, null: true
    
    # Update status values while status is still an integer
    execute <<-SQL
      UPDATE documents SET 
        embedding_status = 'pending' WHERE embedding_status IS NULL;
    SQL
    
    # Create a temporary column to hold the string status
    add_column :documents, :status_str, :string, default: 'pending'
    
    # Map integer status to string status
    execute <<-SQL
      UPDATE documents SET 
        status_str = CASE 
          WHEN status = 0 THEN 'pending'
          WHEN status = 1 THEN 'processing'
          WHEN status = 2 THEN 'processed'
          WHEN status = 3 THEN 'error'
          ELSE 'pending'
        END;
    SQL
    
    # Remove the original status column
    remove_column :documents, :status
    
    # Add the new status column with the right type
    add_column :documents, :status, :string, default: 'pending', null: false
    
    # Copy values from temporary column
    execute <<-SQL
      UPDATE documents SET status = status_str;
    SQL
    
    # Remove the temporary column
    remove_column :documents, :status_str
  end
  
  def down
    # Remove new columns
    remove_column :documents, :embedding_status
    remove_column :documents, :word_count
    remove_column :documents, :primary_embedding_type
    
    # Remove string status and recreate integer status
    remove_column :documents, :status
    add_column :documents, :status, :integer, default: 0
  end
end
