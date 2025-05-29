class AddDescriptionToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :description, :text
  end
end
