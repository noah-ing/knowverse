# frozen_string_literal: true

module Documents
  # Handles document filtering, sorting, and pagination logic
  # Extracted from DocumentsController for separation of concerns
  class FilterService
    VALID_SORT_FIELDS = %w[created_at title status embedding_status file_type word_count updated_at].freeze
    DEFAULT_SORT_FIELD = 'created_at'
    DEFAULT_SORT_DIRECTION = 'desc'
    DEFAULT_PER_PAGE = 10

    attr_reader :params, :filter_params, :sort_field, :sort_direction

    def initialize(params)
      @params = params
      @filter_params = {}
      @sort_field = DEFAULT_SORT_FIELD
      @sort_direction = DEFAULT_SORT_DIRECTION
    end

    # Apply all filters and return filtered query
    def apply_filters(documents)
      documents = filter_by_status(documents)
      documents = filter_by_embedding_status(documents)
      documents = filter_by_file_type(documents)
      documents = filter_by_date_range(documents)
      documents = filter_by_search_term(documents)
      documents
    end

    # Apply sorting to documents
    def apply_sorting(documents)
      @sort_field = normalize_sort_field(params[:sort_by])
      @sort_direction = normalize_sort_direction(params[:sort_direction])

      documents.order("#{sort_field} #{sort_direction}")
    end

    # Apply pagination
    def paginate(documents)
      per_page = params[:per_page].present? ? params[:per_page].to_i : DEFAULT_PER_PAGE
      documents.page(params[:page] || 1).per(per_page)
    end

    # Convenience method: apply filters, sorting, and pagination
    def apply_all(documents)
      documents = apply_filters(documents)
      documents = apply_sorting(documents)
      paginate(documents)
    end

    # Search documents by title or content
    def search(documents, query)
      return Document.none if query.blank?

      sanitized_query = Document.sanitize_sql_like(query)
      documents.where("title ILIKE ? OR content ILIKE ?", "%#{sanitized_query}%", "%#{sanitized_query}%")
    end

    private

    def filter_by_status(documents)
      return documents unless params[:status].present?

      filter_params[:status] = params[:status]
      documents.where(status: params[:status])
    end

    def filter_by_embedding_status(documents)
      return documents unless params[:embedding_status].present?

      filter_params[:embedding_status] = params[:embedding_status]
      documents.where(embedding_status: params[:embedding_status])
    end

    def filter_by_file_type(documents)
      return documents unless params[:file_type].present?

      filter_params[:file_type] = params[:file_type]
      documents.where(file_type: params[:file_type])
    end

    def filter_by_date_range(documents)
      documents = filter_date_from(documents)
      filter_date_to(documents)
    end

    def filter_date_from(documents)
      return documents unless params[:date_from].present?

      date_from = Date.parse(params[:date_from]).beginning_of_day
      filter_params[:date_from] = params[:date_from]
      documents.where("created_at >= ?", date_from)
    rescue ArgumentError
      documents
    end

    def filter_date_to(documents)
      return documents unless params[:date_to].present?

      date_to = Date.parse(params[:date_to]).end_of_day
      filter_params[:date_to] = params[:date_to]
      documents.where("created_at <= ?", date_to)
    rescue ArgumentError
      documents
    end

    def filter_by_search_term(documents)
      return documents unless params[:q].present?

      filter_params[:q] = params[:q]
      search(documents, params[:q])
    end

    def normalize_sort_field(field)
      VALID_SORT_FIELDS.include?(field) ? field : DEFAULT_SORT_FIELD
    end

    def normalize_sort_direction(direction)
      direction.to_s.downcase == 'asc' ? 'asc' : 'desc'
    end
  end
end
