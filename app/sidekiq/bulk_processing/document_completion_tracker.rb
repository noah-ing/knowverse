# frozen_string_literal: true

module BulkProcessing
  # DocumentCompletionTracker is called after embedding generation completes
  # to update the BulkUpload progress
  class DocumentCompletionTracker < ApplicationJob
    queue_as :bulk_processing

    def perform(document_id, success:)
      document = Document.find_by(id: document_id)
      return unless document&.bulk_upload_id

      bulk_upload = document.bulk_upload
      return if bulk_upload.finished?

      if success
        bulk_upload.increment_processed!
      else
        bulk_upload.increment_failed!(
          document_id: document_id,
          error: document.metadata['embedding_error'] || document.metadata['error_message']
        )
      end
    end
  end
end
