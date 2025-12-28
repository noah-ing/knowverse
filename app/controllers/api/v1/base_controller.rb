# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_api_request!

      rescue_from ActiveRecord::RecordNotFound do |e|
        render json: { error: 'Not found', message: e.message }, status: :not_found
      end

      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: { error: 'Validation failed', messages: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      rescue_from ActionController::ParameterMissing do |e|
        render json: { error: 'Missing parameter', message: e.message }, status: :bad_request
      end

      private

      def authenticate_api_request!
        # Support both session auth (for logged-in users) and API key auth
        return if current_user.present?

        api_key = request.headers['X-API-Key'] || params[:api_key]
        if api_key.present?
          @current_organization = Organization.find_by(api_key: api_key)
          if @current_organization
            @current_user = @current_organization.owner || @current_organization.users.first
            sign_in(@current_user, store: false) if @current_user
            return
          end
        end

        render json: { error: 'Unauthorized', message: 'Invalid or missing API key' }, status: :unauthorized
      end
    end
  end
end
