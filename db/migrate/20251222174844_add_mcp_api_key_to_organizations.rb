class AddMcpApiKeyToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :mcp_api_key, :string
    add_index :organizations, :mcp_api_key
  end
end
