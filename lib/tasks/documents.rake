namespace :documents do
  desc "Process all pending documents (async - requires job processor)"
  task process_pending: :environment do
    count = DocumentProcessing::TextExtractionWorker.process_all_pending
    puts "Queued #{count} pending documents for processing"
  end

  desc "Reset and reprocess documents stuck in processing state"
  task reset_stuck: :environment do
    count = DocumentProcessing::TextExtractionWorker.retry_stuck_processing
    puts "Reset and requeued #{count} stuck documents"
  end

  desc "Process documents synchronously (fast batch mode - no job processor needed)"
  task :process_sync, [:org_id, :threads] => :environment do |_t, args|
    org_id = args[:org_id]
    thread_count = (args[:threads] || 4).to_i

    documents = if org_id
      Document.where(organization_id: org_id).where(status: ['pending', 'processing'])
    else
      Document.where(status: ['pending', 'processing'])
    end

    total = documents.count
    if total == 0
      puts "No pending documents to process"
      next
    end

    puts "Processing #{total} documents synchronously with #{thread_count} threads..."
    start_time = Time.now

    processed = Concurrent::AtomicFixnum.new(0)
    failed = Concurrent::AtomicFixnum.new(0)

    # Create thread pool
    pool = Concurrent::FixedThreadPool.new(thread_count)

    documents.find_each do |doc|
      pool.post do
        begin
          # Run text extraction synchronously
          DocumentProcessing::TextExtractionWorker.new.perform(doc.id)

          # Run embedding generation synchronously
          DocumentProcessing::EmbeddingGenerationWorker.new.perform(doc.id)

          count = processed.increment
          puts "  [#{count}/#{total}] ✓ #{doc.title}"
        rescue => e
          failed.increment
          puts "  [FAIL] #{doc.title}: #{e.message}"
        end
      end
    end

    # Wait for all jobs to complete
    pool.shutdown
    pool.wait_for_termination

    elapsed = Time.now - start_time
    puts "\n=== BATCH PROCESSING COMPLETE ==="
    puts "  Total: #{total}"
    puts "  Success: #{processed.value}"
    puts "  Failed: #{failed.value}"
    puts "  Time: #{elapsed.round(2)}s (#{(total / elapsed).round(2)} docs/sec)"
  end

  desc "Generate embeddings for processed documents without embeddings"
  task :embed_sync, [:org_id, :threads] => :environment do |_t, args|
    org_id = args[:org_id]
    thread_count = (args[:threads] || 4).to_i

    documents = if org_id
      Document.where(organization_id: org_id, status: 'processed', embedding_status: ['pending', 'processing'])
    else
      Document.where(status: 'processed', embedding_status: ['pending', 'processing'])
    end

    total = documents.count
    if total == 0
      puts "No documents need embedding generation"
      next
    end

    puts "Generating embeddings for #{total} documents with #{thread_count} threads..."
    start_time = Time.now

    processed = Concurrent::AtomicFixnum.new(0)
    failed = Concurrent::AtomicFixnum.new(0)

    pool = Concurrent::FixedThreadPool.new(thread_count)

    documents.find_each do |doc|
      pool.post do
        begin
          DocumentProcessing::EmbeddingGenerationWorker.new.perform(doc.id)
          count = processed.increment
          puts "  [#{count}/#{total}] ✓ #{doc.title}"
        rescue => e
          failed.increment
          puts "  [FAIL] #{doc.title}: #{e.message}"
        end
      end
    end

    pool.shutdown
    pool.wait_for_termination

    elapsed = Time.now - start_time
    puts "\n=== EMBEDDING GENERATION COMPLETE ==="
    puts "  Total: #{total}"
    puts "  Success: #{processed.value}"
    puts "  Failed: #{failed.value}"
    puts "  Time: #{elapsed.round(2)}s"
  end

  desc "Reprocess a specific document"
  task :reprocess, [:doc_id] => :environment do |_t, args|
    doc_id = args[:doc_id]
    unless doc_id
      puts "Usage: rake documents:reprocess[DOC_ID]"
      next
    end

    doc = Document.find(doc_id)
    puts "Reprocessing document: #{doc.title}"

    # Reset status
    doc.update!(status: 'pending', embedding_status: 'pending')
    doc.vector_embeddings.destroy_all

    # Process synchronously
    DocumentProcessing::TextExtractionWorker.new.perform(doc.id)
    DocumentProcessing::EmbeddingGenerationWorker.new.perform(doc.id)

    doc.reload
    chunks = Search::UnifiedSearchService.new.stats(doc.organization_id)
    puts "✓ Complete - Status: #{doc.status}/#{doc.embedding_status}, Vectors: #{chunks[:points_count] || 'N/A'}"
  end

  desc "Show document processing statistics"
  task stats: :environment do
    puts "=== DOCUMENT PROCESSING STATISTICS ==="
    puts ""
    puts "By Status:"
    Document.group(:status).count.each { |s, c| puts "  #{s}: #{c}" }
    puts ""
    puts "By Embedding Status:"
    Document.group(:embedding_status).count.each { |s, c| puts "  #{s}: #{c}" }
    puts ""
    puts "By Organization:"
    Organization.find_each do |org|
      doc_count = org.documents.count
      next if doc_count == 0

      embedded = org.documents.where(embedding_status: 'completed').count
      search_service = Search::UnifiedSearchService.new
      stats = search_service.stats(org.id)

      puts "  #{org.name}: #{doc_count} docs, #{embedded} embedded, #{stats[:points_count] || 0} vectors"
    end
  end

  desc "Fix document processing pipeline by clearing and resetting stuck jobs"
  task fix_processing_pipeline: :environment do
    # Get counts before running the fix
    pending_before = Document.pending.count
    processing_before = Document.processing.count
    processed_before = Document.processed.count
    error_before = Document.errored.count
    
    puts "Document counts before fix:"
    puts "  Pending: #{pending_before}"
    puts "  Processing: #{processing_before}"
    puts "  Processed: #{processed_before}"
    puts "  Error: #{error_before}"
    puts "--------------------------------------"
    
    # Reset documents stuck in processing state back to pending
    stuck_processing = Document.processing.where('updated_at < ?', 10.minutes.ago)
    stuck_count = stuck_processing.count
    
    puts "Found #{stuck_count} documents stuck in processing state"
    
    if stuck_count > 0
      # Reset in batches to avoid memory issues with large datasets
      batch_size = 100
      total_reset = 0
      
      stuck_processing.find_in_batches(batch_size: batch_size) do |batch|
        batch.each do |document|
          document.update(status: 'pending')
          total_reset += 1
        end
        puts "  Reset #{total_reset} documents so far..."
      end
      
      puts "Successfully reset #{total_reset} stuck documents to pending state"
    end
    
    # Now process all pending documents
    pending_count = Document.pending.count
    puts "Queueing #{pending_count} pending documents for processing..."
    
    # Queue in smaller batches to prevent overwhelming the job queue
    batch_size = 50
    total_queued = 0
    
    Document.pending.find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |document|
        DocumentProcessing::TextExtractionWorker.perform_later(document.id)
        total_queued += 1
      end
      puts "  Queued #{total_queued} documents so far..."
    end
    
    puts "Successfully queued #{total_queued} documents for processing"
    puts "--------------------------------------"
    
    # Count errors for reporting
    errors_in_text = Document.where(status: 'error').count
    errors_in_embedding = Document.where(embedding_status: 'error').count
    
    puts "Current error counts:"
    puts "  Documents with text extraction errors: #{errors_in_text}"
    puts "  Documents with embedding errors: #{errors_in_embedding}"
    puts ""
    puts "To process all pending documents again in the future, run:"
    puts "  rake documents:process_pending"
    puts ""
    puts "To reset stuck documents in the future, run:"
    puts "  rake documents:reset_stuck"
  end
end
