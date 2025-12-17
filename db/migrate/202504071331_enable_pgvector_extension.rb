class EnablePgvectorExtension < ActiveRecord::Migration[8.0]
  def up
    execute "CREATE EXTENSION IF NOT EXISTS vector"
    puts "Successfully enabled pgvector extension."
  end

  def down
    execute "DROP EXTENSION IF EXISTS vector"
  end
end
