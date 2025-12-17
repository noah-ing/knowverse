class VectorEmbedding < ApplicationRecord
  belongs_to :document
  belongs_to :domain_embedding_model, optional: true
  has_many :vector_projections, dependent: :destroy
  
  # Define status constants
  STATUS_PENDING = 'pending'
  STATUS_PROCESSING = 'processing'
  STATUS_PROCESSED = 'processed'
  STATUS_ERROR = 'error'
  
  # Dimension validation
  validates :dimension, inclusion: { in: [384, 768, 1024, 1536, 2048] }
  
  # Domain constants
  DEFAULT_DOMAIN = 'general'
  
  # Embedding model names
  SUPPORTED_MODELS = {
    'mini' => 384,
    'small' => 768,
    'base' => 1024,
    'large' => 1536,
    'xl' => 2048
  }
  
  # Map dimensions to models
  DIMENSIONS_TO_MODELS = SUPPORTED_MODELS.invert
  
  validates :embedding_model, inclusion: { in: SUPPORTED_MODELS.keys }
  validates :status, inclusion: { in: [STATUS_PENDING, STATUS_PROCESSING, STATUS_PROCESSED, STATUS_ERROR] }
  
  # Ensure dimension matches model
  validate :dimension_matches_model
  
  # Scopes for easy filtering
  scope :processed, -> { where(status: STATUS_PROCESSED) }
  scope :pending, -> { where(status: STATUS_PENDING) }
  scope :processing, -> { where(status: STATUS_PROCESSING) }
  scope :errored, -> { where(status: STATUS_ERROR) }
  scope :indexed_in_hnsw, -> { where(indexed_in_hnsw: true) }
  scope :not_indexed_in_hnsw, -> { where(indexed_in_hnsw: false) }
  
  # Domain-specific scopes
  scope :by_domain, ->(domain) { where(domain: domain) }
  scope :general_domain, -> { where(domain: DEFAULT_DOMAIN) }
  scope :domain_specific, -> { where.not(domain: DEFAULT_DOMAIN) }
  
  # Helper methods
  def processed?
    status == STATUS_PROCESSED
  end
  
  def pending?
    status == STATUS_PENDING
  end
  
  def processing?
    status == STATUS_PROCESSING
  end
  
  def errored?
    status == STATUS_ERROR
  end
  
  def general_domain?
    domain == DEFAULT_DOMAIN
  end
  
  def domain_specific?
    !general_domain?
  end
  
  def mark_as_processing!
    update!(status: STATUS_PROCESSING)
  end
  
  def mark_as_processed!
    update!(status: STATUS_PROCESSED)
  end
  
  def mark_as_error!(error_message)
    update!(status: STATUS_ERROR, error_message: error_message)
  end
  
  def mark_as_indexed_in_hnsw!(index_reference)
    update!(
      indexed_in_hnsw: true,
      hnsw_index_reference: index_reference,
      indexed_at: Time.current
    )
  end
  
  def self.available_domains(organization_id)
    joins(:document)
      .where(documents: { organization_id: organization_id })
      .distinct
      .pluck(:domain)
  end
  
  def model_with_domain
    if general_domain?
      embedding_model
    else
      "#{domain}/#{embedding_model}"
    end
  end
  
  private
  
  def dimension_matches_model
    expected_dimension = SUPPORTED_MODELS[embedding_model]
    if dimension != expected_dimension
      errors.add(:dimension, "must be #{expected_dimension} for model #{embedding_model}")
    end
  end
end
