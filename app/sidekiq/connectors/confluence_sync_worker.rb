module Connectors
  class ConfluenceSyncWorker < ApplicationJob
    queue_as :connectors
    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform(document_source_id)
      document_source = DocumentSource.find(document_source_id)
      return unless document_source.connected?

      Rails.logger.info("Confluence sync started for DocumentSource #{document_source_id}")
      document_source.mark_syncing!

      service = Connectors::ConfluenceService.new(document_source)
      synced_count = 0
      skipped_count = 0
      error_count = 0

      # Get all spaces
      spaces = service.list_spaces
      Rails.logger.info("Confluence: Found #{spaces.size} spaces")

      spaces.each do |space|
        begin
          # Get pages from this space
          pages = service.list_pages(space_id: space[:id])
          Rails.logger.info("Confluence: Found #{pages.size} pages in space #{space[:name]}")

          pages.each do |page|
            begin
              result = sync_page(document_source, service, space, page)
              case result
              when :synced then synced_count += 1
              when :skipped then skipped_count += 1
              when :error then error_count += 1
              end
            rescue => e
              Rails.logger.error("Confluence: Error syncing page #{page[:title]}: #{e.message}")
              error_count += 1
            end

            # Rate limiting
            sleep 0.2
          end
        rescue => e
          Rails.logger.error("Confluence: Error syncing space #{space[:name]}: #{e.message}")
          error_count += 1
        end
      end

      document_source.mark_synced!
      Rails.logger.info("Confluence sync completed: #{synced_count} synced, #{skipped_count} skipped, #{error_count} errors")
    rescue => e
      Rails.logger.error("Confluence sync failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
      document_source.mark_error!(e.message)
      raise
    end

    private

    def sync_page(document_source, service, space, page)
      page_id = page[:id]

      # Check if we recently synced this page
      existing_doc = document_source.documents.find_by(external_id: "confluence:page:#{page_id}")
      if existing_doc
        page_updated = Time.parse(page[:created_at]) rescue Time.current
        if existing_doc.updated_at >= page_updated
          return :skipped
        end
      end

      # Fetch page content and convert to markdown
      content = service.get_page_content(page_id)

      if content.blank?
        Rails.logger.debug("Confluence: Page #{page[:title]} has no content, skipping")
        return :skipped
      end

      # Add header with page info
      full_content = build_page_content(page, space, content)

      sync_document(
        document_source,
        external_id: "confluence:page:#{page_id}",
        title: "#{page[:title]} - #{space[:name]}",
        content: full_content,
        url: page[:url],
        metadata: {
          page_id: page_id,
          space_id: space[:id],
          space_name: space[:name],
          version: page[:version]
        }
      )

      :synced
    end

    def build_page_content(page, space, content)
      lines = []
      lines << "# #{page[:title]}"
      lines << ""
      lines << "> Space: #{space[:name]}"
      lines << ""
      lines << "---"
      lines << ""
      lines << content
      lines.join("\n")
    end

    def sync_document(document_source, external_id:, title:, content:, url:, metadata: {})
      existing = document_source.documents.find_by(external_id: external_id)

      doc = existing || document_source.documents.new(organization: document_source.organization)
      doc.assign_attributes(
        title: title.truncate(255),
        external_id: external_id,
        external_url: url,
        file_type: 'markdown',
        status: 'pending',
        embedding_status: 'pending',
        metadata: metadata
      )

      safe_filename = title.gsub(/[^a-zA-Z0-9\-_]/, '_').truncate(100) + '.md'
      doc.file.attach(
        io: StringIO.new(content),
        filename: safe_filename,
        content_type: 'text/markdown'
      )

      if doc.save
        DocumentProcessing::TextExtractionWorker.perform_later(doc.id)
        Rails.logger.info("Confluence: Synced #{title}")
      else
        Rails.logger.error("Confluence: Failed to save #{title}: #{doc.errors.full_messages.join(', ')}")
      end
    end
  end
end
