# frozen_string_literal: true

module DocumentProcessing
  # QdrantMigrationWorker - Migrates documents to Qdrant vector index
  #
  # This replaces the old HnswMigrationWorker that used the fictional WASM service.
  # Now uses Qdrant (Rust) for all vector operations.
  #
  # NOTE: Class is still named HnswMigrationWorker for backwards compatibility
  # with existing queued jobs. Will process any jobs in the :vector_migration queue.
  #
  class HnswMigrationWorker < ActiveJob::Base
    queue_as :vector_migration

    # Retry configuration for transient Qdrant/Haystack failures
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    # For backwards compatibility with existing code
    def self.perform_async(batch_size = 100, organization_id = nil, _model_name = 'base', _dimension = nil)
      perform_later(batch_size, organization_id)
    end

    def perform(batch_size = 100, organization_id = nil, *_args)
      Rails.logger.info("Starting Qdrant migration batch (size: #{batch_size}, org: #{organization_id || 'all'})")

      search_service = Search::UnifiedSearchService.new

      # Check Qdrant health first
      unless search_service.healthy?
        Rails.logger.error("Qdrant cluster is not healthy. Skipping migration batch.")
        # Re-queue for later
        self.class.set(wait: 5.minutes).perform_later(batch_size, organization_id)
        return
      end

      # Prepare scope for documents to migrate
      # Documents with embeddings but not yet in Qdrant
      scope = Document.where(indexed_in_hnsw: false)
                      .where.not(embedding: nil)
                      .where(embedding_status: 'processed')
                      .where(status: 'active')

      # Filter by organization if specified
      scope = scope.where(organization_id: organization_id) if organization_id

      # Order by priority and limit to batch size
      documents = scope.order(migration_priority: :desc, created_at: :asc)
                       .limit(batch_size)

      migrated_count = 0
      failed_count = 0

      # Process each document
      documents.find_each do |document|
        if migrate_document_to_qdrant(document, search_service)
          migrated_count += 1
        else
          failed_count += 1
        end
      end

      Rails.logger.info("Qdrant migration batch complete: #{migrated_count} migrated, #{failed_count} failed")

      # Schedule next batch if more documents exist
      remaining_count = scope.count
      if remaining_count > batch_size
        Rails.logger.info("Scheduling next Qdrant migration batch. Remaining: #{remaining_count - batch_size}")
        self.class.set(wait: 30.seconds).perform_later(batch_size, organization_id)
      end
    end

    private

    def migrate_document_to_qdrant(document, search_service)
      Rails.logger.info("Migrating document #{document.id} to Qdrant")

      begin
        # Use UnifiedSearchService to index the document
        result = search_service.index_document(document)

        if result[:success]
          # Mark as migrated (using indexed_in_hnsw for backward compatibility)
          document.update!(
            indexed_in_hnsw: true,
            hnsw_index_reference: "qdrant:#{document.organization_id}:#{document.id}",
            migration_error: nil
          )

          Rails.logger.info("Successfully migrated document #{document.id} to Qdrant")
          true
        else
          raise "Qdrant upsert failed: #{result[:error]}"
        end
      rescue => e
        Rails.logger.error("Qdrant migration failed for document #{document.id}: #{e.message}")

        document.update(
          migration_error: e.message,
          migration_priority: [document.migration_priority.to_i - 1, 0].max
        )

        false
      end
    end
  end
end
