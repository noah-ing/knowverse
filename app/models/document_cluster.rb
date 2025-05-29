class DocumentCluster < ApplicationRecord
  belongs_to :organization
  belongs_to :parent, class_name: 'DocumentCluster', foreign_key: 'parent_cluster_id', optional: true
  has_many :children, class_name: 'DocumentCluster', foreign_key: 'parent_cluster_id', dependent: :nullify
  
  has_many :cluster_memberships, dependent: :destroy
  has_many :documents, through: :cluster_memberships
  
  validates :algorithm, presence: true
  validates :centroid, presence: true
  validates :document_count, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  
  # Scopes for common queries
  scope :roots, -> { where(parent_cluster_id: nil) }
  scope :by_algorithm, ->(algorithm) { where(algorithm: algorithm) }
  scope :kmeans, -> { where(algorithm: 'kmeans') }
  scope :hierarchical, -> { where(algorithm: 'hierarchical') }
  scope :dbscan, -> { where(algorithm: 'dbscan') }
  scope :with_documents_min, ->(min_count) { where('document_count >= ?', min_count) }
  
  # Find clusters that contain specific documents
  scope :containing_documents, ->(document_ids) {
    joins(:cluster_memberships)
      .where(cluster_memberships: { document_id: document_ids })
      .group('document_clusters.id')
      .having('COUNT(DISTINCT cluster_memberships.document_id) = ?', document_ids.size)
  }
  
  # Find similar clusters based on centroid proximity
  def similar_clusters(limit = 5, threshold = 0.8)
    # Implement using vector similarity on centroids
    DocumentCluster
      .where(organization_id: organization_id)
      .where.not(id: id)
      .order("centroid <=> '#{centroid.to_json}'::jsonb")
      .limit(limit)
  end
  
  # Get documents sorted by proximity to centroid
  def sorted_documents(limit = 20)
    documents
      .joins(:vector_embeddings)
      .order("vector_embeddings.embedding <=> '#{centroid.to_json}'::jsonb")
      .limit(limit)
  end
  
  # Get representative documents that best characterize this cluster
  def representative_documents(count = 3)
    documents
      .joins(:cluster_memberships)
      .where(cluster_memberships: { document_cluster_id: id })
      .order(membership_strength: :desc)
      .limit(count)
  end
  
  # Custom JSON serialization
  def as_json(options = {})
    super(options.merge(
      except: [:created_at, :updated_at],
      include: {
        children: { only: [:id, :document_count] },
        representative_documents: { only: [:id, :title] }
      },
      methods: [:depth, :breadcrumbs]
    ))
  end
  
  # Get cluster depth in hierarchy
  def depth
    return 0 if parent_cluster_id.nil?
    
    current = self
    depth = 0
    
    while current.parent_cluster_id.present?
      depth += 1
      current = current.parent
    end
    
    depth
  end
  
  # Get cluster ancestry path
  def breadcrumbs
    return [] if parent_cluster_id.nil?
    
    path = []
    current = self
    
    while current.parent_cluster_id.present?
      current = current.parent
      path.unshift({ id: current.id, document_count: current.document_count })
    end
    
    path
  end
end
