namespace :documents do
  desc "Process all pending documents"
  task process_pending: :environment do
    count = DocumentProcessing::TextExtractionWorker.process_all_pending
    puts "Queued #{count} pending documents for processing"
  end
  
  desc "Reset and reprocess documents stuck in processing state"
  task reset_stuck: :environment do
    count = DocumentProcessing::TextExtractionWorker.retry_stuck_processing
    puts "Reset and requeued #{count} stuck documents"
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
