# frozen_string_literal: true

class RagController < ApplicationController
  include ActionController::Live

  rescue_from(UncaughtThrowError) { |e| e.message.include?(':warden') ? redirect_to(new_user_session_path, alert: 'Please sign in to continue.') : raise(e) }

  before_action :authenticate_user!
  before_action :set_organization

  def index
    providers_response = haystack_client.list_llm_providers
    @providers = providers_response.success? ? providers_response.data : []
    @retrieval_options = query_service.default_retrieval_options
    @generation_options = query_service.default_generation_options
    @templates = conversation_service.load_templates
    @default_template = conversation_service.default_template(@templates)
    @selected_template = conversation_service.find_template(params[:template_id])
    @template = @selected_template || @default_template
    @template_variables = conversation_service.extract_template_variables(@template)
    @conversation_id = params[:conversation_id]
    @messages = conversation_service.load_conversation_messages(@conversation_id)
  end

  def stream
    setup_sse_headers
    @query = params[:query]
    return send_error("Question cannot be blank") if @query.blank?

    retrieval_opts = query_service.parse_retrieval_options(params)
    generation_opts = query_service.parse_generation_options(params)
    generation_opts[:system_prompt] = build_system_prompt(params)
    conversation = conversation_service.find_or_create_conversation(params[:conversation_id], find_rag_template&.id)
    conversation.add_user_message(@query)

    svc = Rag::StreamingService.new(@organization, conversation)
    opts = query_service.build_streaming_options(provider: params[:provider].presence, retrieval_options: retrieval_opts, generation_options: generation_opts, conversation_id: conversation.id)
    stream_response(:generate_answer_stream, opts, svc)
  end

  def agent_stream
    setup_sse_headers
    @query = params[:query]
    return send_error("Question cannot be blank") if @query.blank?

    agent_opts = query_service.parse_agent_options(params)
    conversation = conversation_service.find_or_create_conversation(params[:conversation_id])
    conversation.add_user_message(@query)

    svc = Rag::AgentStreamingService.new(@organization, conversation, agent_opts[:mode])
    opts = query_service.build_agent_options(agent_options: agent_opts, conversation_id: conversation.id)
    stream_response(:generate_agent_stream, opts, svc)
  end

  def agent_info
    modes_response = haystack_client.list_agent_modes
    tools_response = haystack_client.list_agent_tools
    render json: { modes: modes_response.success? ? modes_response.data : [], tools: tools_response.success? ? tools_response.data : [] }
  end

  def conversation
    return render(json: { error: "Conversation ID is required" }, status: :bad_request) if params[:conversation_id].blank?
    conv = ConversationSession.find_by(id: params[:conversation_id], organization_id: @organization.id, user_id: current_user.id)
    return render(json: { error: "Conversation not found" }, status: :not_found) if conv.nil?
    messages = conv.conversation_messages.order(created_at: :asc)
    render json: { conversation: { id: conv.id, title: conv.title, created_at: conv.created_at, updated_at: conv.updated_at, last_message_at: conv.last_message_at }, messages: messages.map { |m| { id: m.id, role: m.role, content: m.content, created_at: m.created_at, metadata: m.metadata } } }
  end

  private

  def set_organization
    @organization = params[:organization_id].present? ? Organization.find(params[:organization_id]) : current_user.organizations.first
    redirect_to(organizations_path, alert: 'Please create or join an organization first.') if @organization.nil?
  end

  def setup_sse_headers
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["Connection"] = "keep-alive"
  end

  def send_error(msg)
    response.stream.write("event: error\ndata: #{JSON.generate({ error: msg })}\n\n")
    response.stream.close
  end

  def stream_response(method, opts, svc)
    haystack_client.send(method, @query, @organization.id, opts) { |event| response.stream.write(svc.process_event(event)) }
  rescue => e
    Rails.logger.error("Streaming error: #{e.message}\n#{e.backtrace.join("\n")}")
    response.stream.write("data: #{JSON.generate({ type: 'error', error: e.message })}\n\n")
  ensure
    response.stream.close
  end

  def build_system_prompt(params)
    template = find_rag_template
    vars = conversation_service.parse_template_variables(params)
    return query_service.build_system_prompt(template: template, template_service: TemplateService.new(@organization), template_variables: vars, query: @query) if template.present?
    params[:system_prompt].presence || query_service.default_system_prompt
  end

  def find_rag_template
    TemplateService.new(@organization).find_template('rag', params[:template_id])
  end

  def haystack_client = @haystack_client ||= HaystackClient.new
  def query_service = @query_service ||= Rag::QueryService.new(@organization, current_user)
  def conversation_service = @conversation_service ||= Rag::ConversationService.new(@organization, current_user)
end
