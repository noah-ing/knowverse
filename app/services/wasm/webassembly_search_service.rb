require 'singleton'

module Wasm
  class WebassemblySearchService
    include Singleton
    
    # Configuration constants for HNSW
    DEFAULT_CONFIG = {
      m: 16,                     # Maximum number of connections per node (higher = better recall, more memory)
      ef_construction: 200,      # Search scope during construction (higher = better recall, slower construction)
      ef_search: 50,             # Search scope during query (higher = better recall, slower search)
      max_elements: 1_000_000,   # Maximum elements in the index
      ml: 1.0,                   # Level multiplier for random level generation (leave as 1.0 for standard HNSW)
      memory_quota_mb: 2048,     # Memory quota for HNSW indexes (2GB by default)
      partition_size: 50_000,    # Default partition size (documents per partition)
    }.freeze
    
    # Status indicators
    STATUS_LOADING = 'loading'
    STATUS_READY = 'ready'
    STATUS_ERROR = 'error'
    
    attr_reader :status, :error_message, :config
    
    def initialize
      @status = STATUS_LOADING
      @error_message = nil
      @config = DEFAULT_CONFIG.dup
      @index_stores = {}  # Organization-scoped HNSW indexes
      @metrics = {
        insert_time: [],
        search_time: [],
        memory_usage: []
      }
      
      load_config
    end
    
    # Initialize with custom configuration
    def load_config
      begin
        # In production, we'd load configuration from environment, database, etc.
        # For now, use default config
        
        # Mark as ready
        @status = STATUS_READY
      rescue => e
        @status = STATUS_ERROR
        @error_message = "Failed to initialize WebassemblySearchService: #{e.message}"
        Rails.logger.error(@error_message)
        Rails.logger.error(e.backtrace.join("\n"))
      end
    end
    
    # Get or create HNSW index store for an organization
    def for_organization(organization_id)
      @index_stores[organization_id] ||= HnswIndexStore.new(organization_id, @config)
    end
    
    # Format a vector for use with HNSW (normalizing, etc.)
    def format_vector(vector)
      # For now, just normalize the vector
      # In production, this would call the WASM module's normalize function
      normalize(vector)
    end
    
    # Search for nearest neighbors using HNSW
    def search(query_vector, organization_id, options = {})
      return [] if @status != STATUS_READY
      
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      
      begin
        # Normalize query vector
        normalized_query = format_vector(query_vector)
        
        # Get index for this organization
        index = for_organization(organization_id)
        
        # Perform search
        k = options[:limit] || 10
        results = index.search(normalized_query, k)
        
        # Record metrics
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration_ms = (end_time - start_time) * 1000
        record_operation('search', duration_ms, index.memory_usage)
        
        results
      rescue => e
        Rails.logger.error("HNSW search error: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        []
      end
    end
    
    # Add a vector to the HNSW index
    def insert(vector, document_id, organization_id)
      return nil if @status != STATUS_READY
      
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      
      begin
        # Normalize vector
        normalized_vector = format_vector(vector)
        
        # Get index for this organization
        index = for_organization(organization_id)
        
        # Insert into index
        reference = index.insert(normalized_vector, document_id)
        
        # Record metrics
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration_ms = (end_time - start_time) * 1000
        record_operation('insert', duration_ms, index.memory_usage)
        
        reference
      rescue => e
        Rails.logger.error("HNSW insert error: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        nil
      end
    end
    
    # Get metrics about the HNSW indexes
    def get_metrics
      {
        avg_insert_time: average(@metrics[:insert_time]),
        avg_search_time: average(@metrics[:search_time]),
        max_memory_usage: @metrics[:memory_usage].max || 0,
        total_indexes: @index_stores.size,
        status: @status
      }
    end
    
    # Check if a document exists in the HNSW index
    def has_document?(document_id, organization_id)
      return false if @status != STATUS_READY
      
      begin
        index = for_organization(organization_id)
        index.contains?(document_id)
      rescue => e
        Rails.logger.error("HNSW lookup error: #{e.message}")
        false
      end
    end
    
    # Remove a document from the HNSW index
    def remove(document_id, organization_id)
      return false if @status != STATUS_READY
      
      begin
        index = for_organization(organization_id)
        index.delete(document_id)
        true
      rescue => e
        Rails.logger.error("HNSW delete error: #{e.message}")
        false
      end
    end
    
    private
    
    # Normalize a vector to unit length
    def normalize(vector)
      # Calculate L2 norm (Euclidean norm)
      norm = Math.sqrt(vector.map { |x| x * x }.sum)
      return vector if norm.zero?
      
      # Normalize each component by dividing by the norm
      vector.map { |x| x / norm }
    end
    
    # Record operation metrics
    def record_operation(type, time, memory)
      case type
      when 'insert'
        @metrics[:insert_time] << time
        @metrics[:insert_time].shift if @metrics[:insert_time].size > 100
      when 'search'
        @metrics[:search_time] << time
        @metrics[:search_time].shift if @metrics[:search_time].size > 100
      end
      
      @metrics[:memory_usage] << memory
      @metrics[:memory_usage].shift if @metrics[:memory_usage].size > 100
    end
    
    # Calculate average of an array
    def average(array)
      return 0 if array.empty?
      array.sum / array.size.to_f
    end
  end
end
