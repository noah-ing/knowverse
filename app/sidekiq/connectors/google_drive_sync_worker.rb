module Connectors
  class GoogleDriveSyncWorker < ActiveJob::Base
    queue_as :connectors
    retry_on StandardError, wait: ->(attempt) { (attempt ** 4) + 2 }, attempts: 3

    def perform(document_source_id)
      document_source = DocumentSource.find(document_source_id)

      unless document_source.connected?
        Rails.logger.warn("GoogleDriveSyncWorker: Source #{document_source_id} is not connected")
        return
      end

      Rails.logger.info("GoogleDriveSyncWorker: Starting sync for source #{document_source_id}")
      document_source.mark_syncing!

      begin
        service = ::Connectors::GoogleDriveService.new(document_source)
        organization = document_source.organization

        # Get folder ID from settings if configured
        folder_id = document_source.settings['folder_id']

        # List files from Google Drive
        files = service.list_all_files(folder_id: folder_id, max_files: 100)
        Rails.logger.info("GoogleDriveSyncWorker: Found #{files.size} files to sync")

        synced_count = 0
        skipped_count = 0
        error_count = 0

        files.each do |file|
          begin
            result = sync_file(document_source, organization, service, file)
            case result
            when :synced then synced_count += 1
            when :skipped then skipped_count += 1
            when :error then error_count += 1
            end
          rescue => e
            Rails.logger.error("GoogleDriveSyncWorker: Error syncing file #{file[:id]}: #{e.message}")
            error_count += 1
          end
        end

        document_source.mark_synced!
        Rails.logger.info("GoogleDriveSyncWorker: Sync complete. Synced: #{synced_count}, Skipped: #{skipped_count}, Errors: #{error_count}")

      rescue => e
        Rails.logger.error("GoogleDriveSyncWorker: Sync failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
        document_source.mark_error!(e.message)
        raise e
      end
    end

    private

    def sync_file(document_source, organization, service, file)
      # Check if document already exists with this external ID
      existing_doc = Document.find_by(
        document_source_id: document_source.id,
        external_id: file[:id]
      )

      # Skip if unchanged (compare modified times)
      if existing_doc.present?
        file_modified = file[:modified_time]
        if existing_doc.updated_at >= file_modified
          Rails.logger.debug("GoogleDriveSyncWorker: Skipping unchanged file #{file[:name]}")
          return :skipped
        end
      end

      Rails.logger.info("GoogleDriveSyncWorker: Syncing file #{file[:name]} (#{file[:file_type]})")

      # Download file content
      download_result = service.download_file(file[:id], file[:mime_type])
      content = download_result[:content]

      # Determine the actual file type (may be different after export)
      file_type = file[:file_type]
      filename = file[:name]

      # Adjust filename extension if exported
      if download_result[:exported_mime_type]
        case download_result[:exported_mime_type]
        when 'application/pdf'
          filename = filename.sub(/\.\w+$/, '') + '.pdf' unless filename.end_with?('.pdf')
          file_type = 'pdf'
        when 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          filename = filename.sub(/\.\w+$/, '') + '.xlsx' unless filename.end_with?('.xlsx')
          file_type = 'xlsx'
        end
      end

      # Create or update document
      document = existing_doc || Document.new(
        organization: organization,
        document_source: document_source
      )

      document.assign_attributes(
        title: file[:name].sub(/\.\w+$/, '').gsub(/[_-]/, ' '),
        file_type: file_type,
        external_id: file[:id],
        external_url: file[:web_view_link],
        status: 'pending',
        embedding_status: 'pending'
      )

      # Attach file content
      document.file.attach(
        io: StringIO.new(content),
        filename: filename,
        content_type: determine_content_type(file_type)
      )

      if document.save
        # Queue text extraction
        DocumentProcessing::TextExtractionWorker.perform_later(document.id)
        Rails.logger.info("GoogleDriveSyncWorker: Created/updated document #{document.id} for #{file[:name]}")
        :synced
      else
        Rails.logger.error("GoogleDriveSyncWorker: Failed to save document: #{document.errors.full_messages.join(', ')}")
        :error
      end
    end

    def determine_content_type(file_type)
      case file_type
      when 'pdf' then 'application/pdf'
      when 'docx' then 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      when 'xlsx' then 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      when 'txt' then 'text/plain'
      when 'md' then 'text/markdown'
      else 'application/octet-stream'
      end
    end
  end
end
