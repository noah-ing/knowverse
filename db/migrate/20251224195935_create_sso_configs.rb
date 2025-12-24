class CreateSsoConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :sso_configs do |t|
      t.references :organization, null: false, foreign_key: true, index: { unique: true }
      t.string :provider_type, null: false  # 'saml' or 'oidc'
      t.boolean :enabled, default: false

      # SAML fields (encrypted via Active Record Encryption)
      t.text :idp_metadata_url
      t.text :idp_sso_target_url
      t.text :idp_cert
      t.string :idp_cert_fingerprint
      t.string :name_identifier_format, default: 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'

      # OIDC fields (encrypted via Active Record Encryption)
      t.text :issuer
      t.text :client_id
      t.text :client_secret
      t.text :discovery_url
      t.string :scope, default: 'openid email profile'

      # Common configuration
      t.string :domain_allowlist, array: true, default: []
      t.boolean :auto_provision, default: true
      t.string :default_role, default: 'viewer'

      # Metadata
      t.datetime :last_used_at
      t.integer :login_count, default: 0

      t.timestamps
    end

    add_index :sso_configs, :provider_type
    add_index :sso_configs, :enabled
  end
end
