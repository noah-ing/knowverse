# Migration Helper for KnowVerse
# This module provides helper methods for making migrations idempotent

module MigrationHelper
  # Safely create a table only if it doesn't exist
  def safe_create_table(table_name, **options, &block)
    return if table_exists?(table_name)
    create_table(table_name, **options, &block)
  end
  
  # Safely add an index only if it doesn't exist
  def safe_add_index(table_name, column_names, **options)
    # Skip if the table doesn't exist
    return unless table_exists?(table_name)
    
    # Generate index name
    index_name = options[:name]
    index_name ||= if column_names.is_a?(Array)
                     "index_#{table_name}_on_#{column_names.join('_and_')}"
                   else
                     "index_#{table_name}_on_#{column_names}"
                   end
    
    # Skip if index already exists
    return if index_exists?(table_name, column_names, name: index_name)
    
    add_index(table_name, column_names, **options)
  end
  
  # Safely add a column only if it doesn't exist
  def safe_add_column(table_name, column_name, type, **options)
    # Skip if the table doesn't exist
    return unless table_exists?(table_name)
    
    # Skip if column already exists
    return if column_exists?(table_name, column_name)
    
    add_column(table_name, column_name, type, **options)
  end
  
  # Safely enable an extension only if it's not already enabled
  def safe_enable_extension(extension_name)
    return if extension_enabled?(extension_name)
    enable_extension(extension_name)
  end
end

# Add these methods to ActiveRecord migrations
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Migration.send(:include, MigrationHelper)
end
