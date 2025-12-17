class VectorProjection < ApplicationRecord
  belongs_to :vector_embedding
  belongs_to :organization
  
  has_one :document, through: :vector_embedding
  
  validates :algorithm, presence: true
  validates :coordinates, presence: true
  validates :dimensions, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :lod_level, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  
  # Scopes for common queries
  scope :tsne, -> { where(algorithm: 'tsne') }
  scope :umap, -> { where(algorithm: 'umap') }
  scope :by_dimension, ->(dimensions) { where(dimensions: dimensions) }
  scope :by_lod, ->(level) { where(lod_level: level) }
  scope :low_resolution, -> { where(lod_level: [0, 1]) }
  scope :high_resolution, -> { where(lod_level: 0) }
  
  # JSON serialization options
  def as_json(options = {})
    super(options.merge(
      except: [:created_at, :updated_at],
      include: {
        vector_embedding: { only: [:id, :dimensions, :model] }
      }
    ))
  end
  
  # Get projection as array for frontend visualization
  def projection_array
    if coordinates.is_a?(Array)
      coordinates
    else
      # Handle JSON string or Hash representation
      coordinates.is_a?(String) ? JSON.parse(coordinates) : coordinates.values
    end
  end
end
