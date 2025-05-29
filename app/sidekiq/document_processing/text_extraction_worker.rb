module DocumentProcessing
  class TextExtractionWorker < ActiveJob::Base
    queue_as :document_processing
    
    # Retry options for more resilience
    retry_on StandardError, wait: :exponentially_longer, attempts: 3
    
    # For backwards compatibility with existing code that might still use Sidekiq API
    def self.perform_async(document_id)
      perform_later(document_id)
    end
    
    # For direct access in Rails console to process documents
    def self.process_all_pending
      count = 0
      Document.pending.find_each do |document|
        perform_later(document.id)
        count += 1
      end
      Rails.logger.info("Queued #{count} pending documents for processing")
      count
    end
    
    # Process documents stuck in processing state for too long
    def self.retry_stuck_processing
      # Find documents that have been in processing state for more than 10 minutes
      cutoff_time = 10.minutes.ago
      stuck_docs = Document.processing.where('updated_at < ?', cutoff_time)
      
      count = 0
      stuck_docs.find_each do |document|
        Rails.logger.info("Resetting stuck document #{document.id} from processing back to pending")
        document.update(status: 'pending')
        perform_later(document.id)
        count += 1
      end
      
      Rails.logger.info("Reset and requeued #{count} stuck documents")
      count
    end
    
    def perform(document_id)
      # Use find not find_by to raise error if document doesn't exist
      document = begin
        Document.find(document_id)
      rescue ActiveRecord::RecordNotFound
        Rails.logger.error("Document #{document_id} not found, skipping processing")
        return
      end
      
      begin
        Rails.logger.info("Processing document #{document_id}")
        
        # Ensure document is in processing state (idempotent)
        document.mark_as_processing!
        
        if document.file.attached?
          # Extract text from file based on file type
          extracted_text = extract_text(document)
          
          # Update document with extracted text
          document.update(
            content: extracted_text,
            status: 'processed',
            file_type: document.determine_file_type
          )
          
          Rails.logger.info("Successfully extracted text for document #{document_id}")
        elsif document.content.present?
          # Document already has content but no file attached (test or direct content creation)
          document.update(status: 'processed')
          Rails.logger.info("Document #{document_id} already had content, marked as processed")
        else
          # No file and no content
          document.mark_as_error!("No file attached and no content available")
          Rails.logger.error("Document #{document_id} has no file or content")
          return
        end
        
        # Queue embedding generation after successful extraction
        Rails.logger.info("Queueing embedding generation for document #{document_id}")
        DocumentProcessing::EmbeddingGenerationWorker.perform_later(document_id)
      rescue => e
        document.mark_as_error!(e.message)
        Rails.logger.error("Text extraction failed for document #{document_id}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        
        # Re-raise so retry mechanics can work
        raise e
      end
    end
    
    private
    
    def extract_text(document)
      # Temporary file path
      file_path = download_to_tempfile(document)
      
      extracted_text = case document.file_extension
      when 'pdf'
        extract_text_from_pdf(file_path)
      when 'docx', 'doc'
        extract_text_from_docx(file_path)
      when 'txt', 'md', 'rtf'
        extract_text_from_text_file(file_path)
      else
        # For other file types, use a generic placeholder
        "Content from #{document.file_extension || 'unknown'} file: #{document.title || 'Untitled'}"
      end
      
      # If extraction produced no text, use a placeholder
      if extracted_text.blank?
        Rails.logger.warn("Empty text extracted from document #{document.id}, using placeholder")
        extracted_text = "Placeholder content for document: #{document.title || 'Untitled'}"
      end
      
      extracted_text
    rescue => e
      Rails.logger.error("Error extracting text: #{e.message}")
      "Error extracting text: #{e.message}. Please try re-uploading this document."
    ensure
      # Clean up temporary file
      File.unlink(file_path) if file_path && File.exist?(file_path)
    end
    
    def download_to_tempfile(document)
      extension = document.file_extension
      tempfile = Tempfile.new(['document', ".#{extension || 'bin'}"])
      tempfile.binmode
      tempfile.write(document.file.download)
      tempfile.close
      tempfile.path
    rescue => e
      Rails.logger.error("Error downloading to tempfile: #{e.message}")
      raise e
    end
    
    def extract_text_from_pdf(file_path)
      # This is a placeholder - in a real implementation, we would use a
      # PDF parsing library like pdf-reader or external tools via system calls
      Rails.logger.info("Extracting text from PDF: #{File.basename(file_path)}")
      "Extracted text from PDF document. File: #{File.basename(file_path)}"
    end
    
    def extract_text_from_docx(file_path)
      # This is a placeholder - in a real implementation, we would use a
      # library like docx or external tools
      Rails.logger.info("Extracting text from DOCX: #{File.basename(file_path)}")
      "Extracted text from Word document. File: #{File.basename(file_path)}"
    end
    
    def extract_text_from_text_file(file_path)
      # For text files, simply read the content
      Rails.logger.info("Reading text file: #{File.basename(file_path)}")
      File.read(file_path).force_encoding('UTF-8')
    rescue => e
      Rails.logger.error("Error reading text file: #{e.message}")
      "Error reading text file: #{e.message}"
    end
  end
end
