namespace :migrations do
  desc "Mark all pending migrations as complete without running them"
  task :mark_complete => :environment do
    puts "Finding all migration files..."
    marked_count = 0
    
    # Get the connection to use for direct SQL
    conn = ActiveRecord::Base.connection
    
    # Create schema_migrations table if it doesn't exist
    unless conn.table_exists?('schema_migrations')
      puts "Creating schema_migrations table..."
      conn.create_table :schema_migrations do |t|
        t.string :version, null: false
        t.index :version, unique: true
      end
    end
    
    # Get existing migrations
    existing = conn.select_values("SELECT version FROM schema_migrations")
    puts "Found #{existing.size} existing migrations"
    
    # Mark all migrations as complete
    Dir.glob(Rails.root.join('db/migrate/*.rb')).each do |file|
      timestamp = File.basename(file).split('_').first
      
      if existing.include?(timestamp)
        puts "Migration #{timestamp} already marked as complete"
      else
        conn.execute("INSERT INTO schema_migrations (version) VALUES ('#{timestamp}')")
        marked_count += 1
        puts "Marked migration #{timestamp} as complete"
      end
    end
    
    puts "All migrations have been marked as complete!"
    puts "#{marked_count} new migrations were marked as complete."
    puts "You should now be able to run the application without migration errors."
  end
end
