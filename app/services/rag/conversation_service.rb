# frozen_string_literal: true

module Rag
  # Service for managing RAG conversations and templates
  class ConversationService
    def initialize(organization, current_user)
      @organization = organization
      @current_user = current_user
    end

    # Find or create a conversation based on ID
    def find_or_create_conversation(conversation_id, template_id = nil)
      if conversation_id.present?
        conversation = find_conversation(conversation_id)

        if conversation.present? && template_id.present?
          update_template_association(conversation, template_id)
        end

        return conversation if conversation.present?
      end

      create_new_conversation(template_id)
    end

    # Load conversation messages for display
    def load_conversation_messages(conversation_id)
      return [] if conversation_id.blank?

      conversation = find_conversation(conversation_id)
      return [] unless conversation.present?

      conversation.conversation_messages.order(created_at: :asc)
    end

    # Get templates for RAG interface
    def load_templates
      @organization.organization_templates.where(template_type: 'rag').order(name: :asc)
    end

    # Get default template
    def default_template(templates)
      templates.find_by(is_default: true)
    end

    # Find template by ID
    def find_template(template_id)
      return nil if template_id.blank?
      @organization.organization_templates.find_by(id: template_id)
    end

    # Extract template variables
    def extract_template_variables(template)
      return {} unless template.present?
      TemplateService.new(@organization).extract_variables(template)
    end

    # Parse template variables from params
    def parse_template_variables(params)
      return {} unless params[:template_variables].present? && params[:template_variables].is_a?(Hash)
      params[:template_variables]
    end

    # Track template usage after completion
    def track_template_usage(template, conversation, start_time, metrics)
      return unless template.present?

      response_time = (Time.current - start_time).to_f
      token_count = metrics['token_count'] if metrics.present?

      template_service = TemplateService.new(@organization)
      template_service.track_usage(
        template,
        @current_user,
        conversation,
        {
          response_time: response_time,
          token_count: token_count,
          metrics: metrics
        }
      )
    end

    private

    def find_conversation(conversation_id)
      ConversationSession.find_by(
        id: conversation_id,
        organization_id: @organization.id,
        user_id: @current_user.id
      )
    end

    def update_template_association(conversation, template_id)
      current_template = conversation.metadata&.dig('template_id')
      return if current_template == template_id

      conversation.update(metadata: (conversation.metadata || {}).merge('template_id' => template_id))
    end

    def create_new_conversation(template_id)
      ConversationSession.create!(
        organization: @organization,
        user: @current_user,
        title: "Q&A #{Time.current.strftime('%Y-%m-%d %H:%M')}",
        metadata: template_id.present? ? { 'template_id' => template_id } : {},
        last_message_at: Time.current
      )
    end
  end
end
