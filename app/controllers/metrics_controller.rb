# frozen_string_literal: true

# Prometheus metrics endpoint for monitoring
# Access: Protected by IP whitelist in production
class MetricsController < ApplicationController
  skip_before_action :authenticate_user!, if: -> { defined?(authenticate_user!) }
  before_action :verify_metrics_access

  def index
    render plain: Infrastructure::MetricsExporter.instance.export,
           content_type: 'text/plain; charset=utf-8'
  end

  private

  def verify_metrics_access
    # In production, restrict to internal IPs / monitoring systems
    return if Rails.env.development? || Rails.env.test?

    allowed_ips = ENV.fetch('METRICS_ALLOWED_IPS', '127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16').split(',')

    unless allowed_ip?(request.remote_ip, allowed_ips)
      head :forbidden
    end
  end

  def allowed_ip?(ip, allowed_ranges)
    require 'ipaddr'
    allowed_ranges.any? do |range|
      IPAddr.new(range.strip).include?(ip)
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
