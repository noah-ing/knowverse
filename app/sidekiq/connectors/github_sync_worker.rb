module Connectors
  class GithubSyncWorker < ApplicationJob
    queue_as :connectors
    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform(document_source_id)
      document_source = DocumentSource.find(document_source_id)
      return unless document_source.connected?

      Rails.logger.info("GitHub sync started for DocumentSource #{document_source_id}")
      document_source.mark_syncing!

      service = Connectors::GithubService.new(document_source)
      synced_count = 0
      skipped_count = 0
      error_count = 0

      # Sync repositories and their markdown files
      repos = service.list_repositories(per_page: 50)
      Rails.logger.info("GitHub: Found #{repos.size} repositories to sync")

      repos.each do |repo|
        begin
          result = sync_repository(document_source, service, repo)
          case result
          when :synced then synced_count += 1
          when :skipped then skipped_count += 1
          when :error then error_count += 1
          end
        rescue => e
          Rails.logger.error("GitHub: Error syncing repo #{repo[:full_name]}: #{e.message}")
          error_count += 1
        end

        # Rate limiting - GitHub allows 5000 requests/hour for authenticated users
        sleep 0.2
      end

      document_source.mark_synced!
      Rails.logger.info("GitHub sync completed: #{synced_count} synced, #{skipped_count} skipped, #{error_count} errors")
    rescue => e
      Rails.logger.error("GitHub sync failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
      document_source.mark_error!(e.message)
      raise
    end

    private

    def sync_repository(document_source, service, repo)
      owner = repo[:owner]
      repo_name = repo[:name]
      repo_updated_at = Time.parse(repo[:updated_at]) rescue Time.current

      # Check if we already synced this repo recently
      existing_repo_doc = document_source.documents.find_by(external_id: "github:#{repo[:id]}:readme")
      if existing_repo_doc && existing_repo_doc.updated_at >= repo_updated_at
        return :skipped
      end

      synced_any = false

      # Sync README
      readme_content = service.get_readme(owner, repo_name)
      if readme_content.present?
        sync_file(
          document_source,
          external_id: "github:#{repo[:id]}:readme",
          title: "#{repo[:full_name]} - README",
          content: readme_content,
          url: "#{repo[:html_url]}/blob/#{repo[:default_branch]}/README.md",
          file_type: 'markdown',
          metadata: { repo: repo[:full_name], type: 'readme' }
        )
        synced_any = true
      end

      # Sync other markdown files (limit to avoid overwhelming)
      markdown_files = service.list_markdown_files(owner, repo_name, max_depth: 2)
      markdown_files.take(20).each do |file|
        next if file[:name].downcase.start_with?('readme') # Already synced

        begin
          content = service.get_file_content(owner, repo_name, file[:path])
          sync_file(
            document_source,
            external_id: "github:#{repo[:id]}:#{file[:sha]}",
            title: "#{repo[:full_name]}/#{file[:path]}",
            content: content,
            url: file[:html_url],
            file_type: 'markdown',
            metadata: { repo: repo[:full_name], type: 'file', path: file[:path] }
          )
          synced_any = true
          sleep 0.1 # Rate limiting
        rescue => e
          Rails.logger.warn("GitHub: Error syncing file #{file[:path]}: #{e.message}")
        end
      end

      synced_any ? :synced : :skipped
    end

    def sync_file(document_source, external_id:, title:, content:, url:, file_type:, metadata: {})
      existing = document_source.documents.find_by(external_id: external_id)

      doc = existing || document_source.documents.new(organization: document_source.organization)
      doc.assign_attributes(
        title: title.truncate(255),
        external_id: external_id,
        external_url: url,
        file_type: file_type,
        status: 'pending',
        embedding_status: 'pending',
        metadata: metadata
      )

      # Determine filename extension
      ext = case file_type
            when 'markdown' then '.md'
            else '.txt'
            end

      safe_filename = title.gsub(/[^a-zA-Z0-9\-_]/, '_').truncate(100) + ext
      doc.file.attach(
        io: StringIO.new(content),
        filename: safe_filename,
        content_type: 'text/markdown'
      )

      if doc.save
        DocumentProcessing::TextExtractionWorker.perform_later(doc.id)
        Rails.logger.info("GitHub: Synced #{title}")
      else
        Rails.logger.error("GitHub: Failed to save #{title}: #{doc.errors.full_messages.join(', ')}")
      end
    end
  end
end
