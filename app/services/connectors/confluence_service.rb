module Connectors
  class ConfluenceService
    OAUTH_AUTHORIZE_URL = 'https://auth.atlassian.com/authorize'.freeze
    OAUTH_TOKEN_URL = 'https://auth.atlassian.com/oauth/token'.freeze
    RESOURCES_URL = 'https://api.atlassian.com/oauth/token/accessible-resources'.freeze

    attr_reader :document_source

    def initialize(document_source)
      @document_source = document_source
    end

    def self.client_id
      ENV.fetch('CONFLUENCE_CLIENT_ID', nil)
    end

    def self.client_secret
      ENV.fetch('CONFLUENCE_CLIENT_SECRET', nil)
    end

    def self.redirect_uri(organization_id)
      base = ENV.fetch('CONFLUENCE_REDIRECT_URI_BASE', 'http://localhost:3000')
      "#{base}/organizations/#{organization_id}/connectors/confluence/callback"
    end

    def self.configured?
      client_id.present? && client_secret.present?
    end

    def self.authorize_url(organization_id, state: nil)
      params = {
        audience: 'api.atlassian.com',
        client_id: client_id,
        scope: 'read:confluence-content.all read:confluence-space.summary read:confluence-content.summary offline_access',
        redirect_uri: redirect_uri(organization_id),
        response_type: 'code',
        prompt: 'consent',
        state: state
      }.compact

      "#{OAUTH_AUTHORIZE_URL}?#{params.to_query}"
    end

    def self.exchange_code(code, organization_id)
      response = Faraday.post(OAUTH_TOKEN_URL) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = {
          grant_type: 'authorization_code',
          client_id: client_id,
          client_secret: client_secret,
          code: code,
          redirect_uri: redirect_uri(organization_id)
        }.to_json
      end

      result = JSON.parse(response.body)

      if result['error'].present?
        raise "Confluence OAuth error: #{result['error_description'] || result['error']}"
      end

      # Get accessible resources (Confluence sites)
      resources_response = Faraday.get(RESOURCES_URL) do |req|
        req.headers['Authorization'] = "Bearer #{result['access_token']}"
        req.headers['Accept'] = 'application/json'
      end

      resources = JSON.parse(resources_response.body)

      # Use the first Confluence site
      confluence_site = resources.find { |r| r['scopes']&.any? { |s| s.include?('confluence') } }

      unless confluence_site
        raise "No Confluence site found. Please ensure you have Confluence access."
      end

      {
        'access_token' => result['access_token'],
        'refresh_token' => result['refresh_token'],
        'expires_at' => Time.current.to_i + result['expires_in'].to_i,
        'cloud_id' => confluence_site['id'],
        'site_name' => confluence_site['name'],
        'site_url' => confluence_site['url']
      }
    end

    def cloud_id
      document_source.settings&.dig('cloud_id')
    end

    def site_url
      document_source.settings&.dig('site_url')
    end

    def list_spaces(limit: 100)
      spaces = []
      start = 0

      loop do
        response = api_get("/wiki/api/v2/spaces", {
          limit: limit,
          start: start,
          status: 'current'
        })

        results = response['results'] || []
        spaces.concat(results.map { |space| space_to_hash(space) })

        break if results.size < limit

        start += limit
        break if start > 500 # Safety limit
      end

      spaces
    end

    def list_pages(space_id: nil, limit: 100)
      pages = []
      cursor = nil

      loop do
        params = {
          limit: limit,
          status: 'current',
          'body-format': 'storage'
        }
        params[:cursor] = cursor if cursor.present?
        params['space-id'] = space_id if space_id.present?

        response = api_get("/wiki/api/v2/pages", params)

        results = response['results'] || []
        pages.concat(results.map { |page| page_to_hash(page) })

        cursor = response.dig('_links', 'next')&.match(/cursor=([^&]+)/)&.captures&.first
        break if cursor.blank? || results.size < limit

        break if pages.size > 1000 # Safety limit
      end

      pages
    end

    def get_page(page_id)
      response = api_get("/wiki/api/v2/pages/#{page_id}", {
        'body-format': 'storage'
      })
      page_to_hash(response)
    end

    def get_page_content(page_id)
      response = api_get("/wiki/api/v2/pages/#{page_id}", {
        'body-format': 'storage'
      })

      storage_format = response.dig('body', 'storage', 'value') || ''
      confluence_to_markdown(storage_format)
    end

    def confluence_to_markdown(storage_format)
      return '' if storage_format.blank?

      # Parse the Confluence storage format (XML-like) and convert to Markdown
      doc = Nokogiri::HTML.fragment(storage_format)

      lines = []

      doc.children.each do |node|
        lines << process_node(node)
      end

      lines.flatten.join("\n").gsub(/\n{3,}/, "\n\n").strip
    end

    private

    def api_get(endpoint, params = {})
      url = "https://api.atlassian.com/ex/confluence/#{cloud_id}#{endpoint}"
      url += "?#{params.to_query}" if params.present?

      response = Faraday.get(url) do |req|
        req.headers['Authorization'] = "Bearer #{document_source.access_token}"
        req.headers['Accept'] = 'application/json'
      end

      unless response.success?
        error_body = JSON.parse(response.body) rescue {}
        raise "Confluence API error (#{response.status}): #{error_body['message'] || response.body}"
      end

      JSON.parse(response.body)
    end

    def space_to_hash(space)
      {
        id: space['id'],
        key: space['key'],
        name: space['name'],
        type: space['type'],
        status: space['status'],
        description: space.dig('description', 'plain', 'value'),
        homepage_id: space['homepageId']
      }
    end

    def page_to_hash(page)
      {
        id: page['id'],
        title: page['title'],
        space_id: page['spaceId'],
        status: page['status'],
        created_at: page['createdAt'],
        version: page.dig('version', 'number'),
        author_id: page.dig('version', 'authorId'),
        body: page.dig('body', 'storage', 'value'),
        url: "#{site_url}/wiki/spaces/#{page['spaceId']}/pages/#{page['id']}"
      }
    end

    def process_node(node)
      case node.name
      when 'h1'
        "# #{node.text.strip}"
      when 'h2'
        "## #{node.text.strip}"
      when 'h3'
        "### #{node.text.strip}"
      when 'h4'
        "#### #{node.text.strip}"
      when 'h5'
        "##### #{node.text.strip}"
      when 'h6'
        "###### #{node.text.strip}"
      when 'p'
        process_inline(node) + "\n"
      when 'ul'
        node.css('li').map { |li| "- #{process_inline(li)}" }.join("\n") + "\n"
      when 'ol'
        node.css('li').map.with_index { |li, i| "#{i + 1}. #{process_inline(li)}" }.join("\n") + "\n"
      when 'blockquote'
        node.text.strip.lines.map { |line| "> #{line}" }.join
      when 'pre', 'ac:structured-macro'
        if node.name == 'ac:structured-macro' && node['ac:name'] == 'code'
          code = node.at_css('ac:plain-text-body')&.text || ''
          lang = node.at_css('ac:parameter[@ac:name="language"]')&.text || ''
          "```#{lang}\n#{code}\n```\n"
        else
          "```\n#{node.text.strip}\n```\n"
        end
      when 'table'
        process_table(node)
      when 'hr'
        "---\n"
      when 'br'
        "\n"
      when 'a'
        href = node['href']
        text = node.text.strip
        href.present? ? "[#{text}](#{href})" : text
      when 'ac:image'
        "[Image]"
      when 'ac:link'
        ri_page = node.at_css('ri:page')
        if ri_page
          "[#{ri_page['ri:content-title']}]"
        else
          node.text.strip
        end
      when 'text'
        node.text
      else
        # Recursively process children for unknown elements
        node.children.map { |child| process_node(child) }.join
      end
    end

    def process_inline(node)
      node.children.map do |child|
        case child.name
        when 'strong', 'b'
          "**#{child.text}**"
        when 'em', 'i'
          "*#{child.text}*"
        when 'code'
          "`#{child.text}`"
        when 'a'
          href = child['href']
          text = child.text.strip
          href.present? ? "[#{text}](#{href})" : text
        when 'text'
          child.text
        else
          process_node(child)
        end
      end.join
    end

    def process_table(table)
      rows = table.css('tr').map do |row|
        cells = row.css('th, td').map { |cell| process_inline(cell).strip }
        "| #{cells.join(' | ')} |"
      end

      return '' if rows.empty?

      # Insert header separator after first row
      header_cells = table.at_css('tr')&.css('th, td')&.size || 1
      separator = "| #{(['---'] * header_cells).join(' | ')} |"

      rows.insert(1, separator)
      rows.join("\n") + "\n"
    end
  end
end
