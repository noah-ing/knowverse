# frozen_string_literal: true

module Distributed
  module Benchmark
    # Memory profiling for distributed system benchmarking
    class MemoryProfiler
      attr_reader :snapshots
      
      def initialize
        @snapshots = {}
        @current_report = nil
      end
      
      # Take a snapshot of the current memory state
      # @param name [String] Name of the snapshot
      # @param custom_data [Hash] Additional data to store with snapshot
      def take_snapshot(name, custom_data = {})
        # Check if memory_profiler is available
        begin
          require 'memory_profiler'
        rescue LoadError
          puts "Warning: memory_profiler gem not available. Install with: gem install memory_profiler"
          return nil
        end
        
        # Get current process memory usage
        memory_info = get_memory_info
        
        # Store snapshot
        @snapshots[name] = {
          timestamp: Time.now,
          memory_info: memory_info,
          custom_data: custom_data
        }
        
        memory_info
      end
      
      # Compare two memory snapshots
      # @param first [String] Name of first snapshot
      # @param second [String] Name of second snapshot
      # @return [Hash] Difference metrics
      def compare_snapshots(first, second)
        first_snapshot = @snapshots[first]
        second_snapshot = @snapshots[second]
        
        return nil unless first_snapshot && second_snapshot
        
        # Calculate differences
        rss_diff = second_snapshot[:memory_info][:rss] - first_snapshot[:memory_info][:rss]
        heap_diff = second_snapshot[:memory_info][:heap_used] - first_snapshot[:memory_info][:heap_used]
        objects_diff = second_snapshot[:memory_info][:objects] - first_snapshot[:memory_info][:objects]
        time_diff = second_snapshot[:timestamp] - first_snapshot[:timestamp]
        
        {
          first_snapshot: first,
          second_snapshot: second,
          time_diff_sec: time_diff.to_f,
          rss_diff_bytes: rss_diff,
          rss_diff_mb: rss_diff / (1024 * 1024.0),
          heap_diff_bytes: heap_diff,
          objects_diff: objects_diff,
          mb_per_second: (rss_diff / (1024 * 1024.0)) / [time_diff.to_f, 0.001].max
        }
      end
      
      # Run memory profiling on a specific block of code
      # @param name [String] Name for this profiling run
      # @param options [Hash] Options for profiling
      # @yield Block to profile
      # @return [Object] Result of the block
      def profile(name, options = {})
        # Check if memory_profiler is available
        begin
          require 'memory_profiler'
        rescue LoadError
          puts "Warning: memory_profiler gem not available. Install with: gem install memory_profiler"
          return yield if block_given?
        end
        
        result = nil
        
        # Take snapshot before
        before_name = "#{name}_before"
        before_snapshot = take_snapshot(before_name)
        
        # Start detailed profiling
        report = ::MemoryProfiler.report(top: options[:top] || 50) do
          result = yield if block_given?
        end
        
        # Take snapshot after
        after_name = "#{name}_after"
        after_snapshot = take_snapshot(after_name)
        
        # Store the report
        @current_report = report
        
        # Calculate difference
        diff = compare_snapshots(before_name, after_name)
        
        if options[:print_report]
          puts "Memory Profile: #{name}"
          puts "Total allocated: #{report.total_allocated_memsize / 1024.0} KB (#{report.total_allocated} objects)"
          puts "Total retained: #{report.total_retained_memsize / 1024.0} KB (#{report.total_retained} objects)"
          puts "RSS difference: #{diff[:rss_diff_mb].round(2)} MB"
          
          if options[:detailed]
            report.pretty_print
          end
        end
        
        # Store results
        @snapshots["#{name}_report"] = {
          timestamp: Time.now,
          allocated_kb: report.total_allocated_memsize / 1024.0,
          retained_kb: report.total_retained_memsize / 1024.0,
          allocated_objects: report.total_allocated,
          retained_objects: report.total_retained,
          diff: diff
        }
        
        result
      end
      
      # Profile memory usage per organization
      # @param options [Hash] Options for profiling
      # @return [Hash] Memory usage data per organization
      def profile_organization_memory(options = {})
        service = Distributed::DistributedService.instance
        results = {}
        
        # Find all organizations
        orgs = Organization.all.to_a
        
        # Take baseline snapshot
        take_snapshot('baseline')
        
        # Unload all organizations
        service.distributed_index_store.unload_all_organizations if service.respond_to?(:distributed_index_store)
        
        # Profile each organization
        orgs.each do |org|
          # Skip if insufficient data
          vector_count = org.documents.count
          next if vector_count < 5
          
          # Profile memory usage for this organization
          profile("org_#{org.id}", print_report: options[:print_report]) do
            # Load vectors for this organization
            service.distributed_index_store.load_organization(org.id) if service.respond_to?(:distributed_index_store)
            
            # Perform a test search to ensure vectors are loaded
            if service.respond_to?(:distributed_search_service)
              test_vector = Distributed::Benchmark::VectorGenerator.random_vector(1536)
              service.distributed_search_service.search(test_vector, org.id, 5)
            end
            
            # Sleep briefly to let memory stabilize
            sleep 0.5
          end
          
          # Calculate metrics based on the organization's data
          report_data = @snapshots["org_#{org.id}_report"]
          vector_count = org.documents.count
          
          results[org.id] = {
            organization_id: org.id,
            organization_name: org.name,
            document_count: vector_count,
            memory_kb: report_data[:diff][:rss_diff_bytes] / 1024.0,
            memory_per_vector_bytes: vector_count > 0 ? (report_data[:diff][:rss_diff_bytes] / vector_count.to_f) : 0,
            objects_count: report_data[:diff][:objects_diff],
            objects_per_vector: vector_count > 0 ? (report_data[:diff][:objects_diff] / vector_count.to_f) : 0
          }
          
          # Unload organization after profiling
          service.distributed_index_store.unload_organization(org.id) if service.respond_to?(:distributed_index_store)
        end
        
        # Calculate overall statistics
        total_vectors = results.sum { |_, data| data[:document_count] }
        total_memory = results.sum { |_, data| data[:memory_kb] }
        
        results[:summary] = {
          organization_count: results.size,
          total_vectors: total_vectors,
          total_memory_kb: total_memory,
          average_memory_per_vector_bytes: total_vectors > 0 ? ((total_memory * 1024) / total_vectors) : 0,
          memory_per_million_vectors_mb: total_vectors > 0 ? ((total_memory * 1000000) / (total_vectors * 1024)) : 0
        }
        
        # Print summary if requested
        if options[:print_report]
          puts "\nMemory Usage Summary:"
          puts "Organizations: #{results[:summary][:organization_count]}"
          puts "Total Vectors: #{results[:summary][:total_vectors]}"
          puts "Total Memory: #{(results[:summary][:total_memory_kb] / 1024.0).round(2)} MB"
          puts "Avg Memory Per Vector: #{results[:summary][:average_memory_per_vector_bytes].round(2)} bytes"
          puts "Memory for 1M Vectors: #{results[:summary][:memory_per_million_vectors_mb].round(2)} MB"
        end
        
        results
      end
      
      # Generate a report of memory usage
      # @return [String] Markdown-formatted report
      def generate_report
        report = "# Memory Usage Report\n\n"
        report += "## Snapshots\n\n"
        
        report += "| Snapshot | Time | RSS (MB) | Heap (MB) | Objects |\n"
        report += "|----------|------|----------|-----------|--------|\n"
        
        @snapshots.each do |name, data|
          next unless data[:memory_info] # Skip report entries
          
          timestamp = data[:timestamp].strftime('%Y-%m-%d %H:%M:%S')
          rss_mb = (data[:memory_info][:rss] / (1024 * 1024.0)).round(2)
          heap_mb = (data[:memory_info][:heap_used] / (1024 * 1024.0)).round(2)
          objects = data[:memory_info][:objects]
          
          report += "| #{name} | #{timestamp} | #{rss_mb} | #{heap_mb} | #{objects} |\n"
        end
        
        report += "\n## Memory Profiles\n\n"
        
        report += "| Profile | Allocated KB | Retained KB | Allocated Objects | Retained Objects | RSS Diff (MB) |\n"
        report += "|---------|--------------|-------------|-------------------|-----------------|---------------|\n"
        
        @snapshots.each do |name, data|
          next unless name.end_with?('_report') # Only include report entries
          
          profile_name = name.sub('_report', '')
          allocated_kb = data[:allocated_kb]&.round(2)
          retained_kb = data[:retained_kb]&.round(2)
          allocated_objects = data[:allocated_objects]
          retained_objects = data[:retained_objects]
          rss_diff_mb = data[:diff] ? data[:diff][:rss_diff_mb].round(2) : nil
          
          report += "| #{profile_name} | #{allocated_kb} | #{retained_kb} | #{allocated_objects} | #{retained_objects} | #{rss_diff_mb} |\n"
        end
        
        # Add organization memory profiles if available
        org_profiles = @snapshots.select { |name, _| name.start_with?('org_') && name.end_with?('_report') }
        
        if org_profiles.any?
          report += "\n## Organization Memory Usage\n\n"
          
          report += "| Organization | Documents | Memory (MB) | Memory per Doc (bytes) |\n"
          report += "|--------------|-----------|-------------|------------------------|\n"
          
          org_profiles.each do |name, data|
            next unless data[:diff] # Skip entries without diff data
            
            org_id = name.sub('org_', '').sub('_report', '')
            org = Organization.find_by(id: org_id)
            next unless org
            
            docs = org.documents.count
            memory_mb = (data[:diff][:rss_diff_bytes] / (1024 * 1024.0)).round(2)
            memory_per_doc = docs > 0 ? (data[:diff][:rss_diff_bytes] / docs.to_f).round(2) : 0
            
            report += "| #{org.name} (#{org_id}) | #{docs} | #{memory_mb} | #{memory_per_doc} |\n"
          end
        end
        
        report
      end
      
      # Get current process memory information
      # @return [Hash] Memory metrics
      def get_memory_info
        process_info = get_process_info
        
        # Get GC stats
        gc_stats = GC.stat
        
        {
          rss: process_info[:rss] || 0,
          vsz: process_info[:vsz] || 0,
          heap_used: gc_stats[:heap_live_slots] * gc_stats[:heap_slot_size],
          heap_available: gc_stats[:heap_available_slots] * gc_stats[:heap_slot_size],
          objects: gc_stats[:heap_live_slots],
          gc_stat: gc_stats
        }
      end
      
      # Get process info from the operating system
      # @return [Hash] Process metrics
      def get_process_info
        case RbConfig::CONFIG['host_os']
        when /darwin|mac os/
          get_process_info_mac
        when /linux/
          get_process_info_linux
        when /mswin|mingw|windows/
          get_process_info_windows
        else
          { rss: 0, vsz: 0 }
        end
      end
      
      # Get process info on macOS
      # @return [Hash] Process metrics
      def get_process_info_mac
        pid = Process.pid
        output = `ps -o rss=,vsz= -p #{pid}`.strip.split
        
        {
          rss: output[0].to_i * 1024, # KB to bytes
          vsz: output[1].to_i * 1024  # KB to bytes
        }
      end
      
      # Get process info on Linux
      # @return [Hash] Process metrics
      def get_process_info_linux
        pid = Process.pid
        
        if File.exist?("/proc/#{pid}/status")
          status = File.read("/proc/#{pid}/status")
          
          rss = status.match(/VmRSS:\s+(\d+) kB/)
          vsz = status.match(/VmSize:\s+(\d+) kB/)
          
          {
            rss: rss ? rss[1].to_i * 1024 : 0, # KB to bytes
            vsz: vsz ? vsz[1].to_i * 1024 : 0  # KB to bytes
          }
        else
          output = `ps -o rss=,vsz= -p #{pid}`.strip.split
          
          {
            rss: output[0].to_i * 1024, # KB to bytes
            vsz: output[1].to_i * 1024  # KB to bytes
          }
        end
      end
      
      # Get process info on Windows
      # @return [Hash] Process metrics
      def get_process_info_windows
        pid = Process.pid
        output = `tasklist /FI "PID eq #{pid}" /FO LIST`
        
        mem = output.match(/Mem Usage:\s+([0-9,]+) K/)
        
        {
          rss: mem ? mem[1].gsub(',', '').to_i * 1024 : 0, # KB to bytes
          vsz: 0 # Not easily available on Windows
        }
      end
    end
  end
end
