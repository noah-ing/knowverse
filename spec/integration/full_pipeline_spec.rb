# frozen_string_literal: true

# Full Pipeline Integration Tests
#
# These tests validate that the entire document → embedding → search pipeline
# works correctly end-to-end. They catch integration issues that unit tests miss.
#
# Run: bundle exec rspec spec/integration/full_pipeline_spec.rb

require 'rails_helper'

RSpec.describe 'Full Document Pipeline Integration', type: :integration do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }

  describe 'Document Ingestion → Search Flow' do
    context 'with text documents' do
      it 'processes a text document and makes it searchable' do
        # 1. Create document
        document = create(:document,
                          organization: organization,
                          content: 'Ruby on Rails is a web application framework written in Ruby. It follows the MVC pattern.',
                          status: 'pending')

        # 2. Process document (sync for testing)
        processor = DocumentProcessing::TextExtractionWorker.new
        processor.perform(document.id)
        document.reload

        expect(document.content).to be_present
        expect(document.status).to eq('processed')

        # 3. Generate embedding (requires Haystack service)
        skip 'Haystack service not running' unless haystack_available?

        embedding_worker = DocumentProcessing::EmbeddingGenerationWorker.new
        embedding_worker.perform(document.id)
        document.reload

        expect(document.vector_embeddings).to be_present
        embedding = document.vector_embeddings.first
        expect(embedding.embedding).to be_a(Array)
        expect(embedding.embedding.length).to eq(768) # Default dimension

        # 4. Search should find the document
        results = SearchRouter.route_query(
          'Rails web framework Ruby',
          organization.id,
          provider: :pgvector_cosine,
          limit: 10
        )

        expect(results).to be_present
        document_ids = results.map { |r| r[:document_id] }
        expect(document_ids).to include(document.id)
      end
    end

    context 'with PDF documents', :requires_haystack do
      it 'extracts text from PDF and makes it searchable' do
        skip 'Haystack service not running' unless haystack_available?

        # Create a document with PDF content
        pdf_content = File.read(Rails.root.join('spec/fixtures/files/sample.pdf'))
        document = create(:document,
                          organization: organization,
                          file_name: 'sample.pdf',
                          content_type: 'application/pdf',
                          status: 'pending')
        document.file.attach(io: StringIO.new(pdf_content), filename: 'sample.pdf')

        # Process
        processor = DocumentProcessing::TextExtractionWorker.new
        processor.perform(document.id)
        document.reload

        # Should have extracted real text, not placeholder
        expect(document.content).not_to include('Extracted text from PDF document')
        expect(document.content.length).to be > 100
      end
    end
  end

  describe 'Search Provider Correctness' do
    before do
      skip 'Haystack service not running' unless haystack_available?

      # Create test documents with known content
      @docs = [
        create(:document, organization: organization, content: 'Machine learning algorithms process data'),
        create(:document, organization: organization, content: 'Deep neural networks for image recognition'),
        create(:document, organization: organization, content: 'Ruby programming language syntax guide'),
        create(:document, organization: organization, content: 'PostgreSQL database optimization techniques'),
        create(:document, organization: organization, content: 'Vector similarity search using embeddings')
      ]

      # Generate embeddings for all
      @docs.each do |doc|
        DocumentProcessing::EmbeddingGenerationWorker.new.perform(doc.id)
      end
    end

    # Test standard search modes (semantic, keyword, hybrid)
    %i[semantic keyword hybrid].each do |mode|
      context "with #{mode} mode" do
        it 'returns relevant results for semantic query' do
          results = SearchRouter.route_query(
            'neural network deep learning',
            organization.id,
            mode: mode,
            limit: 5
          )

          expect(results).to be_an(Array)
          expect(results.length).to be <= 5

          # The neural networks document should be in top results
          top_doc_ids = results.first(3).map { |r| r[:document_id] }
          neural_doc = @docs.find { |d| d.content.include?('neural networks') }
          expect(top_doc_ids).to include(neural_doc.id)
        end

        it 'returns results with required fields' do
          results = SearchRouter.route_query('database', organization.id, mode: mode)

          results.each do |result|
            expect(result).to have_key(:document_id)
            expect(result).to have_key(:score)
            expect(result[:score]).to be_a(Numeric)
          end
        end
      end
    end
  end

  describe 'Multi-Tenant Isolation' do
    it 'does not return documents from other organizations' do
      skip 'Haystack service not running' unless haystack_available?

      # Create documents in two different organizations
      other_org = create(:organization)

      doc_org1 = create(:document, organization: organization, content: 'Secret project alpha details')
      doc_org2 = create(:document, organization: other_org, content: 'Secret project alpha details')

      # Generate embeddings
      DocumentProcessing::EmbeddingGenerationWorker.new.perform(doc_org1.id)
      DocumentProcessing::EmbeddingGenerationWorker.new.perform(doc_org2.id)

      # Search from org1 should only find org1's document
      results = SearchRouter.route_query('project alpha', organization.id, limit: 10)

      result_doc_ids = results.map { |r| r[:document_id] }
      expect(result_doc_ids).to include(doc_org1.id)
      expect(result_doc_ids).not_to include(doc_org2.id)
    end
  end

  describe 'Qdrant Integration (when available)' do
    before do
      skip 'Qdrant not available' unless qdrant_available?
    end

    it 'indexes documents in Qdrant' do
      skip 'Haystack service not running' unless haystack_available?

      document = create(:document,
                        organization: organization,
                        content: 'Test document for Qdrant indexing')

      # Generate embedding and index
      DocumentProcessing::EmbeddingGenerationWorker.new.perform(document.id)
      document.reload

      # Document should be indexed in Qdrant
      expect(document.indexed_in_hnsw).to be true
    end

    it 'performs semantic search via Qdrant' do
      skip 'Haystack service not running' unless haystack_available?

      # Create and index a document
      document = create(:document,
                        organization: organization,
                        content: 'Quantum computing uses qubits for parallel processing')

      DocumentProcessing::EmbeddingGenerationWorker.new.perform(document.id)

      # Search should use Qdrant
      results = SearchRouter.route_query(
        'quantum parallel processing',
        organization.id,
        mode: :semantic,
        limit: 10
      )

      expect(results).to be_present
      expect(results.first[:document_id]).to eq(document.id)
    end
  end

  private

  def haystack_available?
    response = Net::HTTP.get_response(URI('http://localhost:8000/health'))
    response.is_a?(Net::HTTPSuccess)
  rescue Errno::ECONNREFUSED, SocketError
    false
  end

  def qdrant_available?
    response = Net::HTTP.get_response(URI('http://localhost:6333/readiness'))
    response.is_a?(Net::HTTPSuccess)
  rescue Errno::ECONNREFUSED, SocketError
    false
  end
end
