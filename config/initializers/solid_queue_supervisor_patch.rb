# Cross-platform compatibility patch for SolidQueue Supervisor
# This properly handles signal differences between Windows and Unix platforms

require 'solid_queue'

module SolidQueue
  class Supervisor
    # Define more robust shutdown behavior for both Windows and Unix
    def shutdown
      Rails.logger.info "SolidQueue Supervisor: Shutting down workers"
      @poll_thread&.exit
      @workers&.each { |worker| worker.shutdown }
    rescue => e
      Rails.logger.error "SolidQueue Supervisor: Error during shutdown: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    ensure
      Rails.logger.info "SolidQueue Supervisor: Shutdown complete"
    end
  end
end

# Register platform-specific signal handlers
at_exit do
  Rails.logger.info "SolidQueue Supervisor: Shutdown triggered via at_exit hook"
  SolidQueue.stop if defined?(SolidQueue.stop)
end

if Gem.win_platform?
  Rails.logger.info "SolidQueue Supervisor: Installing Windows-compatible signal handlers"
  # Only trap signals available on Windows
  trap("INT") { exit(0) }
  trap("TERM") { exit(0) }
  Rails.logger.info "SolidQueue Supervisor: Windows signal handlers installed"
else
  # Unix systems can handle more signals
  Rails.logger.info "SolidQueue Supervisor: Installing Unix signal handlers"
  trap("INT") { exit(0) }
  trap("TERM") { exit(0) }
  begin
    trap("QUIT") { exit(0) }
    Rails.logger.info "SolidQueue Supervisor: Unix QUIT signal handler installed"
  rescue ArgumentError => e
    Rails.logger.warn "SolidQueue Supervisor: Could not install QUIT signal handler: #{e.message}"
  end
end

Rails.logger.info "SolidQueue cross-platform compatibility patch loaded"
