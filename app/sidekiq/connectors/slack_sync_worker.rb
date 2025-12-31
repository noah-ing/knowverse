module Connectors
  class SlackSyncWorker < ApplicationJob
    queue_as :connectors
    retry_on StandardError, wait: ->(attempt) { (attempt ** 4) + 2 }, attempts: 3

    def perform(document_source_id)
      document_source = DocumentSource.find(document_source_id)
      return unless document_source.connected?

      Rails.logger.info("Slack sync started for DocumentSource #{document_source_id}")
      document_source.mark_syncing!

      service = Connectors::SlackService.new(document_source)
      synced_count = 0
      skipped_count = 0
      error_count = 0

      # Get all public channels
      channels = service.list_channels.reject { |ch| ch[:is_archived] }
      Rails.logger.info("Slack: Found #{channels.size} active channels to sync")

      channels.each do |channel|
        begin
          result = sync_channel(document_source, service, channel)
          case result
          when :synced then synced_count += 1
          when :skipped then skipped_count += 1
          when :error then error_count += 1
          end
        rescue => e
          Rails.logger.error("Slack: Error syncing channel #{channel[:name]}: #{e.message}")
          error_count += 1
        end

        # Rate limiting - Slack allows ~1 req/sec for tier 3 methods
        sleep 1
      end

      document_source.mark_synced!
      Rails.logger.info("Slack sync completed: #{synced_count} synced, #{skipped_count} skipped, #{error_count} errors")
    rescue => e
      Rails.logger.error("Slack sync failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
      document_source.mark_error!(e.message)
      raise
    end

    private

    def sync_channel(document_source, service, channel)
      channel_id = channel[:id]
      channel_name = channel[:name]

      # Check if we recently synced this channel
      existing_doc = document_source.documents.find_by(external_id: "slack:channel:#{channel_id}")
      if existing_doc && existing_doc.updated_at > 1.hour.ago
        return :skipped
      end

      # Fetch channel history (last 30 days, max 500 messages)
      messages = service.get_channel_history(channel_id, limit: 500)

      if messages.empty?
        Rails.logger.debug("Slack: Channel ##{channel_name} has no messages, skipping")
        return :skipped
      end

      # Convert messages to markdown document
      content = format_channel_as_markdown(service, channel, messages)

      sync_document(
        document_source,
        external_id: "slack:channel:#{channel_id}",
        title: "##{channel_name} - Slack Channel",
        content: content,
        url: "https://slack.com/app_redirect?channel=#{channel_id}",
        metadata: {
          channel_id: channel_id,
          channel_name: channel_name,
          message_count: messages.size,
          topic: channel[:topic],
          purpose: channel[:purpose]
        }
      )

      :synced
    end

    def format_channel_as_markdown(service, channel, messages)
      lines = []

      # Header
      lines << "# ##{channel[:name]}"
      lines << ""
      lines << "> #{channel[:purpose]}" if channel[:purpose].present?
      lines << ""
      lines << "---"
      lines << ""

      # Group messages by date
      messages_by_date = messages.group_by do |msg|
        Time.at(msg[:ts].to_f).to_date
      end

      messages_by_date.sort.reverse.each do |date, day_messages|
        lines << "## #{date.strftime('%B %d, %Y')}"
        lines << ""

        day_messages.sort_by { |m| m[:ts] }.each do |msg|
          next if msg[:subtype] == 'channel_join' # Skip join messages

          user = service.get_user_info(msg[:user])
          username = user[:display_name].presence || user[:real_name] || user[:name] || 'Unknown'
          timestamp = Time.at(msg[:ts].to_f).strftime('%H:%M')

          # Format message
          text = msg[:text] || ''
          text = replace_user_mentions(text, service)
          text = replace_channel_mentions(text)
          text = text.gsub(/\n/, "\n> ")

          lines << "**#{username}** (#{timestamp}):"
          lines << "> #{text}"

          # Add reactions
          if msg[:reactions].any?
            reactions_text = msg[:reactions].map { |r| ":#{r[:name]}: #{r[:count]}" }.join(' ')
            lines << "> _#{reactions_text}_"
          end

          # Note thread replies
          if msg[:reply_count].to_i > 0
            lines << "> _#{msg[:reply_count]} replies in thread_"
          end

          lines << ""
        end
      end

      lines.join("\n")
    end

    def replace_user_mentions(text, service)
      text.gsub(/<@([A-Z0-9]+)>/) do |_match|
        user_id = $1
        user = service.get_user_info(user_id)
        "@#{user[:display_name] || user[:name] || user_id}"
      end
    end

    def replace_channel_mentions(text)
      text.gsub(/<#([A-Z0-9]+)\|([^>]+)>/) do |_match|
        "##{$2}"
      end
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
        Rails.logger.info("Slack: Synced #{title}")
      else
        Rails.logger.error("Slack: Failed to save #{title}: #{doc.errors.full_messages.join(', ')}")
      end
    end
  end
end
