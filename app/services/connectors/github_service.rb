module Connectors
  class GithubService
    OAUTH_AUTHORIZE_URL = 'https://github.com/login/oauth/authorize'.freeze
    OAUTH_TOKEN_URL = 'https://github.com/login/oauth/access_token'.freeze
    API_BASE = 'https://api.github.com'.freeze

    attr_reader :document_source

    def initialize(document_source)
      @document_source = document_source
    end

    def self.client_id
      ENV.fetch('GITHUB_CLIENT_ID', nil)
    end

    def self.client_secret
      ENV.fetch('GITHUB_CLIENT_SECRET', nil)
    end

    def self.redirect_uri(organization_id)
      base = ENV.fetch('GITHUB_REDIRECT_URI_BASE', 'http://localhost:3000')
      "#{base}/organizations/#{organization_id}/connectors/github/callback"
    end

    def self.configured?
      client_id.present? && client_secret.present?
    end

    def self.authorize_url(organization_id, state: nil)
      params = {
        client_id: client_id,
        redirect_uri: redirect_uri(organization_id),
        scope: 'repo read:org',
        state: state
      }.compact

      "#{OAUTH_AUTHORIZE_URL}?#{params.to_query}"
    end

    def self.exchange_code(code, organization_id)
      response = Faraday.post(OAUTH_TOKEN_URL) do |req|
        req.headers['Accept'] = 'application/json'
        req.headers['Content-Type'] = 'application/json'
        req.body = {
          client_id: client_id,
          client_secret: client_secret,
          code: code,
          redirect_uri: redirect_uri(organization_id)
        }.to_json
      end

      result = JSON.parse(response.body)

      if result['error'].present?
        raise "GitHub OAuth error: #{result['error_description'] || result['error']}"
      end

      {
        'access_token' => result['access_token'],
        'token_type' => result['token_type'],
        'scope' => result['scope']
      }
    end

    def list_repositories(visibility: 'all', per_page: 100)
      repos = []
      page = 1

      loop do
        response = api_get('/user/repos', {
          visibility: visibility,
          per_page: per_page,
          page: page,
          sort: 'updated',
          direction: 'desc'
        })

        break if response.empty?

        repos.concat(response.map { |repo| repo_to_hash(repo) })
        break if response.size < per_page

        page += 1
        break if page > 10 # Safety limit
      end

      repos
    end

    def get_repository(owner, repo)
      response = api_get("/repos/#{owner}/#{repo}")
      repo_to_hash(response)
    end

    def list_markdown_files(owner, repo, path: '', max_depth: 3)
      return [] if max_depth <= 0

      files = []

      begin
        contents = api_get("/repos/#{owner}/#{repo}/contents/#{path}")
        contents = [contents] unless contents.is_a?(Array)

        contents.each do |item|
          case item['type']
          when 'file'
            if markdown_file?(item['name'])
              files << {
                path: item['path'],
                name: item['name'],
                sha: item['sha'],
                size: item['size'],
                download_url: item['download_url'],
                html_url: item['html_url']
              }
            end
          when 'dir'
            # Recursively search directories
            files.concat(list_markdown_files(owner, repo, path: item['path'], max_depth: max_depth - 1))
          end
        end
      rescue => e
        Rails.logger.warn("GitHub: Error listing files in #{owner}/#{repo}/#{path}: #{e.message}")
      end

      files
    end

    def get_file_content(owner, repo, path)
      response = api_get("/repos/#{owner}/#{repo}/contents/#{path}")

      if response['encoding'] == 'base64'
        Base64.decode64(response['content'])
      else
        response['content']
      end
    end

    def get_readme(owner, repo)
      response = api_get("/repos/#{owner}/#{repo}/readme")

      if response['encoding'] == 'base64'
        Base64.decode64(response['content'])
      else
        response['content']
      end
    rescue => e
      Rails.logger.debug("GitHub: No README found for #{owner}/#{repo}: #{e.message}")
      nil
    end

    def list_issues(owner, repo, state: 'all', per_page: 100)
      issues = []
      page = 1

      loop do
        response = api_get("/repos/#{owner}/#{repo}/issues", {
          state: state,
          per_page: per_page,
          page: page,
          sort: 'updated',
          direction: 'desc'
        })

        break if response.empty?

        # Filter out pull requests (they appear in issues endpoint)
        real_issues = response.reject { |issue| issue['pull_request'].present? }
        issues.concat(real_issues.map { |issue| issue_to_hash(issue) })

        break if response.size < per_page

        page += 1
        break if page > 5 # Safety limit
      end

      issues
    end

    def get_authenticated_user
      api_get('/user')
    end

    private

    def api_get(endpoint, params = {})
      url = "#{API_BASE}#{endpoint}"
      url += "?#{params.to_query}" if params.present?

      response = Faraday.get(url) do |req|
        req.headers['Accept'] = 'application/vnd.github+json'
        req.headers['Authorization'] = "Bearer #{document_source.access_token}"
        req.headers['X-GitHub-Api-Version'] = '2022-11-28'
      end

      unless response.success?
        error_body = JSON.parse(response.body) rescue {}
        raise "GitHub API error (#{response.status}): #{error_body['message'] || response.body}"
      end

      JSON.parse(response.body)
    end

    def repo_to_hash(repo)
      {
        id: repo['id'].to_s,
        name: repo['name'],
        full_name: repo['full_name'],
        description: repo['description'],
        html_url: repo['html_url'],
        default_branch: repo['default_branch'],
        private: repo['private'],
        updated_at: repo['updated_at'],
        pushed_at: repo['pushed_at'],
        language: repo['language'],
        stargazers_count: repo['stargazers_count'],
        owner: repo['owner']['login']
      }
    end

    def issue_to_hash(issue)
      {
        id: issue['id'].to_s,
        number: issue['number'],
        title: issue['title'],
        body: issue['body'],
        state: issue['state'],
        html_url: issue['html_url'],
        created_at: issue['created_at'],
        updated_at: issue['updated_at'],
        labels: issue['labels']&.map { |l| l['name'] } || [],
        user: issue['user']['login']
      }
    end

    def markdown_file?(filename)
      %w[.md .markdown .mdown .mkd .mkdn .mdwn .mdtxt .mdtext .txt .rst].any? do |ext|
        filename.downcase.end_with?(ext)
      end
    end
  end
end
