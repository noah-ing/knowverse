# frozen_string_literal: true

module Rag
  # Service for handling agent-based SSE streaming in RAG
  class AgentStreamingService
    def initialize(organization, conversation, agent_mode)
      @organization = organization
      @conversation = conversation
      @agent_mode = agent_mode
      @complete_response = ""
      @sources = []
      @agent_trace = []
    end

    attr_reader :complete_response, :sources, :agent_trace

    # Process an agent streaming event and return formatted SSE data
    def process_event(event)
      event_type = event[:type].to_s
      event_data = event[:data].is_a?(Hash) ? event[:data].dup : {}
      event_data["type"] = event_type
      event_data["conversation_id"] = @conversation.id

      case event[:type]
      when :mode_selected, :phase, :quality_check, :clarify, :warning, :error
        format_sse(event_data)
      when :thought
        @agent_trace << { type: "thought", content: event_data["thought"] }
        format_sse(event_data)
      when :action
        @agent_trace << { type: "action", tool: event_data["tool"], input: event_data["input"] }
        format_sse(event_data)
      when :observation
        @agent_trace << { type: "observation", result: event_data["result"] }
        format_sse(event_data)
      when :plan
        @agent_trace << { type: "plan", steps: event_data["steps"] }
        format_sse(event_data)
      when :step_complete
        @agent_trace << { type: "step_complete", step: event_data["step"] }
        format_sse(event_data)
      when :researching
        @agent_trace << { type: "researching", question: event_data["question"] }
        format_sse(event_data)
      when :context
        @sources = event_data["documents"] || event_data["sources"] || []
        format_sse(event_data)
      when :token
        process_token(event_data)
      when :final_answer
        process_final_answer(event_data)
      when :complete
        process_complete(event_data)
      else
        format_sse(event_data)
      end
    end

    private

    def process_token(event_data)
      token_content = event_data["content"] || event_data["token"] || ""
      @complete_response += token_content
      format_sse(event_data)
    end

    def process_final_answer(event_data)
      @complete_response = event_data["answer"] || @complete_response
      @sources = event_data["sources"] || @sources

      assistant_message = @conversation.add_assistant_message(
        @complete_response,
        {
          sources: @sources,
          agent_mode: @agent_mode,
          agent_trace: @agent_trace.present? ? @agent_trace : nil,
          confidence: event_data["confidence"]
        }
      )

      event_data["message_id"] = assistant_message.id
      format_sse(event_data)
    end

    def process_complete(event_data)
      event_data["message_id"] ||= @conversation.conversation_messages.last&.id
      format_sse(event_data)
    end

    def format_sse(data)
      "data: #{JSON.generate(data)}\n\n"
    end
  end
end
