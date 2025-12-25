module Connectors
  class GithubController < ApplicationController
    before_action :authenticate_user!
    before_action :set_organization
    before_action :ensure_organization_member
    before_action :set_document_source, only: [:show, :destroy, :sync]

    def show
      @document_source = @organization.document_sources.github.first
      @synced_documents = @document_source&.documents&.order(created_at: :desc)&.limit(10) || []
    end

    def new
      unless Connectors::GithubService.configured?
        redirect_to organization_documents_path(@organization),
          alert: 'GitHub integration is not configured. Please contact your administrator.'
        return
      end

      @document_source = @organization.document_sources.github.first

      if @document_source&.connected?
        redirect_to organization_connectors_github_path(@organization)
      end
    end

    def create
      unless Connectors::GithubService.configured?
        redirect_to organization_documents_path(@organization),
          alert: 'GitHub integration is not configured.'
        return
      end

      # Generate state token for CSRF protection
      state = SecureRandom.hex(32)
      session[:github_oauth_state] = state

      authorize_url = Connectors::GithubService.authorize_url(@organization.id, state: state)
      redirect_to authorize_url, allow_other_host: true
    end

    def callback
      # Verify state token
      if params[:state] != session[:github_oauth_state]
        redirect_to organization_documents_path(@organization),
          alert: 'Invalid OAuth state. Please try connecting again.'
        return
      end
      session.delete(:github_oauth_state)

      # Check for errors
      if params[:error].present?
        redirect_to organization_documents_path(@organization),
          alert: "GitHub authorization failed: #{params[:error_description] || params[:error]}"
        return
      end

      # Exchange code for tokens
      begin
        credentials = Connectors::GithubService.exchange_code(params[:code], @organization.id)

        # Find or create document source
        document_source = @organization.document_sources.github.first_or_initialize
        document_source.credentials_hash = credentials
        document_source.sync_status = 'connected'

        # Get authenticated user info
        service = Connectors::GithubService.new(document_source)
        user_info = service.get_authenticated_user

        document_source.name = user_info['login'] || 'GitHub'
        document_source.settings = {
          'username' => user_info['login'],
          'user_id' => user_info['id'],
          'avatar_url' => user_info['avatar_url']
        }
        document_source.save!

        redirect_to organization_connectors_github_path(@organization),
          notice: 'GitHub connected successfully! You can now sync your repositories.'
      rescue => e
        Rails.logger.error("GitHub OAuth error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        redirect_to organization_documents_path(@organization),
          alert: "Failed to connect GitHub: #{e.message}"
      end
    end

    def destroy
      @document_source.mark_disconnected!

      redirect_to organization_documents_path(@organization),
        notice: 'GitHub disconnected successfully.'
    end

    def sync
      unless @document_source&.connected?
        redirect_to organization_connectors_github_path(@organization),
          alert: 'GitHub is not connected.'
        return
      end

      # Queue sync job
      Connectors::GithubSyncWorker.perform_later(@document_source.id)

      redirect_to organization_connectors_github_path(@organization),
        notice: 'GitHub sync started. Documents will appear shortly.'
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
      @document_source = @organization.document_sources.github.first
    end
  end
end
