# WebAssembly Search Initializer
# This initializer sets up the WebAssembly search service

Rails.application.config.after_initialize do
  begin
    # Initialize the WebAssembly search service
    Rails.logger.info "Initializing WebAssembly Search Service..."
    
    # Get the service instance (singleton)
    service = Wasm::WebassemblySearchService.instance
    
    # Log status
    if service.status == Wasm::WebassemblySearchService::STATUS_READY
      Rails.logger.info "WebAssembly Search Service ready."
    elsif service.status == Wasm::WebassemblySearchService::STATUS_ERROR
      Rails.logger.error "WebAssembly Search Service initialization failed: #{service.error_message}"
    else
      Rails.logger.info "WebAssembly Search Service initializing..."
    end
  rescue => e
    Rails.logger.error "Failed to initialize WebAssembly Search Service: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end
