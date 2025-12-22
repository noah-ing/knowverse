# frozen_string_literal: true

# Model Context Protocol (MCP) Controller
# Enables Claude Desktop and other MCP clients to query KnowVerse
#
# MCP Spec: https://modelcontextprotocol.io/
class McpController < ApplicationController
  # Skip CSRF for API endpoints
  skip_before_action :verify_authenticity_token
  before_action :authenticate_mcp_api_key!
  before_action :set_organization

  # GET /mcp/tools - List available tools
  def tools
    render json: {
      tools: [
        {
          name: "search_documents",
          description: "Search documents in the knowledge base using semantic search",
          inputSchema: {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "The search query"
              },
              limit: {
                type: "integer",
                description: "Maximum number of results (default: 5, max: 20)",
                default: 5
              }
            },
            required: ["query"]
          }
        },
        {
          name: "get_document",
          description: "Get the full content of a specific document by ID",
          inputSchema: {
            type: "object",
            properties: {
              document_id: {
                type: "integer",
                description: "The document ID"
              }
            },
            required: ["document_id"]
          }
        },
        {
          name: "ask_question",
          description: "Ask a question and get an AI-generated answer based on the knowledge base",
          inputSchema: {
            type: "object",
            properties: {
              question: {
                type: "string",
                description: "The question to answer"
              },
              max_sources: {
                type: "integer",
                description: "Maximum number of source documents to use (default: 5)",
                default: 5
              }
            },
            required: ["question"]
          }
        },
        {
          name: "list_documents",
          description: "List all documents in the knowledge base",
          inputSchema: {
            type: "object",
            properties: {
              limit: {
                type: "integer",
                description: "Maximum number of documents to return (default: 20)",
                default: 20
              },
              status: {
                type: "string",
                description: "Filter by status (pending, processing, processed, error)",
                enum: ["pending", "processing", "processed", "error"]
              }
            }
          }
        }
      ]
    }
  end

  # POST /mcp/execute - Execute a tool
  def execute
    tool_name = params[:name]
    arguments = params[:arguments]&.to_unsafe_h || {}

    result = Mcp::ToolExecutor.new(@organization).execute(tool_name, arguments)

    render json: {
      content: [
        {
          type: "text",
          text: result[:text]
        }
      ],
      isError: result[:error].present?,
      metadata: result[:metadata]
    }
  rescue Mcp::ToolExecutor::ToolNotFoundError => e
    render json: { error: e.message, isError: true }, status: :not_found
  rescue Mcp::ToolExecutor::ExecutionError => e
    render json: { error: e.message, isError: true }, status: :unprocessable_entity
  end

  # GET /mcp/resources - List available resources
  def resources
    documents = @organization.documents.processed.limit(100)

    render json: {
      resources: documents.map do |doc|
        {
          uri: "knowverse://documents/#{doc.id}",
          name: doc.title.presence || doc.filename,
          description: "#{doc.file_type.upcase} document, #{doc.word_count || 0} words",
          mimeType: doc.file&.content_type || "text/plain"
        }
      end
    }
  end

  # GET /mcp/resource/:uri - Get a specific resource
  def resource
    uri = params[:uri]

    # Parse knowverse://documents/:id
    if uri&.start_with?("knowverse://documents/")
      doc_id = uri.split("/").last.to_i
      document = @organization.documents.find_by(id: doc_id)

      if document
        render json: {
          contents: [
            {
              uri: uri,
              mimeType: "text/plain",
              text: document.content || "No content available"
            }
          ]
        }
      else
        render json: { error: "Document not found" }, status: :not_found
      end
    else
      render json: { error: "Invalid resource URI" }, status: :bad_request
    end
  end

  private

  def authenticate_mcp_api_key!
    api_key = request.headers["X-MCP-Key"] || request.headers["Authorization"]&.gsub(/^Bearer\s+/, "")

    if api_key.blank?
      render json: { error: "Missing API key. Include X-MCP-Key header." }, status: :unauthorized
      return
    end

    @organization = Organization.find_by_mcp_api_key(api_key)

    unless @organization
      render json: { error: "Invalid API key" }, status: :unauthorized
    end
  end

  def set_organization
    # Already set in authenticate_mcp_api_key!
  end
end
