module DocumentProcessing
  class TextExtractionWorker < ActiveJob::Base
    queue_as :document_processing
    
    # Retry options for more resilience (exponential backoff: 3s, 18s, 83s)
    retry_on StandardError, wait: ->(attempt) { (attempt ** 4) + 2 }, attempts: 3
    
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

    # Initialize Haystack client for document extraction
    def haystack_client
      @haystack_client ||= HaystackClient.new
    end

    def extract_text(document)
      file_content = document.file.download
      filename = document.file.filename.to_s
      extension = document.file_extension

      Rails.logger.info("Extracting text from #{extension} file: #{filename}")

      extracted_text = case extension
      when 'pdf'
        extract_text_from_pdf(file_content, filename)
      when 'docx', 'doc'
        extract_text_from_docx(file_content, filename)
      when 'xlsx', 'xls'
        extract_text_from_excel(file_content, filename)
      when 'txt', 'md', 'rtf'
        extract_text_from_text_file(file_content)
      else
        # Try auto-detection via Haystack service
        extract_text_auto(file_content, filename)
      end

      # Validate extraction result
      if extracted_text.blank?
        Rails.logger.warn("Empty text extracted from document #{document.id}")
        raise ExtractionError, "No text content could be extracted from document"
      end

      extracted_text
    rescue ExtractionError => e
      Rails.logger.error("Extraction error for document #{document.id}: #{e.message}")
      raise e
    rescue => e
      Rails.logger.error("Unexpected error extracting text from document #{document.id}: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
      raise ExtractionError, "Text extraction failed: #{e.message}"
    end

    # Extract text from PDF using Haystack service (pdfplumber/pypdf)
    def extract_text_from_pdf(file_content, filename)
      Rails.logger.info("Extracting PDF via Haystack service: #{filename}")

      response = haystack_client.extract_pdf(
        file_content,
        filename: filename,
        extract_tables: true,
        preserve_layout: true
      )

      if response.success? && response.data['content'].present?
        log_extraction_metadata(response.data, 'PDF')
        response.data['content']
      else
        error_msg = response.error || response.data&.dig('errors')&.join(', ') || 'Unknown error'
        raise ExtractionError, "PDF extraction failed: #{error_msg}"
      end
    end

    # Extract text from DOCX using Haystack service (python-docx)
    def extract_text_from_docx(file_content, filename)
      Rails.logger.info("Extracting DOCX via Haystack service: #{filename}")

      response = haystack_client.extract_docx(
        file_content,
        filename: filename,
        extract_tables: true,
        preserve_structure: true
      )

      if response.success? && response.data['content'].present?
        log_extraction_metadata(response.data, 'DOCX')
        response.data['content']
      else
        error_msg = response.error || response.data&.dig('errors')&.join(', ') || 'Unknown error'
        raise ExtractionError, "DOCX extraction failed: #{error_msg}"
      end
    end

    # Extract text from Excel using Haystack service (fastexcel/calamine)
    def extract_text_from_excel(file_content, filename)
      Rails.logger.info("Extracting Excel via Haystack service: #{filename}")

      response = haystack_client.extract_excel(
        file_content,
        filename: filename,
        max_preview_rows: 1000,  # More rows for comprehensive extraction
        include_empty_sheets: false
      )

      if response.success? && response.data['content'].present?
        log_extraction_metadata(response.data, 'Excel')
        response.data['content']
      else
        error_msg = response.error || response.data&.dig('errors')&.join(', ') || 'Unknown error'
        raise ExtractionError, "Excel extraction failed: #{error_msg}"
      end
    end

    # Extract text from plain text files (local processing)
    def extract_text_from_text_file(file_content)
      Rails.logger.info("Processing plain text file locally")

      # Try UTF-8 first, fall back to Latin-1
      begin
        file_content.force_encoding('UTF-8')
        unless file_content.valid_encoding?
          file_content = file_content.encode('UTF-8', 'ISO-8859-1', invalid: :replace, undef: :replace)
        end
      rescue Encoding::InvalidByteSequenceError
        file_content = file_content.encode('UTF-8', 'ISO-8859-1', invalid: :replace, undef: :replace)
      end

      file_content
    end

    # Auto-detect file type and extract via Haystack service
    def extract_text_auto(file_content, filename)
      Rails.logger.info("Auto-detecting and extracting: #{filename}")

      response = haystack_client.extract_auto(file_content, filename: filename)

      if response.success? && response.data['content'].present?
        detected_type = response.data.dig('metadata', 'detected_type') || 'unknown'
        log_extraction_metadata(response.data, detected_type.upcase)
        response.data['content']
      else
        error_msg = response.error || response.data&.dig('errors')&.join(', ') || 'Unknown error'
        raise ExtractionError, "Auto extraction failed: #{error_msg}"
      end
    end

    # Log extraction metadata for debugging and monitoring
    def log_extraction_metadata(data, doc_type)
      metadata = data['metadata'] || {}
      processing_time = data['processing_time'] || 0
      total_chars = data['total_chars'] || 0
      total_words = data['total_words'] || 0
      extraction_method = data['extraction_method'] || 'unknown'

      Rails.logger.info(
        "#{doc_type} extraction complete: " \
        "#{total_words} words, #{total_chars} chars, " \
        "method=#{extraction_method}, time=#{processing_time.round(3)}s"
      )

      # Log additional metadata based on document type
      case doc_type
      when 'PDF'
        pages = metadata['total_pages'] || 0
        tables = metadata['total_tables'] || 0
        Rails.logger.info("  PDF details: #{pages} pages, #{tables} tables")
      when 'DOCX'
        paragraphs = metadata['total_paragraphs'] || 0
        tables = metadata['total_tables'] || 0
        Rails.logger.info("  DOCX details: #{paragraphs} paragraphs, #{tables} tables")
      when 'EXCEL'
        sheets = metadata['total_sheets'] || 0
        rows = metadata['total_rows'] || 0
        Rails.logger.info("  Excel details: #{sheets} sheets, #{rows} total rows")
      end
    end

    # Custom error class for extraction failures
    class ExtractionError < StandardError; end
  end
end
