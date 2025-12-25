module Connectors
  class SlackController < ApplicationController
    before_action :authenticate_user!
    before_action :set_organization
    before_action :ensure_organization_member
    before_action :set_document_source, only: [:show, :destroy, :sync]

    def show
      @document_source = @organization.document_sources.slack.first
      @synced_documents = @document_source&.documents&.order(created_at: :desc)&.limit(10) || []
    end

    def new
      unless Connectors::SlackService.configured?
        redirect_to organization_documents_path(@organization),
          alert: 'Slack integration is not configured. Please contact your administrator.'
        return
      end

      @document_source = @organization.document_sources.slack.first

      if @document_source&.connected?
        redirect_to organization_connectors_slack_path(@organization)
      end
    end

    def create
      unless Connectors::SlackService.configured?
        redirect_to organization_documents_path(@organization),
          alert: 'Slack integration is not configured.'
        return
      end

      # Generate state token for CSRF protection
      state = SecureRandom.hex(32)
      session[:slack_oauth_state] = state

      authorize_url = Connectors::SlackService.authorize_url(@organization.id, state: state)
      redirect_to authorize_url, allow_other_host: true
    end

    def callback
      # Verify state token
      if params[:state] != session[:slack_oauth_state]
        redirect_to organization_documents_path(@organization),
          alert: 'Invalid OAuth state. Please try connecting again.'
        return
      end
      session.delete(:slack_oauth_state)

      # Check for errors
      if params[:error].present?
        redirect_to organization_documents_path(@organization),
          alert: "Slack authorization failed: #{params[:error]}"
        return
      end

      # Exchange code for tokens
      begin
        credentials = Connectors::SlackService.exchange_code(params[:code], @organization.id)

        # Find or create document source
        document_source = @organization.document_sources.slack.first_or_initialize
        document_source.credentials_hash = credentials
        document_source.sync_status = 'connected'
        document_source.name = credentials['team_name'] || 'Slack'
        document_source.settings = {
          'team_id' => credentials['team_id'],
          'team_name' => credentials['team_name'],
          'bot_user_id' => credentials['bot_user_id']
        }
        document_source.save!

        redirect_to organization_connectors_slack_path(@organization),
          notice: 'Slack connected successfully! You can now sync your channels.'
      rescue => e
        Rails.logger.error("Slack OAuth error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        redirect_to organization_documents_path(@organization),
          alert: "Failed to connect Slack: #{e.message}"
      end
    end

    def destroy
      @document_source.mark_disconnected!

      redirect_to organization_documents_path(@organization),
        notice: 'Slack disconnected successfully.'
    end

    def sync
      unless @document_source&.connected?
        redirect_to organization_connectors_slack_path(@organization),
          alert: 'Slack is not connected.'
        return
      end

      # Queue sync job
      Connectors::SlackSyncWorker.perform_later(@document_source.id)

      redirect_to organization_connectors_slack_path(@organization),
        notice: 'Slack sync started. Channel messages will appear shortly.'
    end

    private

    def set_organization
      @organization = Organization.find(params[:organization_id])
    end

    def ensure_organization_member
      unless @organization.users.include?(current_user)
        redirect_to organizations_path, alert: 'You do not have access to this organization.'
      end
    end

    def set_document_source
      @document_source = @organization.document_sources.slack.first
    end
  end
end
