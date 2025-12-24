module Connectors
  class NotionSyncWorker < ActiveJob::Base
    queue_as :document_processing
    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform(document_source_id)
      document_source = DocumentSource.find(document_source_id)

      unless document_source.connected?
        Rails.logger.warn("NotionSyncWorker: Source #{document_source_id} is not connected")
        return
      end

      Rails.logger.info("NotionSyncWorker: Starting sync for source #{document_source_id}")
      document_source.mark_syncing!

      begin
        service = ::Connectors::NotionService.new(document_source)
        organization = document_source.organization

        # List all accessible pages
        pages = service.list_all_pages(max_pages: 100)
        Rails.logger.info("NotionSyncWorker: Found #{pages.size} pages to sync")

        synced_count = 0
        skipped_count = 0
        error_count = 0

        pages.each do |page|
          begin
            result = sync_page(document_source, organization, service, page)
            case result
            when :synced then synced_count += 1
            when :skipped then skipped_count += 1
            when :error then error_count += 1
            end

            # Rate limiting: Notion allows 3 req/sec average
            sleep 0.5
          rescue => e
            Rails.logger.error("NotionSyncWorker: Error syncing page #{page[:id]}: #{e.message}")
            error_count += 1
          end
        end

        document_source.mark_synced!
        Rails.logger.info("NotionSyncWorker: Sync complete. Synced: #{synced_count}, Skipped: #{skipped_count}, Errors: #{error_count}")

      rescue => e
        Rails.logger.error("NotionSyncWorker: Sync failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
        document_source.mark_error!(e.message)
        raise e
      end
    end

    private

    def sync_page(document_source, organization, service, page)
      # Check if document already exists with this external ID
      existing_doc = Document.find_by(
        document_source_id: document_source.id,
        external_id: page[:id]
      )

      # Skip if unchanged (compare modified times)
      if existing_doc.present?
        page_modified = Time.parse(page[:last_edited_time]) rescue Time.current
        if existing_doc.updated_at >= page_modified
          Rails.logger.debug("NotionSyncWorker: Skipping unchanged page #{page[:title]}")
          return :skipped
        end
      end

      # Skip archived pages
      if page[:archived]
        Rails.logger.debug("NotionSyncWorker: Skipping archived page #{page[:title]}")
        return :skipped
      end

      Rails.logger.info("NotionSyncWorker: Syncing page #{page[:title]}")

      # Fetch page content (blocks)
      content = service.get_page_content(page[:id])

      # Create or update document
      document = existing_doc || Document.new(
        organization: organization,
        document_source: document_source
      )

      document.assign_attributes(
        title: page[:title].presence || 'Untitled',
        file_type: 'notion',
        external_id: page[:id],
        external_url: page[:url],
        status: 'pending',
        embedding_status: 'pending'
      )

      # Store content as a text file attachment
      if content.present?
        filename = "#{sanitize_filename(page[:title])}.md"
        document.file.attach(
          io: StringIO.new(content),
          filename: filename,
          content_type: 'text/markdown'
        )
      end

      if document.save
        # Queue text extraction (content already extracted, but this handles embedding)
        DocumentProcessing::TextExtractionWorker.perform_later(document.id)
        Rails.logger.info("NotionSyncWorker: Created/updated document #{document.id} for #{page[:title]}")
        :synced
      else
        Rails.logger.error("NotionSyncWorker: Failed to save document: #{document.errors.full_messages.join(', ')}")
        :error
      end
    end

    def sanitize_filename(name)
      return 'untitled' if name.blank?

      # Remove or replace invalid filename characters
      name.gsub(/[\/\\:*?"<>|]/, '_')
          .gsub(/\s+/, '_')
          .truncate(100, omission: '')
    end
  end
end
