# frozen_string_literal: true

# V7-010: Add missing database indexes for performance optimization
# Based on audit findings (PERF-009):
# - Missing composite index on documents (organization_id, created_at)
# - Additional indexes for common query patterns
class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Composite index for documents filtered by organization and sorted by created_at
    # Supports queries like: organization.documents.order(created_at: :desc)
    add_index :documents, [:organization_id, :created_at], name: 'idx_documents_org_created_at'

    # Composite index for documents filtered by organization and status
    # Supports queries like: organization.documents.where(status: 'processed')
    add_index :documents, [:organization_id, :status], name: 'idx_documents_org_status'

    # Composite index for documents by user and created_at (user's recent documents)
    # Supports queries like: user.documents.order(created_at: :desc).limit(5)
    add_index :documents, [:user_id, :created_at], name: 'idx_documents_user_created_at'

    # Index for conversation messages by role for analytics queries
    # Already has index on conversation_session_id, role combination is useful
    add_index :conversation_messages, [:conversation_session_id, :role],
              name: 'idx_conv_msgs_session_role'

    # Index for vector embeddings by document and status for batch processing
    add_index :vector_embeddings, [:document_id, :status], name: 'idx_vector_emb_doc_status'
  end
end
