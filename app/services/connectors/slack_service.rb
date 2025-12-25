module Connectors
  class SlackService
    OAUTH_AUTHORIZE_URL = 'https://slack.com/oauth/v2/authorize'.freeze
    OAUTH_TOKEN_URL = 'https://slack.com/api/oauth.v2.access'.freeze
    API_BASE = 'https://slack.com/api'.freeze

    attr_reader :document_source

    def initialize(document_source)
      @document_source = document_source
    end

    def self.client_id
      ENV.fetch('SLACK_CLIENT_ID', nil)
    end

    def self.client_secret
      ENV.fetch('SLACK_CLIENT_SECRET', nil)
    end

    def self.redirect_uri(organization_id)
      base = ENV.fetch('SLACK_REDIRECT_URI_BASE', 'http://localhost:3000')
      "#{base}/organizations/#{organization_id}/connectors/slack/callback"
    end

    def self.configured?
      client_id.present? && client_secret.present?
    end

    def self.authorize_url(organization_id, state: nil)
      params = {
        client_id: client_id,
        redirect_uri: redirect_uri(organization_id),
        scope: 'channels:history,channels:read,users:read,team:read',
        state: state
      }.compact

      "#{OAUTH_AUTHORIZE_URL}?#{params.to_query}"
    end

    def self.exchange_code(code, organization_id)
      response = Faraday.post(OAUTH_TOKEN_URL) do |req|
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        req.body = {
          client_id: client_id,
          client_secret: client_secret,
          code: code,
          redirect_uri: redirect_uri(organization_id)
        }
      end

      result = JSON.parse(response.body)

      unless result['ok']
        raise "Slack OAuth error: #{result['error']}"
      end

      {
        'access_token' => result['access_token'],
        'team_id' => result['team']['id'],
        'team_name' => result['team']['name'],
        'bot_user_id' => result['bot_user_id'],
        'authed_user_id' => result.dig('authed_user', 'id')
      }
    end

    def list_channels
      channels = []
      cursor = nil

      loop do
        params = { types: 'public_channel', limit: 200 }
        params[:cursor] = cursor if cursor.present?

        response = api_get('conversations.list', params)

        unless response['ok']
          raise "Slack API error: #{response['error']}"
        end

        channels.concat(response['channels'].map { |ch| channel_to_hash(ch) })

        cursor = response.dig('response_metadata', 'next_cursor')
        break if cursor.blank?
      end

      channels
    end

    def get_channel_history(channel_id, oldest: nil, limit: 1000)
      messages = []
      cursor = nil
      fetched = 0

      # Default to last 30 days if not specified
      oldest ||= (Time.current - 30.days).to_i

      loop do
        params = {
          channel: channel_id,
          limit: [200, limit - fetched].min,
          oldest: oldest
        }
        params[:cursor] = cursor if cursor.present?

        response = api_get('conversations.history', params)

        unless response['ok']
          if response['error'] == 'not_in_channel'
            Rails.logger.warn("Slack: Bot not in channel #{channel_id}, skipping")
            return []
          end
          raise "Slack API error: #{response['error']}"
        end

        messages.concat(response['messages'].map { |msg| message_to_hash(msg) })
        fetched += response['messages'].size

        break if fetched >= limit

        cursor = response.dig('response_metadata', 'next_cursor')
        break if cursor.blank? || !response['has_more']
      end

      messages
    end

    def get_thread_replies(channel_id, thread_ts)
      messages = []
      cursor = nil

      loop do
        params = {
          channel: channel_id,
          ts: thread_ts,
          limit: 200
        }
        params[:cursor] = cursor if cursor.present?

        response = api_get('conversations.replies', params)

        unless response['ok']
          raise "Slack API error: #{response['error']}"
        end

        # Skip the first message (parent) since we already have it
        thread_messages = response['messages'][1..] || []
        messages.concat(thread_messages.map { |msg| message_to_hash(msg) })

        cursor = response.dig('response_metadata', 'next_cursor')
        break if cursor.blank? || !response['has_more']
      end

      messages
    end

    def get_user_info(user_id)
      @users_cache ||= {}
      return @users_cache[user_id] if @users_cache.key?(user_id)

      response = api_get('users.info', { user: user_id })

      if response['ok']
        user = response['user']
        @users_cache[user_id] = {
          id: user['id'],
          name: user['name'],
          real_name: user['real_name'],
          display_name: user.dig('profile', 'display_name'),
          avatar: user.dig('profile', 'image_48')
        }
      else
        @users_cache[user_id] = { id: user_id, name: 'Unknown User' }
      end

      @users_cache[user_id]
    end

    def get_team_info
      response = api_get('team.info')

      if response['ok']
        team = response['team']
        {
          id: team['id'],
          name: team['name'],
          domain: team['domain'],
          icon: team['icon']['image_68']
        }
      else
        nil
      end
    end

    private

    def api_get(method, params = {})
      url = "#{API_BASE}/#{method}"
      url += "?#{params.to_query}" if params.present?

      response = Faraday.get(url) do |req|
        req.headers['Authorization'] = "Bearer #{document_source.access_token}"
        req.headers['Content-Type'] = 'application/json'
      end

      JSON.parse(response.body)
    end

    def channel_to_hash(channel)
      {
        id: channel['id'],
        name: channel['name'],
        is_channel: channel['is_channel'],
        is_private: channel['is_private'],
        is_archived: channel['is_archived'],
        num_members: channel['num_members'],
        topic: channel.dig('topic', 'value'),
        purpose: channel.dig('purpose', 'value'),
        created: channel['created']
      }
    end

    def message_to_hash(message)
      {
        ts: message['ts'],
        user: message['user'],
        text: message['text'],
        type: message['type'],
        subtype: message['subtype'],
        thread_ts: message['thread_ts'],
        reply_count: message['reply_count'] || 0,
        reactions: message['reactions']&.map { |r| { name: r['name'], count: r['count'] } } || [],
        attachments: message['attachments']&.map { |a| { title: a['title'], text: a['text'] } } || [],
        files: message['files']&.map { |f| { name: f['name'], url: f['url_private'] } } || []
      }
    end
  end
end
