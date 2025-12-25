class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def stripe
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = Rails.configuration.stripe[:signing_secret]

    begin
      event = Stripe::Webhook.construct_event(
        payload, sig_header, endpoint_secret
      )
    rescue JSON::ParserError => e
      Rails.logger.error("Stripe webhook parse error: #{e.message}")
      render json: { error: e.message }, status: :bad_request
      return
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error("Stripe webhook signature error: #{e.message}")
      render json: { error: e.message }, status: :bad_request
      return
    end

    # Process with organization-level billing handler
    begin
      handler = Billing::WebhookHandler.new(event)
      result = handler.process!

      Rails.logger.info("Stripe webhook processed: #{event.type} - #{result[:status]}")
      render json: { status: 'success', result: result }
    rescue Billing::WebhookHandler::WebhookError => e
      Rails.logger.error("Stripe webhook processing error: #{e.message}")
      render json: { error: e.message }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error("Stripe webhook unexpected error: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
      render json: { error: 'Internal error' }, status: :internal_server_error
    end
  end
end
