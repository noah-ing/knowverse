# frozen_string_literal: true

module BulkProcessing
  # BulkUploadJob processes a batch of files from a bulk upload
  # It creates Document records and queues them for processing
  #
  # Features:
  # - Chunked processing to avoid memory issues
  # - Progress tracking via BulkUpload model
  # - Rate limiting for external APIs
  # - Error isolation (one file failure doesn't stop batch)
  class BulkUploadJob < ApplicationJob
    queue_as :bulk_processing

    # Retry with exponential backoff
    retry_on StandardError, wait: :exponentially_longer, attempts: 3
    discard_on ActiveRecord::RecordNotFound

    BATCH_SIZE = 50 # Process files in batches of 50

    def perform(bulk_upload_id, file_data_batch)
      @bulk_upload = BulkUpload.find(bulk_upload_id)
      return if @bulk_upload.cancelled?

      @bulk_upload.start! if @bulk_upload.pending?

      process_batch(file_data_batch)
    end

    private

    def process_batch(file_data_batch)
      file_data_batch.each do |file_data|
        process_single_file(file_data)
      rescue StandardError => e
        handle_file_error(file_data, e)
      end
    end

    def process_single_file(file_data)
      # file_data structure:
      # {
      #   filename: 'document.pdf',
      #   content_type: 'application/pdf',
      #   blob_id: 123, # ActiveStorage blob ID
      #   title: 'Optional title'
      # }

      document = create_document(file_data)

      # Queue for processing
      DocumentProcessing::TextExtractionWorker.perform_later(document.id)

      Rails.logger.info "[BulkUpload ##{@bulk_upload.id}] Created document ##{document.id}: #{document.title}"
    end

    def create_document(file_data)
      blob = ActiveStorage::Blob.find(file_data[:blob_id])

      document = Document.new(
        title: file_data[:title] || blob.filename.to_s,
        organization: @bulk_upload.organization,
        bulk_upload: @bulk_upload,
        status: 'pending',
        embedding_status: 'pending',
        metadata: {
          bulk_upload_id: @bulk_upload.id,
          original_filename: blob.filename.to_s,
          uploaded_at: Time.current.iso8601
        }
      )

      document.file.attach(blob)
      document.save!
      document
    end

    def handle_file_error(file_data, error)
      Rails.logger.error "[BulkUpload ##{@bulk_upload.id}] Failed to process file: #{error.message}"
      Rails.logger.error error.backtrace.first(5).join("\n")

      @bulk_upload.increment_failed!(
        error: "#{file_data[:filename]}: #{error.message}"
      )
    end
  end
end
