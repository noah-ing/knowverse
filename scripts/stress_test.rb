#!/usr/bin/env ruby
# frozen_string_literal: true

# Enterprise Stress Test for Document Processing Pipeline
# Usage: rails runner scripts/stress_test.rb [num_documents] [--dry-run]
#
# This script tests the document processing pipeline at scale by:
# 1. Generating test documents of various sizes and types
# 2. Uploading them in batches
# 3. Monitoring queue depth and processing times
# 4. Reporting throughput metrics

require 'benchmark'
require 'securerandom'

class StressTest
  DOCUMENT_TYPES = {
    small_txt: { ext: 'txt', size: 1_000, description: '1KB text' },
    medium_txt: { ext: 'txt', size: 10_000, description: '10KB text' },
    large_txt: { ext: 'txt', size: 100_000, description: '100KB text' },
    small_md: { ext: 'md', size: 5_000, description: '5KB markdown' },
    medium_md: { ext: 'md', size: 50_000, description: '50KB markdown' },
    json_data: { ext: 'json', size: 20_000, description: '20KB JSON' },
    csv_data: { ext: 'csv', size: 30_000, description: '30KB CSV' }
  }.freeze

  BATCH_SIZE = 50
  POLL_INTERVAL = 2 # seconds

  attr_reader :organization, :user, :results

  def initialize(num_documents: 100, dry_run: false)
    @num_documents = num_documents
    @dry_run = dry_run
    @results = {
      started_at: Time.current,
      documents_created: 0,
      documents_processed: 0,
      documents_errored: 0,
      extraction_times: [],
      embedding_times: [],
      total_chunks: 0,
      queue_depths: []
    }
  end

  def run
    setup_test_environment
    print_header

    if @dry_run
      puts "\n[DRY RUN] Would create #{@num_documents} documents"
      puts "Estimated time: #{estimate_time}"
      return
    end

    # Phase 1: Create documents
    puts "\n📁 Phase 1: Creating #{@num_documents} documents..."
    documents = create_documents

    # Phase 2: Monitor processing
    puts "\n⚙️  Phase 2: Monitoring processing..."
    monitor_processing(documents)

    # Phase 3: Report results
    print_results
  end

  private

  def setup_test_environment
    # Use existing organization and user (first ones found)
    @organization = Organization.first
    @user = User.first

    unless @organization && @user
      puts "ERROR: No organization or user found in database."
      puts "Please run the app and create at least one organization and user first."
      exit 1
    end

    # Ensure user is member of org
    unless @organization.users.include?(@user)
      OrganizationUser.create!(organization: @organization, user: @user, role: 'admin')
    end

    # Temporarily increase document limit for testing
    @original_max_docs = @organization.settings['max_documents']
    @organization.update!(settings: @organization.settings.merge('max_documents' => 1_000_000))

    puts "✅ Test environment ready"
    puts "   Organization: #{@organization.name} (ID: #{@organization.id})"
    puts "   User: #{@user.email}"
  end

  def print_header
    puts "\n" + "=" * 60
    puts "🚀 KNOWVERSE ENTERPRISE STRESS TEST"
    puts "=" * 60
    puts "Documents to create: #{@num_documents}"
    puts "Batch size: #{BATCH_SIZE}"
    puts "Document types: #{DOCUMENT_TYPES.keys.join(', ')}"
    puts "Started at: #{Time.current}"
    puts "=" * 60
  end

  def create_documents
    documents = []

    @num_documents.times.each_slice(BATCH_SIZE).with_index do |batch_indices, batch_num|
      batch_start = Time.current
      batch_docs = []

      batch_indices.each do |i|
        doc_type = DOCUMENT_TYPES.keys.sample
        config = DOCUMENT_TYPES[doc_type]

        content = generate_content(config[:ext], config[:size])
        filename = "stress_test_#{i + 1}_#{doc_type}.#{config[:ext]}"

        doc = Document.new(
          title: "Stress Test Document #{i + 1} (#{config[:description]})",
          organization: @organization,
          status: 'pending',
          embedding_status: 'pending',
          metadata: { stress_test: true, doc_type: doc_type.to_s }
        )

        # Attach file
        doc.file.attach(
          io: StringIO.new(content),
          filename: filename,
          content_type: mime_type_for(config[:ext])
        )

        doc.save!
        batch_docs << doc
        @results[:documents_created] += 1

        # Queue processing
        DocumentProcessing::TextExtractionWorker.perform_later(doc.id)
      end

      documents.concat(batch_docs)
      batch_time = Time.current - batch_start

      print "\r   Batch #{batch_num + 1}/#{(@num_documents.to_f / BATCH_SIZE).ceil}: " \
            "#{@results[:documents_created]}/#{@num_documents} created " \
            "(#{batch_time.round(2)}s/batch)"
    end

    puts "\n✅ All documents created and queued"
    documents
  end

  def monitor_processing(documents)
    doc_ids = documents.map(&:id)
    start_time = Time.current
    last_processed = 0

    loop do
      # Check document statuses
      stats = Document.where(id: doc_ids).group(:status, :embedding_status).count

      processed = documents.reload.count { |d| d.embedding_status == 'processed' }
      errored = documents.count { |d| d.status == 'error' || d.embedding_status == 'error' }
      pending = @num_documents - processed - errored

      # Track queue depth
      queue_depth = SolidQueue::Job.where(finished_at: nil).count rescue 0
      @results[:queue_depths] << { time: Time.current, depth: queue_depth }

      # Calculate throughput
      elapsed = Time.current - start_time
      throughput = processed > 0 ? (processed / elapsed * 60).round(1) : 0

      # Progress bar
      progress = (processed.to_f / @num_documents * 50).round
      bar = "█" * progress + "░" * (50 - progress)

      print "\r   [#{bar}] #{processed}/#{@num_documents} " \
            "(#{errored} errors) | Queue: #{queue_depth} | #{throughput} docs/min"

      # Check if done
      if processed + errored >= @num_documents
        puts "\n✅ Processing complete!"
        break
      end

      # Timeout after 2 hours
      if elapsed > 7200
        puts "\n⚠️  Timeout after 2 hours"
        break
      end

      sleep POLL_INTERVAL
    end

    # Gather final stats
    gather_final_stats(documents)
  end

  def gather_final_stats(documents)
    documents.reload.each do |doc|
      if doc.status == 'processed'
        if doc.metadata['extraction_time_ms']
          @results[:extraction_times] << doc.metadata['extraction_time_ms']
        end
      end

      if doc.embedding_status == 'processed'
        @results[:documents_processed] += 1
        @results[:total_chunks] += doc.vector_embeddings.count
      elsif doc.embedding_status == 'error'
        @results[:documents_errored] += 1
      end
    end

    @results[:finished_at] = Time.current
    @results[:total_time] = @results[:finished_at] - @results[:started_at]
  end

  def print_results
    puts "\n" + "=" * 60
    puts "📊 STRESS TEST RESULTS"
    puts "=" * 60

    puts "\n📈 Processing Summary:"
    puts "   Documents created:   #{@results[:documents_created]}"
    puts "   Documents processed: #{@results[:documents_processed]}"
    puts "   Documents errored:   #{@results[:documents_errored]}"
    puts "   Total chunks:        #{@results[:total_chunks]}"

    puts "\n⏱️  Timing:"
    puts "   Total time: #{format_duration(@results[:total_time])}"
    if @results[:documents_processed] > 0
      avg_time = @results[:total_time] / @results[:documents_processed]
      puts "   Avg per document: #{avg_time.round(2)}s"
      puts "   Throughput: #{(@results[:documents_processed] / @results[:total_time] * 60).round(1)} docs/min"
    end

    if @results[:extraction_times].any?
      puts "\n📄 Extraction Times (ms):"
      puts "   Min: #{@results[:extraction_times].min}"
      puts "   Max: #{@results[:extraction_times].max}"
      puts "   Avg: #{(@results[:extraction_times].sum.to_f / @results[:extraction_times].size).round(1)}"
    end

    if @results[:queue_depths].any?
      depths = @results[:queue_depths].map { |q| q[:depth] }
      puts "\n📬 Queue Depth:"
      puts "   Max: #{depths.max}"
      puts "   Avg: #{(depths.sum.to_f / depths.size).round(1)}"
    end

    # Extrapolation for 100k
    if @results[:documents_processed] > 0
      time_per_doc = @results[:total_time] / @results[:documents_processed]
      estimated_100k = time_per_doc * 100_000
      puts "\n🔮 Extrapolation for 100k documents:"
      puts "   Estimated time: #{format_duration(estimated_100k)}"
      puts "   With 10x concurrency: #{format_duration(estimated_100k / 10)}"
    end

    puts "\n" + "=" * 60

    # Save results to file
    save_results
  end

  def save_results
    results_file = Rails.root.join('tmp', "stress_test_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json")
    File.write(results_file, @results.to_json)
    puts "📁 Results saved to: #{results_file}"
  end

  def generate_content(ext, size)
    case ext
    when 'txt', 'md'
      generate_text_content(size)
    when 'json'
      generate_json_content(size)
    when 'csv'
      generate_csv_content(size)
    else
      generate_text_content(size)
    end
  end

  def generate_text_content(size)
    paragraphs = []
    topics = [
      "machine learning", "data processing", "enterprise systems",
      "document management", "vector databases", "semantic search",
      "natural language processing", "knowledge management"
    ]

    while paragraphs.join("\n\n").length < size
      topic = topics.sample
      paragraphs << "This document discusses #{topic} in the context of enterprise " \
                   "knowledge management systems. The implementation involves " \
                   "#{['advanced algorithms', 'distributed processing', 'scalable architecture'].sample} " \
                   "to handle #{rand(1000..100000)} records efficiently. " \
                   "Key considerations include #{['performance', 'reliability', 'security'].sample} " \
                   "and #{['scalability', 'maintainability', 'cost-effectiveness'].sample}."
    end

    paragraphs.join("\n\n")[0...size]
  end

  def generate_json_content(size)
    data = {
      metadata: {
        generated_at: Time.current.iso8601,
        type: 'stress_test',
        version: '1.0'
      },
      records: []
    }

    while data.to_json.length < size
      data[:records] << {
        id: SecureRandom.uuid,
        name: "Record #{data[:records].size + 1}",
        value: rand(1000..99999),
        tags: %w[enterprise test document].sample(2),
        created_at: Time.current.iso8601
      }
    end

    JSON.pretty_generate(data)[0...size]
  end

  def generate_csv_content(size)
    rows = ["id,name,value,category,created_at"]

    while rows.join("\n").length < size
      rows << "#{SecureRandom.uuid},Item #{rows.size},#{rand(100..9999)}," \
              "#{%w[A B C D].sample},#{Time.current.iso8601}"
    end

    rows.join("\n")[0...size]
  end

  def mime_type_for(ext)
    {
      'txt' => 'text/plain',
      'md' => 'text/markdown',
      'json' => 'application/json',
      'csv' => 'text/csv'
    }[ext] || 'application/octet-stream'
  end

  def format_duration(seconds)
    return "0s" if seconds.nil? || seconds <= 0

    hours = (seconds / 3600).floor
    minutes = ((seconds % 3600) / 60).floor
    secs = (seconds % 60).round(1)

    parts = []
    parts << "#{hours}h" if hours > 0
    parts << "#{minutes}m" if minutes > 0
    parts << "#{secs}s" if secs > 0 || parts.empty?
    parts.join(' ')
  end

  def estimate_time
    # Rough estimate: 5s per document with current config
    estimated_seconds = @num_documents * 5
    format_duration(estimated_seconds)
  end
end

# Parse arguments
num_docs = ARGV[0]&.to_i || 100
dry_run = ARGV.include?('--dry-run')

# Run the test
test = StressTest.new(num_documents: num_docs, dry_run: dry_run)
test.run
