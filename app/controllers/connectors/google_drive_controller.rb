module Connectors
  class GoogleDriveController < ApplicationController
    before_action :authenticate_user!
    before_action :set_organization
    before_action :ensure_organization_member
    before_action :set_document_source, only: [:show, :destroy, :sync]

    def show
      @document_source = @organization.document_sources.google_drive.first
      @synced_documents = @document_source&.documents&.order(created_at: :desc)&.limit(10) || []
    end

    def new
      unless Connectors::GoogleDriveService.configured?
        redirect_to organization_documents_path(@organization),
          alert: 'Google Drive integration is not configured. Please contact your administrator.'
        return
      end

      @document_source = @organization.document_sources.google_drive.first

      if @document_source&.connected?
        redirect_to organization_connectors_google_drive_path(@organization)
      end
    end

    def create
      unless Connectors::GoogleDriveService.configured?
        redirect_to organization_documents_path(@organization),
          alert: 'Google Drive integration is not configured.'
        return
      end

      # Generate state token for CSRF protection
      state = SecureRandom.hex(32)
      session[:google_oauth_state] = state

      authorize_url = Connectors::GoogleDriveService.authorize_url(@organization.id, state: state)
      redirect_to authorize_url, allow_other_host: true
    end

    def callback
      # Verify state token
      if params[:state] != session[:google_oauth_state]
        redirect_to organization_documents_path(@organization),
          alert: 'Invalid OAuth state. Please try connecting again.'
        return
      end
      session.delete(:google_oauth_state)

      # Check for errors
      if params[:error].present?
        redirect_to organization_documents_path(@organization),
          alert: "Google Drive authorization failed: #{params[:error_description] || params[:error]}"
        return
      end

      # Exchange code for tokens
      begin
        credentials = Connectors::GoogleDriveService.exchange_code(params[:code], @organization.id)

        # Find or create document source
        document_source = @organization.document_sources.google_drive.first_or_initialize
        document_source.credentials_hash = credentials
        document_source.sync_status = 'connected'
        document_source.name = 'Google Drive'
        document_source.save!

        redirect_to organization_connectors_google_drive_path(@organization),
          notice: 'Google Drive connected successfully! You can now sync your documents.'
      rescue => e
        Rails.logger.error("Google Drive OAuth error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        redirect_to organization_documents_path(@organization),
          alert: "Failed to connect Google Drive: #{e.message}"
      end
    end

    def destroy
      @document_source.mark_disconnected!

      redirect_to organization_documents_path(@organization),
        notice: 'Google Drive disconnected successfully.'
    end

    def sync
      unless @document_source&.connected?
        redirect_to organization_connectors_google_drive_path(@organization),
          alert: 'Google Drive is not connected.'
        return
      end

      # Queue sync job
      Connectors::GoogleDriveSyncWorker.perform_later(@document_source.id)

      redirect_to organization_connectors_google_drive_path(@organization),
        notice: 'Google Drive sync started. Documents will appear shortly.'
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
      @document_source = @organization.document_sources.google_drive.first
    end
  end
end
