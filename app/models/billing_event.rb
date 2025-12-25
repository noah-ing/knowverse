class BillingEvent < ApplicationRecord
  # Status constants
  STATUSES = %w[pending processed failed].freeze

  # Associations
  belongs_to :organization

  # Validations
  validates :stripe_event_id, presence: true, uniqueness: true
  validates :event_type, presence: true
  validates :status, inclusion: { in: STATUSES }

  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :processed, -> { where(status: 'processed') }
  scope :failed, -> { where(status: 'failed') }
  scope :recent, -> { order(created_at: :desc) }

  # Status management
  def mark_processed!
    update!(status: 'processed', processed_at: Time.current, error_message: nil)
  end

  def mark_failed!(error)
    update!(status: 'failed', error_message: error.to_s)
  end

  def pending?
    status == 'pending'
  end

  def processed?
    status == 'processed'
  end

  def failed?
    status == 'failed'
  end

  # Idempotency check
  def self.already_processed?(stripe_event_id)
    exists?(stripe_event_id: stripe_event_id, status: 'processed')
  end

  # Create from Stripe event
  def self.record_event(organization, stripe_event)
    create!(
      organization: organization,
      stripe_event_id: stripe_event.id,
      event_type: stripe_event.type,
      data: stripe_event.data.to_h,
      status: 'pending'
    )
  rescue ActiveRecord::RecordNotUnique
    find_by(stripe_event_id: stripe_event.id)
  end
end
