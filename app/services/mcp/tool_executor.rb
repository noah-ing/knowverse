# frozen_string_literal: true

module Mcp
  # Executes MCP tool calls against the KnowVerse knowledge base
  class ToolExecutor
    class ToolNotFoundError < StandardError; end
    class ExecutionError < StandardError; end

    AVAILABLE_TOOLS = %w[search_documents get_document ask_question list_documents].freeze

    def initialize(organization)
      @organization = organization
    end

    def execute(tool_name, arguments)
      unless AVAILABLE_TOOLS.include?(tool_name)
        raise ToolNotFoundError, "Unknown tool: #{tool_name}"
      end

      send("execute_#{tool_name}", arguments.deep_symbolize_keys)
    rescue ActiveRecord::RecordNotFound => e
      { text: "Not found: #{e.message}", error: true, metadata: {} }
    rescue => e
      Rails.logger.error("[MCP] Tool execution error: #{e.message}")
      raise ExecutionError, e.message
    end

    private

    def execute_search_documents(args)
      query = args[:query]
      limit = [args[:limit] || 5, 20].min

      raise ExecutionError, "Query is required" if query.blank?

      # Use the unified search service
      results = perform_search(query, limit)

      if results.empty?
        return {
          text: "No documents found matching your query.",
          metadata: { query: query, count: 0 }
        }
      end

      text = "Found #{results.size} document(s):\n\n"
      results.each_with_index do |result, i|
        text += "#{i + 1}. **#{result[:title]}** (score: #{result[:score].round(3)})\n"
        text += "   #{result[:snippet]}\n\n"
      end

      {
        text: text,
        metadata: {
          query: query,
          count: results.size,
          results: results
        }
      }
    end

    def execute_get_document(args)
      doc_id = args[:document_id]
      raise ExecutionError, "document_id is required" if doc_id.blank?

      document = @organization.documents.find(doc_id)

      {
        text: format_document(document),
        metadata: {
          id: document.id,
          title: document.title,
          file_type: document.file_type,
          word_count: document.word_count,
          status: document.status
        }
      }
    end

    def execute_ask_question(args)
      question = args[:question]
      max_sources = [args[:max_sources] || 5, 10].min

      raise ExecutionError, "Question is required" if question.blank?

      # Call the Haystack RAG service
      answer = perform_rag_query(question, max_sources)

      {
        text: answer[:text],
        metadata: {
          question: question,
          sources: answer[:sources],
          provider: answer[:provider]
        }
      }
    end

    def execute_list_documents(args)
      limit = [args[:limit] || 20, 100].min
      status = args[:status]

      scope = @organization.documents.order(created_at: :desc)
      scope = scope.where(status: status) if status.present?
      documents = scope.limit(limit)

      if documents.empty?
        return {
          text: "No documents found.",
          metadata: { count: 0 }
        }
      end

      text = "Documents (#{documents.size}):\n\n"
      documents.each do |doc|
        status_emoji = case doc.status
                       when "processed" then "✅"
                       when "processing" then "⏳"
                       when "pending" then "🔄"
                       when "error" then "❌"
                       else "❓"
                       end
        text += "#{status_emoji} [#{doc.id}] #{doc.title} (#{doc.file_type})\n"
      end

      {
        text: text,
        metadata: {
          count: documents.size,
          documents: documents.map { |d| { id: d.id, title: d.title, status: d.status } }
        }
      }
    end

    def perform_search(query, limit)
      # Try to use the search service if available
      begin
        service = Search::UnifiedSearchService.new
        results = service.search(query, @organization.id, mode: :semantic, limit: limit)

        results.map do |result|
          # Results use string keys from the service
          {
            id: result["document_id"] || result["id"],
            title: result["title"],
            score: result["score"] || 0,
            snippet: truncate_text(result["snippet"] || result["content"], 200)
          }
        end
      rescue => e
        Rails.logger.warn("[MCP] Search service error, falling back to basic search: #{e.message}")
        # Fallback to basic full-text search
        # INJ-002 fix: Use sanitize_sql_like to prevent SQL injection in ILIKE queries
        sanitized_query = Document.sanitize_sql_like(query)
        @organization.documents.processed
          .where("title ILIKE ? OR content ILIKE ?", "%#{sanitized_query}%", "%#{sanitized_query}%")
          .limit(limit)
          .map do |doc|
            {
              id: doc.id,
              title: doc.title,
              score: 0.5,
              snippet: truncate_text(doc.content, 200)
            }
          end
      end
    end

    def perform_rag_query(question, max_sources)
      begin
        client = HaystackClient.new
        response = client.generate_answer(
          question,
          @organization.id,
          max_documents: max_sources
        )

        {
          text: response[:answer] || response[:text] || "No answer generated.",
          sources: response[:sources] || [],
          provider: response[:provider] || "unknown"
        }
      rescue => e
        Rails.logger.error("[MCP] RAG query error: #{e.message}")
        {
          text: "Unable to generate answer: #{e.message}",
          sources: [],
          provider: "error"
        }
      end
    end

    def format_document(document)
      text = "# #{document.title}\n\n"
      text += "**Type:** #{document.file_type}\n"
      text += "**Status:** #{document.status}\n"
      text += "**Words:** #{document.word_count || 'Unknown'}\n"
      text += "**Created:** #{document.created_at.strftime('%Y-%m-%d %H:%M')}\n\n"
      text += "---\n\n"
      text += document.content || "No content available."
      text
    end

    def truncate_text(text, length)
      return "" if text.blank?
      text.length > length ? "#{text[0...length]}..." : text
    end
  end
end
