# frozen_string_literal: true

module Api
  module V1
    # BulkUploadsController handles enterprise-scale document uploads
    #
    # Endpoints:
    #   POST   /api/v1/organizations/:org_id/bulk_uploads - Create bulk upload
    #   GET    /api/v1/organizations/:org_id/bulk_uploads/:id - Get status
    #   GET    /api/v1/organizations/:org_id/bulk_uploads - List uploads
    #   DELETE /api/v1/organizations/:org_id/bulk_uploads/:id - Cancel upload
    #
    # Upload flow:
    #   1. Client creates BulkUpload with total_files count
    #   2. Client uploads files directly to ActiveStorage (direct upload)
    #   3. Client sends blob IDs to start processing
    #   4. Server processes in background, client polls for progress
    class BulkUploadsController < Api::V1::BaseController
      before_action :authenticate_user!
      before_action :set_organization
      before_action :set_bulk_upload, only: [:show, :destroy, :add_files, :start]

      # GET /api/v1/organizations/:organization_id/bulk_uploads
      def index
        @bulk_uploads = @organization.bulk_uploads
                                     .includes(:user)
                                     .recent
                                     .page(params[:page])
                                     .per(params[:per_page] || 20)

        render json: {
          bulk_uploads: @bulk_uploads.map(&:summary),
          meta: {
            total: @bulk_uploads.total_count,
            page: @bulk_uploads.current_page,
            per_page: @bulk_uploads.limit_value
          }
        }
      end

      # GET /api/v1/organizations/:organization_id/bulk_uploads/:id
      def show
        render json: {
          bulk_upload: @bulk_upload.summary,
          documents: @bulk_upload.documents.select(:id, :title, :status, :embedding_status).limit(100),
          errors: @bulk_upload.metadata['errors']&.last(20) || []
        }
      end

      # POST /api/v1/organizations/:organization_id/bulk_uploads
      # Creates a new bulk upload session
      #
      # Params:
      #   total_files: integer - expected number of files
      #   source: string - 'api', 'connector', 'form'
      def create
        @bulk_upload = @organization.bulk_uploads.new(
          user: current_user,
          total_files: params[:total_files].to_i,
          metadata: {
            source: params[:source] || 'api',
            batch_size: params[:batch_size] || 50,
            client_info: request.user_agent
          }
        )

        if @bulk_upload.save
          render json: {
            bulk_upload: @bulk_upload.summary,
            upload_url: rails_direct_uploads_url,
            instructions: {
              step1: 'Upload files to upload_url using ActiveStorage direct upload',
              step2: 'Collect signed_blob_ids from upload responses',
              step3: 'POST to add_files_url with blob_ids array',
              step4: 'POST to start_url to begin processing',
              step5: 'Poll show_url for progress'
            },
            urls: {
              add_files: add_files_api_v1_organization_bulk_upload_url(@organization, @bulk_upload),
              start: start_api_v1_organization_bulk_upload_url(@organization, @bulk_upload),
              status: api_v1_organization_bulk_upload_url(@organization, @bulk_upload)
            }
          }, status: :created
        else
          render json: { errors: @bulk_upload.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/organizations/:organization_id/bulk_uploads/:id/add_files
      # Add files to the bulk upload
      #
      # Params:
      #   files: array of { blob_id: string, title: string (optional) }
      def add_files
        return render_error('Bulk upload already started') if @bulk_upload.processing?
        return render_error('Bulk upload already finished') if @bulk_upload.finished?

        files = params[:files] || []
        return render_error('No files provided') if files.empty?

        added_count = 0
        files.each do |file_data|
          begin
            blob = ActiveStorage::Blob.find_signed(file_data[:blob_id])
            @bulk_upload.metadata['pending_files'] ||= []
            @bulk_upload.metadata['pending_files'] << {
              blob_id: blob.id,
              filename: blob.filename.to_s,
              title: file_data[:title],
              content_type: blob.content_type
            }
            added_count += 1
          rescue ActiveRecord::RecordNotFound
            Rails.logger.warn "Invalid blob_id: #{file_data[:blob_id]}"
          end
        end

        @bulk_upload.total_files = (@bulk_upload.metadata['pending_files'] || []).size
        @bulk_upload.save!

        render json: {
          bulk_upload: @bulk_upload.summary,
          files_added: added_count,
          total_pending: @bulk_upload.total_files
        }
      end

      # POST /api/v1/organizations/:organization_id/bulk_uploads/:id/start
      # Start processing the bulk upload
      def start
        return render_error('Bulk upload already started') unless @bulk_upload.pending?

        pending_files = @bulk_upload.metadata['pending_files'] || []
        return render_error('No files to process') if pending_files.empty?

        # Queue processing in batches
        batch_size = @bulk_upload.metadata['batch_size'] || 50
        pending_files.each_slice(batch_size).with_index do |batch, index|
          BulkProcessing::BulkUploadJob.perform_later(@bulk_upload.id, batch)
        end

        @bulk_upload.start!

        render json: {
          bulk_upload: @bulk_upload.summary,
          message: "Processing started for #{pending_files.size} files in #{(pending_files.size.to_f / batch_size).ceil} batches"
        }
      end

      # DELETE /api/v1/organizations/:organization_id/bulk_uploads/:id
      # Cancel a bulk upload
      def destroy
        if @bulk_upload.finished?
          render_error('Cannot cancel finished upload')
        else
          @bulk_upload.cancel!
          render json: { bulk_upload: @bulk_upload.summary, message: 'Upload cancelled' }
        end
      end

      private

      def set_organization
        @organization = current_user.organizations.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Organization not found' }, status: :not_found
      end

      def set_bulk_upload
        @bulk_upload = @organization.bulk_uploads.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Bulk upload not found' }, status: :not_found
      end

      def render_error(message)
        render json: { error: message }, status: :unprocessable_entity
      end
    end
  end
end
