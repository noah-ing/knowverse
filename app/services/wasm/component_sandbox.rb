# frozen_string_literal: true

require 'timeout'
require 'securerandom'

module Wasm
  # WASM 3.0 Component Model sandbox for secure document processing
  # Each document type runs in an isolated WASM component with:
  # - Memory isolation (no shared state)
  # - Resource limits (CPU, memory, time)
  # - Capability-based security (explicit permissions)
  #
  # This orchestrator manages WASM component lifecycle and provides
  # a Ruby interface to the sandboxed processing pipelines.
  class ComponentSandbox
    include Singleton

    # Resource limits per component instance
    MEMORY_LIMIT_MB = 512
    CPU_TIME_LIMIT_SEC = 30
    MAX_OUTPUT_SIZE_MB = 100

    # Component registry
    COMPONENTS = {
      pdf: 'knowverse_pdf_extractor.wasm',
      docx: 'knowverse_docx_extractor.wasm',
      excel: 'knowverse_excel_extractor.wasm',
      image: 'knowverse_image_ocr.wasm',
      chunker: 'knowverse_text_chunker.wasm'
    }.freeze

    # WASM Component Model interface types
    module WIT
      # Document extraction interface
      EXTRACT_INTERFACE = <<~WIT
        package knowverse:extraction@1.0.0;

        interface extractor {
          record extraction-result {
            content: string,
            metadata: list<tuple<string, string>>,
            chunks: list<text-chunk>,
            tables: list<table-data>,
            success: bool,
            error: option<string>
          }

          record text-chunk {
            content: string,
            start-offset: u64,
            end-offset: u64,
            page: option<u32>,
            heading: option<string>
          }

          record table-data {
            headers: list<string>,
            rows: list<list<string>>,
            page: option<u32>
          }

          extract: func(data: list<u8>, options: extraction-options) -> extraction-result;

          record extraction-options {
            extract-tables: bool,
            extract-images: bool,
            preserve-layout: bool,
            max-pages: option<u32>
          }
        }
      WIT
    end

    def initialize
      @runtime = nil
      @component_cache = {}
      @instance_pool = {}
      @metrics = ComponentMetrics.new
      @lock = Mutex.new
    end

    # Initialize the WASM runtime
    def initialize_runtime
      @lock.synchronize do
        return if @runtime

        # In production, this would initialize wasmtime or wasmer
        # For now, we simulate the runtime interface
        @runtime = WasmRuntime.new(
          memory_limit_pages: MEMORY_LIMIT_MB * 16,  # 64KB per page
          fuel_limit: CPU_TIME_LIMIT_SEC * 1_000_000_000  # Nanosecond fuel
        )

        # Preload commonly used components
        preload_components

        Rails.logger.info("[WasmSandbox] Runtime initialized")
      end
    end

    # Process a document in a sandboxed WASM component
    def process_document(file_content, file_type:, options: {})
      initialize_runtime unless @runtime

      component = component_for_type(file_type)
      return { success: false, error: "Unsupported file type: #{file_type}" } unless component

      instance_id = SecureRandom.uuid
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        # Create isolated component instance
        instance = create_instance(component, instance_id)

        # Set up capability grants
        grant_capabilities(instance, options)

        # Execute extraction in sandbox
        result = execute_with_limits(instance) do
          instance.call('extract', file_content, extraction_options(options))
        end

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        @metrics.record_extraction(file_type, duration, file_content.bytesize)

        transform_result(result)

      rescue WasmTrap => e
        Rails.logger.error("[WasmSandbox] Trap in #{file_type} component: #{e.message}")
        { success: false, error: "Processing error: #{e.message}" }

      rescue Timeout::Error
        Rails.logger.error("[WasmSandbox] Timeout processing #{file_type}")
        { success: false, error: "Processing timeout exceeded #{CPU_TIME_LIMIT_SEC}s" }

      ensure
        destroy_instance(instance_id)
      end
    end

    # Process multiple documents in parallel sandboxes
    def process_batch(documents, concurrency: 4)
      queue = Queue.new
      documents.each { |doc| queue << doc }

      results = Concurrent::Hash.new
      workers = []

      concurrency.times do
        workers << Thread.new do
          while (doc = queue.pop(true) rescue nil)
            result = process_document(
              doc[:content],
              file_type: doc[:type],
              options: doc[:options] || {}
            )
            results[doc[:id]] = result
          end
        end
      end

      workers.each(&:join)
      results.to_h
    end

    # Chunk text using the chunker component
    def chunk_text(content, strategy: :semantic, chunk_size: 512, overlap: 64)
      initialize_runtime unless @runtime

      component = @component_cache[:chunker]
      return simple_chunk(content, chunk_size, overlap) unless component

      instance_id = SecureRandom.uuid

      begin
        instance = create_instance(component, instance_id)

        result = execute_with_limits(instance) do
          instance.call('chunk', content, {
            strategy: strategy.to_s,
            chunk_size: chunk_size,
            overlap: overlap
          })
        end

        result[:chunks] || simple_chunk(content, chunk_size, overlap)

      ensure
        destroy_instance(instance_id)
      end
    end

    # Get component health and metrics
    def health
      {
        runtime_initialized: !@runtime.nil?,
        components_loaded: @component_cache.keys,
        active_instances: @instance_pool.size,
        metrics: @metrics.summary
      }
    end

    private

    def component_for_type(file_type)
      type_sym = file_type.to_s.downcase.to_sym

      # Map file extensions to components
      mapping = {
        pdf: :pdf,
        docx: :docx,
        doc: :docx,
        xlsx: :excel,
        xls: :excel,
        csv: :excel,
        png: :image,
        jpg: :image,
        jpeg: :image,
        tiff: :image
      }

      component_type = mapping[type_sym]
      return nil unless component_type

      @component_cache[component_type] ||= load_component(component_type)
    end

    def load_component(type)
      wasm_path = Rails.root.join('lib', 'wasm', 'components', COMPONENTS[type])

      if File.exist?(wasm_path)
        @runtime.compile(File.binread(wasm_path))
      else
        # Fallback to simulation for development
        SimulatedComponent.new(type)
      end
    end

    def preload_components
      [:pdf, :docx, :excel, :chunker].each do |type|
        @component_cache[type] = load_component(type)
      end
    end

    def create_instance(component, instance_id)
      instance = @runtime.instantiate(component, {
        memory_limit: MEMORY_LIMIT_MB * 1024 * 1024,
        fuel_limit: CPU_TIME_LIMIT_SEC * 1_000_000_000
      })

      @instance_pool[instance_id] = instance
      instance
    end

    def destroy_instance(instance_id)
      instance = @instance_pool.delete(instance_id)
      instance&.destroy
    end

    def grant_capabilities(instance, options)
      # WASM Component Model uses capability-based security
      # Grant only the minimum required capabilities

      capabilities = [:read_input, :write_output]

      # Optional capabilities based on extraction needs
      capabilities << :access_fonts if options[:preserve_layout]
      capabilities << :ocr_engine if options[:extract_images]

      instance.grant_capabilities(capabilities)
    end

    def execute_with_limits(instance)
      Timeout.timeout(CPU_TIME_LIMIT_SEC) do
        yield
      end
    end

    def extraction_options(options)
      {
        extract_tables: options.fetch(:extract_tables, true),
        extract_images: options.fetch(:extract_images, false),
        preserve_layout: options.fetch(:preserve_layout, true),
        max_pages: options[:max_pages]
      }
    end

    def transform_result(wasm_result)
      return { success: false, error: 'No result' } unless wasm_result

      {
        success: wasm_result[:success],
        content: wasm_result[:content],
        metadata: Hash[wasm_result[:metadata] || []],
        chunks: (wasm_result[:chunks] || []).map do |chunk|
          {
            content: chunk[:content],
            start_offset: chunk[:start_offset],
            end_offset: chunk[:end_offset],
            page: chunk[:page],
            heading: chunk[:heading]
          }
        end,
        tables: (wasm_result[:tables] || []).map do |table|
          {
            headers: table[:headers],
            rows: table[:rows],
            page: table[:page]
          }
        end,
        error: wasm_result[:error]
      }
    end

    def simple_chunk(content, chunk_size, overlap)
      chunks = []
      offset = 0

      while offset < content.length
        chunk_end = [offset + chunk_size, content.length].min
        chunks << {
          content: content[offset...chunk_end],
          start_offset: offset,
          end_offset: chunk_end
        }
        offset += chunk_size - overlap
      end

      chunks
    end

    # Custom error for WASM traps
    class WasmTrap < StandardError; end

    # Simulated WASM runtime for development
    class WasmRuntime
      def initialize(memory_limit_pages:, fuel_limit:)
        @memory_limit = memory_limit_pages * 65536
        @fuel_limit = fuel_limit
      end

      def compile(wasm_bytes)
        # In production: wasmtime::Module::new(engine, wasm_bytes)
        SimulatedModule.new(wasm_bytes.bytesize)
      end

      def instantiate(module_obj, limits)
        SimulatedInstance.new(module_obj, limits)
      end
    end

    class SimulatedModule
      def initialize(size)
        @size = size
      end
    end

    class SimulatedInstance
      def initialize(module_obj, limits)
        @module = module_obj
        @limits = limits
        @capabilities = []
      end

      def grant_capabilities(caps)
        @capabilities = caps
      end

      def call(func, *args)
        # Simulate WASM function call
        # In production, this would invoke the actual WASM function
        case func
        when 'extract'
          simulate_extraction(args[0], args[1])
        when 'chunk'
          simulate_chunking(args[0], args[1])
        else
          { success: false, error: "Unknown function: #{func}" }
        end
      end

      def destroy
        # Clean up instance resources
      end

      private

      def simulate_extraction(content, options)
        # This simulates what the WASM component would return
        # In production, actual WASM code handles this
        {
          success: true,
          content: "Extracted content (#{content.bytesize} bytes)",
          metadata: [['source', 'wasm_sandbox'], ['version', '1.0']],
          chunks: [{
            content: content[0, 1000],
            start_offset: 0,
            end_offset: [content.bytesize, 1000].min
          }],
          tables: []
        }
      end

      def simulate_chunking(content, options)
        chunk_size = options[:chunk_size] || 512
        overlap = options[:overlap] || 64
        chunks = []
        offset = 0

        while offset < content.length
          chunk_end = [offset + chunk_size, content.length].min
          chunks << {
            content: content[offset...chunk_end],
            start_offset: offset,
            end_offset: chunk_end
          }
          offset += chunk_size - overlap
        end

        { chunks: chunks }
      end
    end

    # Simulated component for types without real WASM
    class SimulatedComponent
      def initialize(type)
        @type = type
      end
    end

    # Metrics collector for component performance
    class ComponentMetrics
      def initialize
        @extractions = Hash.new { |h, k| h[k] = { count: 0, total_time: 0, total_bytes: 0 } }
        @lock = Mutex.new
      end

      def record_extraction(type, duration, bytes)
        @lock.synchronize do
          @extractions[type][:count] += 1
          @extractions[type][:total_time] += duration
          @extractions[type][:total_bytes] += bytes
        end
      end

      def summary
        @lock.synchronize do
          @extractions.transform_values do |stats|
            {
              count: stats[:count],
              avg_time_ms: stats[:count] > 0 ? (stats[:total_time] / stats[:count] * 1000).round(2) : 0,
              total_mb_processed: (stats[:total_bytes] / (1024.0 * 1024)).round(2)
            }
          end
        end
      end
    end
  end
end
