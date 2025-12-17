class DomainEmbeddingModel < ApplicationRecord
  # Associations
  belongs_to :organization
  has_many :vector_embeddings, dependent: :nullify
  
  # Validations
  validates :name, presence: true, uniqueness: { scope: :organization_id }
  validates :base_model, presence: true
  validates :domain, presence: true
  validates :dimension, presence: true, 
    inclusion: { in: VectorEmbedding::SUPPORTED_MODELS.values }
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :by_domain, ->(domain) { where(domain: domain) }
  
  # Ensure dimension matches base model
  validate :dimension_matches_base_model
  
  # Helper methods
  def active?
    active
  end
  
  def full_name
    "#{domain}/#{name}"
  end
  
  def base_model_name
    VectorEmbedding::DIMENSIONS_TO_MODELS[dimension]
  end
  
  def performance_summary
    return "No performance data" if performance_metrics.blank?
    
    metrics = performance_metrics.symbolize_keys
    if metrics[:accuracy].present? && metrics[:latency].present?
      "Accuracy: #{metrics[:accuracy].round(2)}%, Avg Latency: #{metrics[:latency].round(2)}ms"
    else
      "Incomplete performance data"
    end
  end
  
  # Class methods
  def self.available_domains(organization_id)
    where(organization_id: organization_id).pluck(:domain).uniq
  end
  
  def self.for_domain(organization_id, domain)
    where(organization_id: organization_id, domain: domain, active: true)
  end
  
  private
  
  def dimension_matches_base_model
    # Ensure the dimension aligns with one of our base models
    unless VectorEmbedding::DIMENSIONS_TO_MODELS.key?(dimension)
      errors.add(:dimension, "must be one of the supported dimensions: #{VectorEmbedding::SUPPORTED_MODELS.values.join(', ')}")
    end
    
    # If base_model is specified as one of our model names, ensure dimension matches
    if VectorEmbedding::SUPPORTED_MODELS.key?(base_model)
      expected_dimension = VectorEmbedding::SUPPORTED_MODELS[base_model]
      if dimension != expected_dimension
        errors.add(:dimension, "must be #{expected_dimension} for base model #{base_model}")
      end
    end
  end
end
