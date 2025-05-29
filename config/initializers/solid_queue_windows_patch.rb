# Windows compatibility patch for SolidQueue
# This file prevents SIGQUIT errors on Windows platforms by patching
# the Signal module and SolidQueue to handle Windows signal limitations

# Only apply this patch on Windows platforms
if Gem.win_platform?
  Rails.logger.info "Applying Windows-specific SolidQueue compatibility patch"

  # Create a comprehensive patch that intercepts any SIGQUIT usage
  module SolidQueueWindowsPatch
    # Patch for the Signal module itself
    module SignalPatch
      def trap(signal, command = nil, &block)
        # Skip SIGQUIT on Windows
        if signal.to_s.upcase == 'QUIT' || signal.to_s == 'SIGQUIT'
          Rails.logger.info "Windows compatibility: Ignoring SIGQUIT trap request"
          return 'SYSTEM_UNSUPPORTED_SIGNAL'
        end
        
        # Pass other signals to the original method
        super
      end
    end
  end

  # Apply the patch to the Signal module
  Signal.singleton_class.prepend(SolidQueueWindowsPatch::SignalPatch)
  
  # Patch SolidQueue to provide alternate shutdown mechanisms
  if defined?(SolidQueue)
    # Add a shutdown method that doesn't rely on SIGQUIT
    module SolidQueue
      class << self
        alias_method :original_shutdown, :shutdown if method_defined?(:shutdown)
        
        def shutdown
          Rails.logger.info "SolidQueue Windows-compatible shutdown initiated"
          # Call all active dispatchers to gracefully shutdown
          @dispatchers&.each { |dispatcher| dispatcher.stop }
          # Call all active supervisors to shutdown
          @supervisors&.each { |supervisor| supervisor.shutdown }
          # Call original if it exists
          original_shutdown if respond_to?(:original_shutdown)
        rescue => e
          Rails.logger.error "Error during Windows-compatible SolidQueue shutdown: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end
    end
    
    # Patch the ProcessDispatcher class specifically
    if defined?(SolidQueue::Dispatcher)
      module SolidQueueDispatcherPatch
        def initialize(queues: '*', polling_interval: nil, heartbeat_interval: nil, max_threads: nil)
          # Store original initialization options
          @queues = queues
          @polling_interval = polling_interval
          @heartbeat_interval = heartbeat_interval || 5.seconds
          @max_threads = max_threads || 5
          @stopping = false
          @thread_pool = Concurrent::ThreadPoolExecutor.new(
            min_threads: 1,
            max_threads: @max_threads,
            max_queue: 0,
            fallback_policy: :caller_runs
          )
        end
        
        # Replace the signal trapping logic with a simpler stop method
        def stop
          @stopping = true
          @thread_pool.shutdown
          @thread_pool.wait_for_termination(10) # Wait up to 10 seconds for clean shutdown
        rescue => e
          Rails.logger.error "Error during Windows-compatible dispatcher shutdown: #{e.message}"
        end
      end
      
      # Apply the dispatcher patch
      SolidQueue::Dispatcher.prepend(SolidQueueDispatcherPatch)
    end
  end
  
  Rails.logger.info "Windows-specific SolidQueue compatibility patch applied successfully"
end
