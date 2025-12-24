class DocumentSource < ApplicationRecord
  belongs_to :organization
  has_many :documents, dependent: :nullify

  encrypts :credentials

  enum :source_type, {
    google_drive: 0,
    notion: 1,
    slack: 2,
    confluence: 3,
    github: 4
  }

  SYNC_STATUSES = %w[disconnected connected syncing error].freeze

  validates :source_type, presence: true
  validates :sync_status, inclusion: { in: SYNC_STATUSES }

  scope :connected, -> { where(sync_status: 'connected') }
  scope :needs_sync, -> { connected.where('last_sync_at IS NULL OR last_sync_at < ?', 1.hour.ago) }

  def connected?
    sync_status == 'connected' && credentials.present?
  end

  def syncing?
    sync_status == 'syncing'
  end

  def credentials_hash
    return {} if credentials.blank?
    JSON.parse(credentials)
  rescue JSON::ParserError
    {}
  end

  def credentials_hash=(hash)
    self.credentials = hash.to_json
  end

  def access_token
    credentials_hash['access_token']
  end

  def refresh_token
    credentials_hash['refresh_token']
  end

  def token_expires_at
    return nil unless credentials_hash['expires_at']
    Time.at(credentials_hash['expires_at'])
  end

  def token_expired?
    return true unless token_expires_at
    token_expires_at < Time.current
  end

  def needs_reauth?
    !connected? || (token_expired? && refresh_token.blank?)
  end

  def mark_syncing!
    update!(sync_status: 'syncing', sync_error: nil)
  end

  def mark_synced!
    update!(sync_status: 'connected', last_sync_at: Time.current, sync_error: nil)
  end

  def mark_error!(error_message)
    update!(sync_status: 'error', sync_error: error_message)
  end

  def mark_disconnected!
    update!(sync_status: 'disconnected', credentials: nil, sync_error: nil)
  end

  def display_name
    name.presence || "#{source_type.titleize} Connection"
  end

  def last_sync_ago
    return 'Never synced' unless last_sync_at
    "#{time_ago_in_words(last_sync_at)} ago"
  end

  private

  def time_ago_in_words(time)
    seconds = (Time.current - time).to_i
    case seconds
    when 0..59 then "#{seconds} seconds"
    when 60..3599 then "#{seconds / 60} minutes"
    when 3600..86399 then "#{seconds / 3600} hours"
    else "#{seconds / 86400} days"
    end
  end
end
