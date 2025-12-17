# Temporary initializer to debug environment variables
# To be removed after debugging is complete

Rails.logger.info "======== DEBUGGING ENV VARIABLES ========"
Rails.logger.info "RESEND_API_KEY present?: #{ENV['RESEND_API_KEY'].present?}"
Rails.logger.info "RESEND_API_KEY first 5 chars: #{ENV['RESEND_API_KEY']&.first(5)}"
Rails.logger.info "Resend.api_key set?: #{Resend.api_key.present?}"
Rails.logger.info "Resend.api_key first 5 chars: #{Resend.api_key&.first(5)}"
Rails.logger.info "ActionMailer delivery method: #{ActionMailer::Base.delivery_method}"
Rails.logger.info "============================================="
