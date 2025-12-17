# setup_database.rb
# Script to set up the database with pgvector extension and run migrations
# This script should be run once the PostgreSQL connection issues are resolved

require 'fileutils'

# Step 1: Backup the original migration files if they exist
def backup_migrations
  puts "=> Backing up existing migration files..."
  migrations_dir = 'db/migrate'
  backup_dir = 'db/migrate_backup'
  
  FileUtils.mkdir_p(backup_dir) unless Dir.exist?(backup_dir)
  
  Dir.glob("#{migrations_dir}/*").each do |file|
    next if File.directory?(file)
    backup_file = file.gsub(migrations_dir, backup_dir)
    FileUtils.cp(file, backup_file)
    puts "   Backed up #{file} to #{backup_file}"
  end
end

# Step 2: Create the pgvector extension migration
def create_pgvector_migration
  puts "=> Creating pgvector extension migration..."
  migration_content = <<~RUBY
    class EnablePgvectorExtension < ActiveRecord::Migration[8.0]
      def up
        execute "CREATE EXTENSION IF NOT EXISTS vector"
        puts "Successfully enabled pgvector extension."
      end

      def down
        execute "DROP EXTENSION IF EXISTS vector"
      end
    end
  RUBY
  
  File.write('db/migrate/20250402175959_enable_pgvector_extension.rb', migration_content)
  puts "   Created db/migrate/20250402175959_enable_pgvector_extension.rb"
end

# Step 3: Create the pg_trgm extension migration
def create_pg_trgm_migration
  puts "=> Creating pg_trgm extension migration..."
  migration_content = <<~RUBY
    class EnablePgTrgmExtension < ActiveRecord::Migration[8.0]
      def up
        execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"
      end

      def down
        execute "DROP EXTENSION IF EXISTS pg_trgm"
      end
    end
  RUBY
  
  File.write('db/migrate/20250402180239_enable_pg_trgm_extension.rb', migration_content)
  puts "   Created db/migrate/20250402180239_enable_pg_trgm_extension.rb"
end

# Step 4: Create the document model migration
def create_documents_migration
  puts "=> Creating documents migration..."
  migration_content = <<~RUBY
    class CreateDocuments < ActiveRecord::Migration[8.0]
      def change
        create_table :documents do |t|
          t.string :title, null: false
          t.text :description
          t.string :file_type
          t.string :status, default: 'pending', null: false
          t.text :content
          t.string :embedding_status, default: 'pending', null: false
          t.references :organization, null: false, foreign_key: true
          t.integer :word_count, default: 0
          t.jsonb :metadata, default: {}
          # Vector field for embeddings
          t.vector :embedding, dimension: 768

          t.timestamps
        end
        
        # Add indexes for better query performance
        add_index :documents, :status
        add_index :documents, :embedding_status
        add_index :documents, :file_type
        add_index :documents, [:organization_id, :status]
        add_index :documents, [:organization_id, :embedding_status]
        add_index :documents, :title, using: :gin, opclass: :gin_trgm_ops, where: "title IS NOT NULL"
        add_index :documents, :content, using: :gin, opclass: :gin_trgm_ops, where: "content IS NOT NULL"
        
        # Create vector index for similarity search
        execute "CREATE INDEX ON documents USING hnsw (embedding vector_l2_ops);"
      end
    end
  RUBY
  
  File.write('db/migrate/20250402180207_create_documents.rb', migration_content)
  puts "   Created db/migrate/20250402180207_create_documents.rb"
end

# Step 5: Run migrations and set up the database
def run_migrations
  puts "=> Running migrations..."
  puts "   This step may fail if the PostgreSQL connection issues are not resolved."
  puts "   If it fails, you'll need to resolve the connection issues and run 'rails db:migrate' manually."
  
  system('rails db:create db:migrate')
end

# Step 6: Test the document processing pipeline
def test_pipeline
  puts "=> Testing document processing pipeline..."
  puts "   This step can only be executed if the migrations have been successfully run."
  puts "   You can test the pipeline manually by uploading a document through the UI or using the Rails console."
  puts "   Example using Rails console:"
  puts "   ```"
  puts "   org = Organization.first || Organization.create!(name: 'Test Organization')"
  puts "   doc = org.documents.create!(title: 'Test Document', content: 'This is a test document for vector embeddings.')"
  puts "   DocumentProcessing::TextExtractionWorker.new.perform(doc.id)"
  puts "   DocumentProcessing::EmbeddingGenerationWorker.new.perform(doc.id)"
  puts "   ```"
end

# Main execution
begin
  puts "KnowVerse Database Setup Script"
  puts "==============================="
  
  backup_migrations
  create_pgvector_migration
  create_pg_trgm_migration
  create_documents_migration
  
  puts "\nReady to run migrations? This will attempt to connect to the database. (y/n)"
  response = gets.chomp.downcase
  
  if response == 'y'
    run_migrations
    
    puts "\nWould you like to see instructions for testing the document processing pipeline? (y/n)"
    pipeline_response = gets.chomp.downcase
    
    test_pipeline if pipeline_response == 'y'
  else
    puts "Migrations not run. You can run them manually later with 'rails db:migrate'."
  end
  
  puts "\nSetup completed! Make sure to verify that pgvector extension is installed on your PostgreSQL instance."
  puts "You can check by connecting to the database and running: SELECT * FROM pg_extension WHERE extname = 'vector';"
  
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace
end
