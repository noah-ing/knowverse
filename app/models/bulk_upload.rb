# frozen_string_literal: true

# BulkUpload tracks the progress of large-scale document uploads
# for enterprise customers.
#
# Status flow:
#   pending -> processing -> completed/failed/partial
#
# Metadata structure:
#   {
#     source: 'api' | 'connector' | 'upload_form',
#     batch_size: 100,
#     errors: [{ document_id: 1, error: 'message' }],
#     processing_stats: {
#       avg_extraction_time_ms: 500,
#       avg_embedding_time_ms: 2000,
#       total_chunks: 5000
#     }
#   }
class BulkUpload < ApplicationRecord
  belongs_to :organization
  belongs_to :user
  has_many :documents, dependent: :nullify

  # Status enum
  STATUSES = %w[pending processing completed failed partial cancelled].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :total_files, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :processed_files, numericality: { greater_than_or_equal_to: 0 }
  validates :failed_files, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :active, -> { where(status: %w[pending processing]) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_organization, ->(org) { where(organization: org) }

  # Callbacks
  before_validation :set_defaults, on: :create

  # State machine methods
  def start!
    update!(status: 'processing', started_at: Time.current)
  end

  def complete!
    new_status = failed_files.positive? && processed_files.positive? ? 'partial' : 'completed'
    update!(status: new_status, completed_at: Time.current)
  end

  def fail!(error_message = nil)
    errors_list = metadata['errors'] || []
    errors_list << { error: error_message, time: Time.current.iso8601 } if error_message
    update!(
      status: 'failed',
      completed_at: Time.current,
      metadata: metadata.merge('errors' => errors_list)
    )
  end

  def cancel!
    update!(status: 'cancelled', completed_at: Time.current)
  end

  # Progress tracking
  def increment_processed!
    increment!(:processed_files)
    check_completion
  end

  def increment_failed!(document_id: nil, error: nil)
    increment!(:failed_files)
    if document_id && error
      errors_list = metadata['errors'] || []
      errors_list << { document_id: document_id, error: error, time: Time.current.iso8601 }
      update!(metadata: metadata.merge('errors' => errors_list))
    end
    check_completion
  end

  def progress_percentage
    return 0 if total_files.nil? || total_files.zero?
    ((processed_files + failed_files).to_f / total_files * 100).round(1)
  end

  def estimated_time_remaining
    return nil unless processing? && processed_files.positive?

    elapsed = Time.current - started_at
    rate = processed_files / elapsed.to_f
    remaining = total_files - processed_files - failed_files
    return nil if rate.zero?

    (remaining / rate).round
  end

  def throughput_per_minute
    return 0 unless processing? && started_at
    elapsed_minutes = (Time.current - started_at) / 60.0
    return 0 if elapsed_minutes < 0.1
    (processed_files / elapsed_minutes).round(1)
  end

  # Status checks
  def pending?
    status == 'pending'
  end

  def processing?
    status == 'processing'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def partial?
    status == 'partial'
  end

  def finished?
    %w[completed failed partial cancelled].include?(status)
  end

  # Summary for API responses
  def summary
    {
      id: id,
      status: status,
      total_files: total_files,
      processed_files: processed_files,
      failed_files: failed_files,
      progress_percentage: progress_percentage,
      throughput_per_minute: throughput_per_minute,
      estimated_time_remaining: estimated_time_remaining,
      started_at: started_at&.iso8601,
      completed_at: completed_at&.iso8601,
      created_at: created_at.iso8601
    }
  end

  private

  def set_defaults
    self.status ||= 'pending'
    self.processed_files ||= 0
    self.failed_files ||= 0
    self.metadata ||= {}
  end

  def check_completion
    return unless total_files && (processed_files + failed_files) >= total_files
    complete!
  end
end
