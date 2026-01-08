class HomeController < ApplicationController
  before_action :authenticate_user!, only: [:dashboard]

  def index
  end

  def dashboard
    return unless user_signed_in? && current_organization

    # Pre-compute dashboard stats to avoid queries in view
    @org_count = current_user.organizations.count
    @doc_count = current_organization.documents.count
    @vector_count = VectorEmbedding.joins(:document)
                                   .where(documents: { organization_id: current_organization.id })
                                   .count
    @conv_count = ConversationSession.where(organization_id: current_organization.id).count

    # Recent documents with eager loading
    @recent_documents = current_organization.documents
                                            .order(created_at: :desc)
                                            .limit(5)
  end
end
