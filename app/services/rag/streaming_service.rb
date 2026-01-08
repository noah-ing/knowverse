# frozen_string_literal: true

module Rag
  # Service for handling SSE streaming operations in RAG
  class StreamingService
    def initialize(organization, conversation)
      @organization = organization
      @conversation = conversation
      @complete_response = ""
      @sources = []
      @response_metadata = {}
    end

    attr_reader :complete_response, :sources, :response_metadata

    # Process a streaming event and return formatted SSE data
    def process_event(event)
      case event[:type]
      when :metadata
        process_metadata(event)
      when :token
        process_token(event)
      when :sources
        process_sources(event)
      when :complete
        process_complete(event)
      when :error
        process_error(event)
      when :fallback, :metric, :context
        process_generic(event)
      else
        process_generic(event)
      end
    end

    private

    def process_metadata(event)
      @response_metadata = event[:data]
      data = event[:data].merge("type" => "metadata", "conversation_id" => @conversation.id)
      format_sse(data)
    end

    def process_token(event)
      token_content = event[:data]["content"] || event[:data][:content] ||
                      event[:data]["token"] || event[:data][:token] || ""
      token_index = event[:data]["index"] || event[:data][:index] ||
                    event[:data]["id"] || event[:data][:id]

      @complete_response += token_content

      # Store token in StreamingElement if conversation exists
      if @conversation
        idx = token_index || @conversation.streaming_elements.count
        has_source = event[:data]["has_source"] || event[:data][:has_source] || false

        @conversation.add_streaming_token(
          token_content,
          idx,
          false,
          has_source ? @sources : nil
        )
      end

      data = event[:data].is_a?(Hash) ? event[:data].merge("type" => "token") : { "type" => "token", "content" => token_content }
      format_sse(data)
    end

    def process_sources(event)
      @sources = event[:data]["sources"] || event[:data][:sources] || []
      data = event[:data].is_a?(Hash) ? event[:data].merge("type" => "sources") : { "type" => "sources", "sources" => @sources }
      format_sse(data)
    end

    def process_complete(event)
      @sources = event[:data]["sources"] || event[:data][:sources] || []

      # Mark streaming as complete
      if @conversation && @conversation.streaming_elements.any?
        StreamingElement.mark_complete(@conversation.id)
      end

      metrics = event[:data]["metrics"] || event[:data][:metrics]
      provider = event[:data]["provider"] || event[:data][:provider]

      # Finalize streaming or create message
      assistant_message = finalize_message(metrics, provider)

      event_data = (event[:data].is_a?(Hash) ? event[:data] : {}).merge(
        "type" => "complete",
        "conversation_id" => @conversation.id,
        "message_id" => assistant_message.id
      )
      format_sse(event_data)
    end

    def process_error(event)
      data = event[:data].is_a?(Hash) ? event[:data].merge("type" => "error") : { "type" => "error", "error" => event[:data].to_s }
      format_sse(data)
    end

    def process_generic(event)
      event_type = event[:type].to_s
      data = if event[:data].is_a?(Hash)
               event[:data].merge("type" => event_type, "conversation_id" => @conversation.id)
             else
               { "type" => event_type, "conversation_id" => @conversation.id }
             end
      format_sse(data)
    end

    def finalize_message(metrics, provider)
      if @conversation.streaming_elements.any?
        @conversation.finalize_streaming({
          sources: @sources,
          metrics: metrics,
          provider: provider
        })
      else
        @conversation.add_assistant_message(
          @complete_response,
          {
            sources: @sources,
            metrics: metrics,
            provider: provider
          }
        )
      end
    end

    def format_sse(data)
      "data: #{JSON.generate(data)}\n\n"
    end
  end
end
