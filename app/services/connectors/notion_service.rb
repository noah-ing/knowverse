require 'notion'

module Connectors
  class NotionService
    OAUTH_AUTHORIZE_URL = 'https://api.notion.com/v1/oauth/authorize'.freeze
    OAUTH_TOKEN_URL = 'https://api.notion.com/v1/oauth/token'.freeze

    attr_reader :document_source

    def initialize(document_source)
      @document_source = document_source
    end

    def self.client_id
      ENV.fetch('NOTION_CLIENT_ID', nil)
    end

    def self.client_secret
      ENV.fetch('NOTION_CLIENT_SECRET', nil)
    end

    def self.redirect_uri(organization_id)
      base = ENV.fetch('NOTION_REDIRECT_URI_BASE', 'http://localhost:3000')
      "#{base}/organizations/#{organization_id}/connectors/notion/callback"
    end

    def self.configured?
      client_id.present? && client_secret.present?
    end

    def self.authorize_url(organization_id, state: nil)
      params = {
        client_id: client_id,
        redirect_uri: redirect_uri(organization_id),
        response_type: 'code',
        owner: 'user'
      }
      params[:state] = state if state.present?

      "#{OAUTH_AUTHORIZE_URL}?#{params.to_query}"
    end

    def self.exchange_code(code, organization_id)
      credentials = Base64.strict_encode64("#{client_id}:#{client_secret}")

      response = Faraday.post(OAUTH_TOKEN_URL) do |req|
        req.headers['Authorization'] = "Basic #{credentials}"
        req.headers['Content-Type'] = 'application/json'
        req.body = {
          grant_type: 'authorization_code',
          code: code,
          redirect_uri: redirect_uri(organization_id)
        }.to_json
      end

      result = JSON.parse(response.body)

      if result['error'].present?
        raise "Notion OAuth error: #{result['error']}"
      end

      {
        'access_token' => result['access_token'],
        'bot_id' => result['bot_id'],
        'workspace_id' => result['workspace_id'],
        'workspace_name' => result['workspace_name'],
        'workspace_icon' => result['workspace_icon']
      }
    end

    def client
      @client ||= Notion::Client.new(token: document_source.access_token)
    end

    def search_pages(query: '', page_size: 100)
      results = []

      client.search(
        query: query,
        filter: { value: 'page', property: 'object' },
        page_size: page_size
      ) do |page|
        results.concat(page.results)
      end

      results.map { |page| page_to_hash(page) }
    end

    def list_all_pages(max_pages: 500)
      all_pages = []

      client.search(
        query: '',
        filter: { value: 'page', property: 'object' },
        page_size: 100
      ) do |response|
        response.results.each do |page|
          break if all_pages.size >= max_pages
          all_pages << page_to_hash(page)
        end
        break if all_pages.size >= max_pages
      end

      all_pages.take(max_pages)
    end

    def get_page(page_id)
      page = client.page(page_id: page_id)
      page_to_hash(page)
    end

    def get_page_content(page_id)
      blocks = fetch_blocks_recursive(page_id)
      blocks_to_text(blocks)
    end

    def get_page_blocks(page_id)
      fetch_blocks_recursive(page_id)
    end

    private

    def fetch_blocks_recursive(block_id)
      blocks = []

      client.block_children(block_id: block_id) do |response|
        response.results.each do |block|
          block_data = block_to_hash(block)
          blocks << block_data

          if block.has_children
            block_data[:children] = fetch_blocks_recursive(block.id)
          end
        end
      end

      blocks
    rescue Notion::Api::Errors::NotFoundError
      []
    end

    def page_to_hash(page)
      title = extract_page_title(page)

      {
        id: page.id,
        title: title,
        url: page.url,
        created_time: page.created_time,
        last_edited_time: page.last_edited_time,
        parent_type: page.parent&.type,
        archived: page.archived,
        icon: extract_icon(page.icon),
        cover: extract_cover(page.cover)
      }
    end

    def extract_page_title(page)
      # Title can be in different places depending on page type
      if page.properties
        title_prop = page.properties.to_h.values.find do |prop|
          prop.is_a?(Hash) && prop['type'] == 'title'
        end

        if title_prop && title_prop['title'].is_a?(Array)
          return title_prop['title'].map { |t| t['plain_text'] }.join('')
        end
      end

      # Fallback: try to get from parent if it's a database
      'Untitled'
    end

    def extract_icon(icon)
      return nil unless icon

      case icon.type
      when 'emoji'
        { type: 'emoji', value: icon.emoji }
      when 'external'
        { type: 'external', value: icon.external&.url }
      when 'file'
        { type: 'file', value: icon.file&.url }
      end
    end

    def extract_cover(cover)
      return nil unless cover

      case cover.type
      when 'external'
        cover.external&.url
      when 'file'
        cover.file&.url
      end
    end

    def block_to_hash(block)
      {
        id: block.id,
        type: block.type,
        has_children: block.has_children,
        content: extract_block_content(block)
      }
    end

    def extract_block_content(block)
      case block.type
      when 'paragraph'
        extract_rich_text(block.paragraph&.rich_text)
      when 'heading_1'
        extract_rich_text(block.heading_1&.rich_text)
      when 'heading_2'
        extract_rich_text(block.heading_2&.rich_text)
      when 'heading_3'
        extract_rich_text(block.heading_3&.rich_text)
      when 'bulleted_list_item'
        extract_rich_text(block.bulleted_list_item&.rich_text)
      when 'numbered_list_item'
        extract_rich_text(block.numbered_list_item&.rich_text)
      when 'to_do'
        text = extract_rich_text(block.to_do&.rich_text)
        checked = block.to_do&.checked ? '[x]' : '[ ]'
        "#{checked} #{text}"
      when 'toggle'
        extract_rich_text(block.toggle&.rich_text)
      when 'quote'
        extract_rich_text(block.quote&.rich_text)
      when 'callout'
        extract_rich_text(block.callout&.rich_text)
      when 'code'
        code = extract_rich_text(block.code&.rich_text)
        lang = block.code&.language || ''
        "```#{lang}\n#{code}\n```"
      when 'divider'
        '---'
      when 'child_page'
        "[Page: #{block.child_page&.title}]"
      when 'child_database'
        "[Database: #{block.child_database&.title}]"
      when 'image'
        url = block.image&.external&.url || block.image&.file&.url
        "[Image: #{url}]"
      when 'video'
        url = block.video&.external&.url || block.video&.file&.url
        "[Video: #{url}]"
      when 'file'
        url = block.file&.external&.url || block.file&.file&.url
        "[File: #{url}]"
      when 'pdf'
        url = block.pdf&.external&.url || block.pdf&.file&.url
        "[PDF: #{url}]"
      when 'bookmark'
        "[Bookmark: #{block.bookmark&.url}]"
      when 'link_preview'
        "[Link: #{block.link_preview&.url}]"
      when 'table'
        '[Table]'
      when 'table_row'
        cells = block.table_row&.cells&.map { |cell| extract_rich_text(cell) }
        cells&.join(' | ')
      else
        ''
      end
    end

    def extract_rich_text(rich_text_array)
      return '' unless rich_text_array.is_a?(Array)

      rich_text_array.map do |text|
        text.respond_to?(:plain_text) ? text.plain_text : text['plain_text']
      end.join('')
    end

    def blocks_to_text(blocks, depth: 0)
      return '' unless blocks.is_a?(Array)

      indent = '  ' * depth

      blocks.map do |block|
        content = block[:content].to_s
        children_text = ''

        if block[:children].present?
          children_text = blocks_to_text(block[:children], depth: depth + 1)
        end

        case block[:type]
        when 'heading_1'
          "# #{content}"
        when 'heading_2'
          "## #{content}"
        when 'heading_3'
          "### #{content}"
        when 'bulleted_list_item'
          "#{indent}- #{content}#{children_text}"
        when 'numbered_list_item'
          "#{indent}1. #{content}#{children_text}"
        when 'quote'
          "> #{content}"
        else
          content.present? ? "#{indent}#{content}#{children_text}" : children_text
        end
      end.reject(&:blank?).join("\n\n")
    end
  end
end
