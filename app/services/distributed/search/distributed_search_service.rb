# frozen_string_literal: true

module Distributed
  module Search
    # Distributed search service that provides a similar interface to WebassemblySearchService
    # but uses the distributed architecture with Raft consensus and sharding
    class DistributedSearchService
      include Singleton
      
      # Configuration constants for distributed search
      DEFAULT_CONFIG = {
        m: 16,                     # Maximum number of connections per node
        ef_construction: 200,      # Search scope during construction
        ef_search: 50,             # Search scope during query
        max_elements: 5_000_000,   # Increased maximum elements in the index for distributed
        memory_quota_mb: 4096,     # Increased memory quota for distributed operation
        partition_size: 100_000,   # Increased partition size for distributed operation
      }.freeze
      
      # Status indicators
      STATUS_INITIALIZING = 'initializing'
      STATUS_READY = 'ready'
      STATUS_ERROR = 'error'
      
      attr_reader :status, :error_message, :config
      
      def initialize
        @status = STATUS_INITIALIZING
        @error_message = nil
        @config = DEFAULT_CONFIG.dup
        @index_stores = {}  # Organization and dimension-scoped distributed indexes
        @metrics = {
          insert_time: [],
          search_time: [],
          memory_usage: []
        }
        
        # Initialize the distributed service
        initialize_distributed_service
      end
      
      # Initialize the distributed service
      def initialize_distributed_service
        begin
          # Start the distributed service if not already running
          unless Distributed::DistributedService.instance.initialized
            Distributed::DistributedService.instance.initialize_service
          end
          
          # Mark as ready
          @status = STATUS_READY
          Rails.logger.info("DistributedSearchService initialized successfully")
        rescue => e
          @status = STATUS_ERROR
          @error_message = "Failed to initialize DistributedSearchService: #{e.message}"
          Rails.logger.error(@error_message)
          Rails.logger.error(e.backtrace.join("\n"))
        end
      end
      
      # Get or create a distributed index store for an organization and dimension
      def for_organization_and_dimension(organization_id, dimension)
        key = "#{organization_id}:#{dimension}"
        @index_stores[key] ||= DistributedIndexStore.new(organization_id, dimension, @config)
      end
      
      # Format a vector for use with the distributed index
      def format_vector(vector)
        # For now, just normalize the vector
        normalize(vector)
      end
      
      # Search for nearest neighbors using the distributed index
      def search(query_vector, organization_id, options = {})
        return [] if @status != STATUS_READY
        
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        begin
          # Get dimension from options or infer from vector
          dimension = options[:dimension] || query_vector.size
          
          # Normalize query vector
          normalized_query = format_vector(query_vector)
          
          # Get index for this organization and dimension
          index = for_organization_and_dimension(organization_id, dimension)
          
          # Perform search
          k = options[:limit] || 10
          results = index.search(normalized_query, k)
          
          # Record metrics
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          duration_ms = (end_time - start_time) * 1000
          record_operation('search', duration_ms, index.memory_usage)
          
          results
        rescue => e
          Rails.logger.error("Distributed search error: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          []
        end
      end
      
      # Add a vector to the distributed index
      def insert(vector, document_id, organization_id, options = {})
        return nil if @status != STATUS_READY
        
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        begin
          # Get dimension from options or infer from vector
          dimension = options[:dimension] || vector.size
          
          # Normalize vector
          normalized_vector = format_vector(vector)
          
          # Get index for this organization and dimension
          index = for_organization_and_dimension(organization_id, dimension)
          
          # Insert into index
          reference = index.insert(normalized_vector, document_id)
          
          # Record metrics
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          duration_ms = (end_time - start_time) * 1000
          record_operation('insert', duration_ms, index.memory_usage)
          
          reference
        rescue => e
          Rails.logger.error("Distributed insert error: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          nil
        end
      end
      
      # Add multiple vectors in a batch
      def insert_batch(vectors_with_ids, organization_id, options = {})
        return false if @status != STATUS_READY
        
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        begin
          # Get dimension from options or infer from first vector
          dimension = options[:dimension] || vectors_with_ids.first[:vector].size
          
          # Normalize vectors
          normalized_vectors = vectors_with_ids.map do |v|
            v.merge(vector: format_vector(v[:vector]))
          end
          
          # Get index for this organization and dimension
          index = for_organization_and_dimension(organization_id, dimension)
          
          # Insert batch into index
          success = index.insert_batch(normalized_vectors)
          
          # Record metrics
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          duration_ms = (end_time - start_time) * 1000
          record_operation('insert_batch', duration_ms, index.memory_usage)
          
          success
        rescue => e
          Rails.logger.error("Distributed insert_batch error: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          false
        end
      end
      
      # Get metrics about the distributed indexes
      def get_metrics
        {
          avg_insert_time: average(@metrics[:insert_time]),
          avg_search_time: average(@metrics[:search_time]),
          max_memory_usage: @metrics[:memory_usage].max || 0,
          total_indexes: @index_stores.size,
          status: @status
        }
      end
      
      # Check if a document exists in the distributed index
      def has_document?(document_id, organization_id, dimension)
        return false if @status != STATUS_READY
        
        begin
          index = for_organization_and_dimension(organization_id, dimension)
          index.contains?(document_id)
        rescue => e
          Rails.logger.error("Distributed lookup error: #{e.message}")
          false
        end
      end
      
      # Remove a document from the distributed index
      def remove(document_id, organization_id, dimension)
        return false if @status != STATUS_READY
        
        begin
          index = for_organization_and_dimension(organization_id, dimension)
          index.delete(document_id)
        rescue => e
          Rails.logger.error("Distributed delete error: #{e.message}")
          false
        end
      end
      
      # Get cluster status information
      def get_cluster_status
        return {} if @status != STATUS_READY
        
        begin
          Distributed::DistributedService.instance.get_cluster_status
        rescue => e
          Rails.logger.error("Failed to get cluster status: #{e.message}")
          { error: e.message }
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
end
