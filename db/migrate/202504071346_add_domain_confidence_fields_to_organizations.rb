class AddDomainConfidenceFieldsToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :domain_confidence_primary_threshold, :float, default: 0.7
    add_column :organizations, :domain_confidence_secondary_threshold, :float, default: 0.4
    add_column :organizations, :enable_domain_fallback, :boolean, default: true
  end
end
