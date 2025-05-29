class ClusterMembership < ApplicationRecord
  belongs_to :document_cluster
  belongs_to :document
  
  validates :membership_strength, presence: true, 
                                  numericality: { greater_than: 0, less_than_or_equal_to: 1 }
  
  # Scopes for common queries
  scope :strong_membership, -> { where('membership_strength >= ?', 0.8) }
  scope :medium_membership, -> { where('membership_strength >= ? AND membership_strength < ?', 0.5, 0.8) }
  scope :weak_membership, -> { where('membership_strength < ?', 0.5) }
  
  # For a given document, get all clusters sorted by membership strength
  def self.clusters_for_document(document_id, min_strength = 0)
    joins(:document_cluster)
      .where(document_id: document_id)
      .where('membership_strength > ?', min_strength)
      .order(membership_strength: :desc)
      .includes(:document_cluster)
      .map(&:document_cluster)
  end
  
  # For a given cluster, get all documents sorted by membership strength
  def self.documents_for_cluster(cluster_id, min_strength = 0)
    joins(:document)
      .where(document_cluster_id: cluster_id)
      .where('membership_strength > ?', min_strength)
      .order(membership_strength: :desc)
      .includes(:document)
      .map(&:document)
  end
end
