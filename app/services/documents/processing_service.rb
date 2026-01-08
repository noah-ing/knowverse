# frozen_string_literal: true

module Documents
  # Handles document creation and processing logic
  # Extracted from DocumentsController for separation of concerns
  class ProcessingService
    attr_reader :organization

    def initialize(organization)
      @organization = organization
    end

    # Create a document with initial pending status
    def create_document(params)
      document = organization.documents.new(params)
      document.status = 'pending'
      document.embedding_status = 'pending'
      document
    end

    # Process a single document synchronously (text extraction + embedding)
    def process_document_sync(document)
      Rails.logger.info("=" * 50)
      Rails.logger.info("DOCUMENT CREATE: Processing document #{document.id} - #{document.title}")
      Rails.logger.info("Rails.env = #{Rails.env}, development? = #{Rails.env.development?}")

      # Run text extraction
      Rails.logger.info("Starting text extraction...")
      DocumentProcessing::TextExtractionWorker.new.perform(document.id)
      document.reload
      Rails.logger.info("Text extraction complete. Status: #{document.status}")

      if document.status == 'processed'
        # Run embedding generation
        Rails.logger.info("Starting embedding generation...")
        DocumentProcessing::EmbeddingGenerationWorker.new.perform(document.id)
        document.reload
        Rails.logger.info("Embedding generation complete. Embedding status: #{document.embedding_status}")
      else
        Rails.logger.warn("Skipping embedding - document status is #{document.status}, not 'processed'")
      end

      Rails.logger.info("=" * 50)
      document
    end

    # Generate a notice message based on document processing status
    def processing_notice(document)
      if document.embedding_status == 'processed'
        'Document uploaded and processed successfully!'
      elsif document.status == 'processed'
        'Document uploaded and text extracted. Embeddings processing...'
      else
        'Document uploaded but processing had issues. Check the document status.'
      end
    end

    # Handle file upload and create documents from uploaded files
    def upload_files(files)
      return [] if files.blank?

      valid_files = files.reject { |f| f.blank? || !f.respond_to?(:original_filename) }
      saved_documents = []

      valid_files.each do |file|
        document = create_document_from_file(file)
        saved_documents << document if document.save
      end

      saved_documents
    end

    # Queue documents for async processing
    def queue_for_processing(documents)
      documents.each do |document|
        DocumentProcessing::TextExtractionWorker.perform_later(document.id)
      end
    end

    # Process documents in parallel (synchronous, waits for completion)
    def process_documents_parallel(documents)
      return { success: 0, failed: 0 } if documents.empty?

      results = Concurrent::Hash.new

      pool = Concurrent::FixedThreadPool.new([documents.size, 4].min)
      latch = Concurrent::CountDownLatch.new(documents.size)

      documents.each do |document|
        pool.post do
          process_document_in_thread(document, results, latch)
        end
      end

      # Wait for all documents to complete (max 5 minutes)
      latch.wait(300)
      pool.shutdown

      compile_results(results)
    end

    private

    def create_document_from_file(file)
      extension = File.extname(file.original_filename).delete('.').downcase

      document = organization.documents.new(
        title: file.original_filename.sub(/\.[^.]+$/, '').gsub(/[_-]/, ' '),
        file_type: extension.presence || 'txt',
        status: 'pending',
        embedding_status: 'pending'
      )

      document.file.attach(file)
      document
    end

    def process_document_in_thread(document, results, latch)
      Rails.logger.info("Starting processing for document #{document.id}: #{document.title}")

      DocumentProcessing::TextExtractionWorker.new.perform(document.id)
      document.reload

      if document.status == 'processed'
        DocumentProcessing::EmbeddingGenerationWorker.new.perform(document.id)
        document.reload
        results[document.id] = document.embedding_status == 'processed' ? :success : :partial
      else
        results[document.id] = :failed
      end

      Rails.logger.info("Document #{document.id} processing complete: #{results[document.id]}")
    rescue StandardError => e
      Rails.logger.error("Document #{document.id} processing failed: #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      results[document.id] = :failed
      document.update(status: 'error') rescue nil
    ensure
      latch.count_down
    end

    def compile_results(results)
      {
        success: results.values.count { |v| v == :success },
        partial: results.values.count { |v| v == :partial },
        failed: results.values.count { |v| v == :failed }
      }
    end
  end
end
