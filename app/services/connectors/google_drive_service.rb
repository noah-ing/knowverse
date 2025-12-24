require 'google/apis/drive_v3'
require 'googleauth'

module Connectors
  class GoogleDriveService
    SCOPES = [
      'https://www.googleapis.com/auth/drive.readonly',
      'https://www.googleapis.com/auth/drive.metadata.readonly'
    ].freeze

    SUPPORTED_MIME_TYPES = {
      'application/pdf' => 'pdf',
      'application/vnd.google-apps.document' => 'gdoc',
      'application/vnd.google-apps.spreadsheet' => 'gsheet',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => 'docx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => 'xlsx',
      'text/plain' => 'txt',
      'text/markdown' => 'md'
    }.freeze

    EXPORT_FORMATS = {
      'application/vnd.google-apps.document' => 'application/pdf',
      'application/vnd.google-apps.spreadsheet' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    }.freeze

    attr_reader :document_source

    def initialize(document_source)
      @document_source = document_source
    end

    def self.client_id
      ENV.fetch('GOOGLE_CLIENT_ID', nil)
    end

    def self.client_secret
      ENV.fetch('GOOGLE_CLIENT_SECRET', nil)
    end

    def self.redirect_uri(organization_id)
      base = ENV.fetch('GOOGLE_REDIRECT_URI_BASE', 'http://localhost:3000')
      "#{base}/organizations/#{organization_id}/connectors/google_drive/callback"
    end

    def self.configured?
      client_id.present? && client_secret.present?
    end

    def self.authorize_url(organization_id, state: nil)
      client = Signet::OAuth2::Client.new(
        client_id: client_id,
        client_secret: client_secret,
        authorization_uri: 'https://accounts.google.com/o/oauth2/auth',
        redirect_uri: redirect_uri(organization_id),
        scope: SCOPES
      )

      client.authorization_uri(
        access_type: 'offline',
        prompt: 'consent',
        state: state
      ).to_s
    end

    def self.exchange_code(code, organization_id)
      client = Signet::OAuth2::Client.new(
        client_id: client_id,
        client_secret: client_secret,
        token_credential_uri: 'https://oauth2.googleapis.com/token',
        redirect_uri: redirect_uri(organization_id),
        code: code,
        grant_type: 'authorization_code'
      )

      client.fetch_access_token!

      {
        'access_token' => client.access_token,
        'refresh_token' => client.refresh_token,
        'expires_at' => client.expires_at.to_i
      }
    end

    def refresh_token!
      return false unless document_source.refresh_token.present?

      client = Signet::OAuth2::Client.new(
        client_id: self.class.client_id,
        client_secret: self.class.client_secret,
        token_credential_uri: 'https://oauth2.googleapis.com/token',
        refresh_token: document_source.refresh_token
      )

      client.fetch_access_token!

      credentials = document_source.credentials_hash.merge(
        'access_token' => client.access_token,
        'expires_at' => client.expires_at.to_i
      )
      document_source.credentials_hash = credentials
      document_source.save!

      true
    rescue Signet::AuthorizationError => e
      Rails.logger.error("Google Drive token refresh failed: #{e.message}")
      document_source.mark_error!("Authentication failed: #{e.message}")
      false
    end

    def drive_service
      ensure_valid_token!

      @drive_service ||= begin
        service = Google::Apis::DriveV3::DriveService.new
        service.authorization = access_token_client
        service
      end
    end

    def list_files(folder_id: nil, page_token: nil, page_size: 100)
      query_parts = ["trashed = false"]
      query_parts << "mimeType != 'application/vnd.google-apps.folder'"

      if folder_id.present?
        query_parts << "'#{folder_id}' in parents"
      end

      # Filter to supported file types
      mime_type_query = SUPPORTED_MIME_TYPES.keys.map { |t| "mimeType = '#{t}'" }.join(' or ')
      query_parts << "(#{mime_type_query})"

      response = drive_service.list_files(
        q: query_parts.join(' and '),
        page_size: page_size,
        page_token: page_token,
        fields: 'nextPageToken, files(id, name, mimeType, modifiedTime, webViewLink, size, parents)'
      )

      {
        files: response.files.map { |f| file_to_hash(f) },
        next_page_token: response.next_page_token
      }
    end

    def list_all_files(folder_id: nil, max_files: 500)
      all_files = []
      page_token = nil

      loop do
        result = list_files(folder_id: folder_id, page_token: page_token)
        all_files.concat(result[:files])

        break if result[:next_page_token].nil? || all_files.size >= max_files

        page_token = result[:next_page_token]
      end

      all_files.take(max_files)
    end

    def download_file(file_id, mime_type)
      # Google native formats need to be exported
      if EXPORT_FORMATS.key?(mime_type)
        export_format = EXPORT_FORMATS[mime_type]
        content = StringIO.new
        drive_service.export_file(file_id, export_format, download_dest: content)
        content.rewind
        {
          content: content.read,
          exported_mime_type: export_format
        }
      else
        content = StringIO.new
        drive_service.get_file(file_id, download_dest: content)
        content.rewind
        {
          content: content.read,
          exported_mime_type: nil
        }
      end
    end

    def get_file_metadata(file_id)
      file = drive_service.get_file(
        file_id,
        fields: 'id, name, mimeType, modifiedTime, webViewLink, size, parents'
      )
      file_to_hash(file)
    end

    private

    def ensure_valid_token!
      if document_source.token_expired?
        unless refresh_token!
          raise "Unable to refresh Google Drive access token"
        end
        @drive_service = nil # Force recreation with new token
      end
    end

    def access_token_client
      Google::Auth::UserRefreshCredentials.new(
        client_id: self.class.client_id,
        client_secret: self.class.client_secret,
        access_token: document_source.access_token,
        refresh_token: document_source.refresh_token,
        expires_at: document_source.token_expires_at
      )
    end

    def file_to_hash(file)
      {
        id: file.id,
        name: file.name,
        mime_type: file.mime_type,
        modified_time: file.modified_time,
        web_view_link: file.web_view_link,
        size: file.size,
        parents: file.parents,
        file_type: determine_file_type(file.mime_type)
      }
    end

    def determine_file_type(mime_type)
      case mime_type
      when 'application/pdf' then 'pdf'
      when 'application/vnd.google-apps.document' then 'pdf' # Will be exported as PDF
      when 'application/vnd.google-apps.spreadsheet' then 'xlsx' # Will be exported as XLSX
      when 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' then 'docx'
      when 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' then 'xlsx'
      when 'text/plain' then 'txt'
      when 'text/markdown' then 'md'
      else 'unknown'
      end
    end
  end
end
