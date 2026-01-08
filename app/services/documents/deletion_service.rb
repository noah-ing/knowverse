# frozen_string_literal: true

module Documents
  # Handles document deletion logic including related data cleanup
  # Extracted from DocumentsController for separation of concerns
  class DeletionService
    attr_reader :organization

    def initialize(organization)
      @organization = organization
    end

    # Delete a single document with all related data
    def delete_document(document)
      ActiveRecord::Base.transaction do
        delete_related_data(document)
        document.destroy!
      end
    end

    # Delete multiple documents in bulk
    def bulk_delete(document_ids)
      return { count: 0, success: false, error: 'No documents selected' } if document_ids.blank?

      documents = organization.documents.where(id: document_ids)
      count = documents.count

      ActiveRecord::Base.transaction do
        documents.each do |document|
          delete_related_data(document)
          document.destroy!
        end
      end

      { count: count, success: true }
    rescue StandardError => e
      Rails.logger.error "Bulk delete error: #{e.message}\n#{e.backtrace.join("\n")}"
      { count: 0, success: false, error: e.message.split("\n").first }
    end

    private

    def delete_related_data(document)
      delete_vector_projections(document)
      delete_vector_embeddings(document)
      delete_cluster_memberships(document)
      delete_search_feedback(document)
    end

    def delete_vector_projections(document)
      embeddings = VectorEmbedding.where(document_id: document.id)
      embeddings.each do |embedding|
        safe_delete_projections(embedding.id)
      end
    end

    def safe_delete_projections(embedding_id)
      ActiveRecord::Base.connection.execute(
        "DELETE FROM vector_projections WHERE vector_embedding_id = #{embedding_id}"
      )
    rescue StandardError => e
      Rails.logger.error "Error deleting vector projections: #{e.message}"
    end

    def delete_vector_embeddings(document)
      VectorEmbedding.where(document_id: document.id).delete_all
    end

    def delete_cluster_memberships(document)
      return unless defined?(ClusterMembership)

      ClusterMembership.where(document_id: document.id).delete_all
    end

    def delete_search_feedback(document)
      return unless defined?(SearchFeedback)

      SearchFeedback.where(document_id: document.id).delete_all
    end
  end
end
