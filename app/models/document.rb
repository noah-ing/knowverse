class Document < ApplicationRecord
  belongs_to :organization
  has_many :vector_embeddings, dependent: :destroy
  has_many :vector_projections, through: :vector_embeddings
  has_many :cluster_memberships, dependent: :destroy
  has_many :document_clusters, through: :cluster_memberships
  has_many :search_feedbacks, dependent: :destroy
  
  # ActiveStorage
  has_one_attached :file
  
  # Constants
  VALID_FILE_TYPES = %w[pdf docx doc txt rtf md].freeze
  STATUSES = %w[pending processing processed error].freeze
  EMBEDDING_STATUSES = %w[pending processing processed error].freeze
  
  # Validations
  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :embedding_status, inclusion: { in: EMBEDDING_STATUSES }
  validates :file_type, inclusion: { in: VALID_FILE_TYPES }, allow_nil: true
  
  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :with_positive_feedback, -> { joins(:search_feedbacks).where('search_feedbacks.relevance_score >= ?', 4).distinct }
  scope :with_negative_feedback, -> { joins(:search_feedbacks).where('search_feedbacks.relevance_score <= ?', 2).distinct }
  scope :most_feedback, -> { joins(:search_feedbacks).group('documents.id').order('COUNT(search_feedbacks.id) DESC') }
  scope :processing, -> { where(status: 'processing') }
  scope :processed, -> { where(status: 'processed') }
  scope :errored, -> { where(status: 'error') }
  scope :embedding_pending, -> { where(embedding_status: 'pending') }
  scope :embedding_processing, -> { where(embedding_status: 'processing') }
  scope :embedding_processed, -> { where(embedding_status: 'processed') }
  scope :embedding_errored, -> { where(embedding_status: 'error') }
  scope :search_ready, -> { processed.embedding_processed }
  
  # Callbacks
  before_create :set_initial_statuses
  before_save :update_word_count, if: -> { content_changed? }
  
  # Instance methods
  
  # Status methods
  def pending?
    status == 'pending'
  end
  
  def processing?
    status == 'processing'
  end
  
  def processed?
    status == 'processed'
  end
  
  def errored?
    status == 'error'
  end
  
  def embedding_pending?
    embedding_status == 'pending'
  end
  
  def embedding_processing?
    embedding_status == 'processing'
  end
  
  def embedding_processed?
    embedding_status == 'processed'
  end
  
  def embedding_errored?
    embedding_status == 'error'
  end
  
  def search_ready?
    processed? && embedding_processed?
  end
  
  # File handling
  def file_extension
    return nil unless file.attached?
    file.filename.extension.downcase
  end
  
  def determine_file_type
    ext = file_extension
    return nil unless ext
    
    case ext
    when 'pdf' then 'pdf'
    when 'docx', 'doc' then 'docx'
    when 'txt', 'md', 'rtf' then ext
    else 'unknown'
    end
  end
  
  # Processing methods
  def mark_as_processing!
    update(status: 'processing')
  end
  
  def mark_as_processed!
    update(status: 'processed')
  end
  
  def mark_as_error!(error_message = nil)
    metadata_hash = metadata || {}
    metadata_hash[:error_message] = error_message if error_message
    update(status: 'error', metadata: metadata_hash)
  end
  
  def mark_embedding_as_processing!
    update(embedding_status: 'processing')
  end
  
  def mark_embedding_as_processed!
    update(embedding_status: 'processed')
  end
  
  def mark_embedding_as_error!(error_message = nil)
    metadata_hash = metadata || {}
    metadata_hash[:embedding_error] = error_message if error_message
    update(embedding_status: 'error', metadata: metadata_hash)
  end
  
  # Vector embedding helper methods
  def get_embedding(dimension: nil, model_name: nil)
    if dimension
      vector_embeddings.processed.find_by(dimension: dimension)
    elsif model_name
      vector_embeddings.processed.find_by(model_name: model_name)
    else
      # Default to primary embedding type or fall back to any available
      vector_embeddings.processed.find_by(model_name: primary_embedding_type) || 
        vector_embeddings.processed.first
    end
  end
  
  def get_embedding_vector(dimension: nil, model_name: nil)
    embedding = get_embedding(dimension: dimension, model_name: model_name)
    embedding&.embedding
  end
  
  def set_primary_embedding_type(model_name)
    update(primary_embedding_type: model_name) if VectorEmbedding::SUPPORTED_MODELS.key?(model_name)
  end
  
  def available_embedding_dimensions
    vector_embeddings.processed.pluck(:dimension)
  end
  
  def available_embedding_models
    vector_embeddings.processed.pluck(:model_name)
  end
  
  def has_embedding_dimension?(dimension)
    vector_embeddings.processed.exists?(dimension: dimension)
  end
  
  def has_embedding_model?(model_name)
    vector_embeddings.processed.exists?(model_name: model_name)
  end
  
  # Legacy compatibility methods
  def embedding
    # For backward compatibility, return the embedding from the first available vector embedding
    embedding_record = get_embedding
    embedding_record&.embedding
  end
  
  # Error handling methods
  def error_message
    metadata&.dig(:error_message)
  end
  
  def embedding_error
    metadata&.dig(:embedding_error)
  end
  
  # Feedback methods
  def feedback_score
    search_feedbacks.average(:relevance_score).to_f.round(2)
  end
  
  def feedback_count
    search_feedbacks.count
  end
  
  def feedback_distribution
    {
      positive: search_feedbacks.where('relevance_score >= ?', 4).count,
      neutral: search_feedbacks.where(relevance_score: 3).count,
      negative: search_feedbacks.where('relevance_score <= ?', 2).count
    }
  end
  
  def has_feedback?
    search_feedbacks.exists?
  end
  
  # Search methods
  def self.nearest_neighbors(embedding_vector, dimension: nil, model_name: nil, limit: 10, min_similarity: 0.5)
    if dimension || model_name
      # New dimension-aware approach with JOIN to vector_embeddings
      query = joins(:vector_embeddings).where(vector_embeddings: { status: VectorEmbedding::STATUS_PROCESSED })
      
      if dimension
        query = query.where(vector_embeddings: { dimension: dimension })
      elsif model_name
        query = query.where(vector_embeddings: { model_name: model_name })
      end
      
      query.select('documents.*, vector_embeddings.embedding <-> ? as distance', sanitize_vector(embedding_vector))
           .order('distance')
           .limit(limit)
    else
      # Legacy approach using document.embedding field
      where.not(embedding: nil)
           .order(Arel.sql("embedding <-> '#{sanitize_vector(embedding_vector)}'"))
           .limit(limit)
    end
  end
  
  def self.similar_to(embedding_vector, dimension: nil, model_name: nil, min_similarity: 0.5, limit: 10)
    if dimension || model_name
      # New dimension-aware approach with JOIN to vector_embeddings
      query = joins(:vector_embeddings).where(vector_embeddings: { status: VectorEmbedding::STATUS_PROCESSED })
      
      if dimension
        query = query.where(vector_embeddings: { dimension: dimension })
      elsif model_name
        query = query.where(vector_embeddings: { model_name: model_name })
      end
      
      similarity_expr = "vector_embeddings.embedding <=> ?"
      query.select("documents.*, #{similarity_expr} as similarity", sanitize_vector(embedding_vector))
           .where("#{similarity_expr} > ?", sanitize_vector(embedding_vector), min_similarity)
           .order('similarity DESC')
           .limit(limit)
    else
      # Legacy approach using document.embedding field
      where.not(embedding: nil)
           .where("embedding <=> '#{sanitize_vector(embedding_vector)}' > ?", min_similarity)
           .order(Arel.sql("embedding <=> '#{sanitize_vector(embedding_vector)}' DESC"))
           .limit(limit)
    end
  end
  
  private
  
  def set_initial_statuses
    self.status ||= 'pending'
    self.embedding_status ||= 'pending'
    self.metadata ||= {}
  end
  
  def update_word_count
    return unless content.present?
    self.word_count = content.split(/\s+/).size
  end
  
  def self.sanitize_vector(vector)
    vector.is_a?(Array) ? vector.to_s.gsub('[', '[').gsub(']', ']') : vector.to_s
  end
end
