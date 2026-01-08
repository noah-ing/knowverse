# frozen_string_literal: true

module Rag
  # Service for RAG query operations - extracts options parsing from controller
  class QueryService
    def initialize(organization, current_user)
      @organization = organization
      @current_user = current_user
    end

    # Parse retrieval options from params
    def parse_retrieval_options(params)
      {
        max_documents: params[:max_documents].presence&.to_i || 5,
        min_similarity: params[:min_similarity].presence&.to_f || 0.01,
        strategy: params[:strategy].presence || "auto"
      }
    end

    # Parse generation options from params
    def parse_generation_options(params)
      {
        temperature: params[:temperature].presence&.to_f || 0.7,
        max_tokens: params[:max_tokens].presence&.to_i || 500,
        model: params[:model].presence
      }
    end

    # Parse agent options from params
    def parse_agent_options(params)
      {
        mode: params[:mode].presence || "auto",
        max_iterations: params[:max_iterations].presence&.to_i || 10,
        provider: params[:provider].presence,
        include_trace: params[:include_trace].present? ? params[:include_trace] == "true" : true,
        temperature: params[:temperature].presence&.to_f || 0.7,
        max_tokens: params[:max_tokens].presence&.to_i || 1000
      }
    end

    # Build streaming options hash for haystack client
    def build_streaming_options(provider:, retrieval_options:, generation_options:, conversation_id:)
      {
        provider: provider,
        retrieval_strategy: retrieval_options[:strategy],
        max_documents: retrieval_options[:max_documents],
        similarity_threshold: retrieval_options[:min_similarity],
        temperature: generation_options[:temperature],
        max_tokens: generation_options[:max_tokens],
        model: generation_options[:model],
        system_prompt: generation_options[:system_prompt],
        conversation_id: conversation_id
      }
    end

    # Build agent streaming options hash
    def build_agent_options(agent_options:, conversation_id:)
      {
        mode: agent_options[:mode],
        max_iterations: agent_options[:max_iterations],
        provider: agent_options[:provider],
        temperature: agent_options[:temperature],
        max_tokens: agent_options[:max_tokens],
        include_trace: agent_options[:include_trace],
        conversation_id: conversation_id
      }
    end

    # Build system prompt with template or defaults
    def build_system_prompt(template:, template_service:, template_variables:, query:)
      if template.present?
        template_service.render_template(template, template_variables.merge({
          query: query,
          organization: @organization.name,
          user: @current_user.email
        }))
      else
        default_system_prompt
      end
    end

    # Default RAG system prompt
    def default_system_prompt
      <<~PROMPT
        You are a helpful AI assistant for #{@organization.name}'s knowledge base. Your role is to:

        1. Answer questions based on the provided document context
        2. Cite specific sources when making claims
        3. Be clear when information is not available in the documents
        4. Provide concise, accurate responses

        When responding:
        - Base your answers on the retrieved document chunks
        - If the context doesn't contain relevant information, say so clearly
        - Use professional, clear language
        - Format responses with markdown when helpful (lists, code blocks, etc.)
      PROMPT
    end

    # Default retrieval options for index page
    def default_retrieval_options
      {
        max_documents: 5,
        min_similarity: 0.01,
        strategy: "auto"
      }
    end

    # Default generation options for index page
    def default_generation_options
      {
        temperature: 0.7,
        max_tokens: 500
      }
    end
  end
end
