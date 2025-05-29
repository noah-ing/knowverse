# frozen_string_literal: true

module Search
  # Controller responsible for streaming search results from the 
  # distributed vector search backend. It implements Server-Sent Events
  # for streaming results and manages the lifecycle of search components.
  class StreamingController < ApplicationController
    include ActionController::Live
    
    before_action :set_response_headers, only: [:stream]
    before_action :load_search_components, only: [:stream, :initialize_components]
    
    # GET /search/streaming
    # Streams search results using Server-Sent Events
    def stream
      # Extract search parameters
      query = params[:query]
      confidence_threshold = (params[:confidence] || 0.7).to_f
      result_limit = (params[:limit] || 20).to_i
      
      unless query.present?
        stream_error("Query parameter is required")
        return
      end
      
      # Stream results
      begin
        stream_results(query, confidence_threshold, result_limit)
      rescue => e
        Rails.logger.error "Error streaming search results: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        stream_error("An error occurred while processing your search: #{e.message}")
      ensure
        # Always close the stream
        response.stream.close
      end
    end
    
    # GET /search/components/initialize
    # Initialize frontend components with necessary data
    def initialize_components
      domain_options = current_organization&.domain_embedding_models || DomainEmbeddingModel.where(is_default: true)
      current_domain = @domain_model
      
      # Prepare component initialization data
      component_data = {
        components: {
          search_form: true,
          search_results: true,
          streaming_results: true,
          domain_selector: domain_options.exists?
        },
        domain_options: domain_options.map { |model| { id: model.id, name: model.name } },
        current_domain: current_domain ? { id: current_domain.id, name: current_domain.name } : nil,
        prefetch_data: {
          enabled: @bridge&.prefetch_enabled || false
        }
      }
      
      render json: component_data
    end
    
    private
    
    # Set up response headers for SSE streaming
    def set_response_headers
      response.headers['Content-Type'] = 'text/event-stream'
      response.headers['Cache-Control'] = 'no-cache'
      response.headers['Connection'] = 'keep-alive'
      response.headers['X-Accel-Buffering'] = 'no' # For Nginx
    end
    
    # Initialize search components and bridge
    def load_search_components
      # Get the domain model from params or use default
      domain_id = params[:domain_id].presence
      @domain_model = if domain_id
                        current_organization&.domain_embedding_models&.find_by(id: domain_id) ||
                          DomainEmbeddingModel.find_by(id: domain_id)
                      else
                        current_organization&.domain_embedding_models&.where(is_default: true)&.first ||
                          DomainEmbeddingModel.where(is_default: true).first
                      end
      
      # Create the component bridge
      @bridge = VectorSearch::SearchComponentManager.instance.bridge_for(
        domain_model: @domain_model,
        organization: current_organization,
        user: current_user
      )
    end
    
    # Stream search results to the client
    def stream_results(query, confidence_threshold, result_limit)
      # Start the stream with an initial status
      stream_event('status', { message: 'Searching...' })
      
      # Add metadata about the search
      stream_event('metadata', {
        domain: @domain_model&.name || 'General',
        model_used: @domain_model&.embedding_model_name || 'Default',
        dimensions: @domain_model&.embedding_dimensions,
        timestamp: Time.current.iso8601
      })
      
      # Record search start time
      start_time = Time.current
      result_count = 0
      
      # Set up streaming options
      options = {
        confidence: confidence_threshold,
        limit: result_limit,
        format: 'json',
        cancelled: false # Flag that can be set by client
      }
      
      # Stream search results
      @bridge.stream_search(query, ->(result) {
        # Prepare result for streaming
        stream_result = {
          id: result[:id] || SecureRandom.hex(4),
          title: result[:title] || "Result #{result_count + 1}",
          text: result[:text] || result[:content] || "",
          confidence: result[:confidence] || 0.0,
          metadata: result[:metadata] || {}
        }
        
        # Send as an individual result or in batches
        stream_event('message', { results: [stream_result] })
        
        # Increment result counter
        result_count += 1
        
        # Check if we should continue streaming
        if result_count >= result_limit
          options[:cancelled] = true
        end
      }, options)
      
      # Calculate elapsed time
      elapsed_ms = ((Time.current - start_time) * 1000).to_i
      
      # Send completion event
      stream_event('search_complete', {
        summary: {
          result_count: result_count,
          time_ms: elapsed_ms,
          query: query,
          model_name: @domain_model&.name || 'Default model'
        }
      })
      
      # Record search statistics
      record_search_stats(query, result_count, elapsed_ms, @domain_model)
    end
    
    # Send a server-sent event
    def stream_event(event_name, data)
      response.stream.write("event: #{event_name}\n")
      response.stream.write("data: #{data.to_json}\n\n")
    rescue IOError, ActionController::Live::ClientDisconnected
      # Client disconnected, stop streaming
      options[:cancelled] = true if defined?(options)
    end
    
    # Stream an error message
    def stream_error(message)
      stream_event('error', { message: message })
    rescue IOError, ActionController::Live::ClientDisconnected
      # Ignore client disconnection errors
    ensure
      response.stream.close
    end
    
    # Record search statistics for analytics
    def record_search_stats(query, result_count, elapsed_ms, domain_model)
      return unless defined?(SearchQuery)
      
      begin
        SearchQuery.create(
          query_text: query,
          user: current_user,
          organization: current_organization,
          domain_embedding_model: domain_model,
          result_count: result_count,
          response_time_ms: elapsed_ms,
          successful: result_count.positive?
        )
      rescue => e
        Rails.logger.error "Error recording search stats: #{e.message}"
      end
    end
  end
end
