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

    SearchRouter::PROVIDERS.keys.each do |provider|
      context "with #{provider} provider" do
        it 'returns relevant results for semantic query' do
          skip 'Provider requires external service' if provider_requires_external?(provider)

          results = SearchRouter.route_query(
            'neural network deep learning',
            organization.id,
            provider: provider,
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
          skip 'Provider requires external service' if provider_requires_external?(provider)

          results = SearchRouter.route_query('database', organization.id, provider: provider)

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

  describe 'Vector Operations Correctness' do
    it 'calculates correct Euclidean distance' do
      vec_a = [1.0, 0.0, 0.0]
      vec_b = [0.0, 1.0, 0.0]

      # Expected: sqrt(1^2 + 1^2) = sqrt(2) ≈ 1.414
      require_relative '../../lib/knowverse_vector'
      distance = KnowverseVector::Distance.euclidean(vec_a, vec_b)

      expect(distance).to be_within(0.001).of(Math.sqrt(2))
    end

    it 'calculates correct cosine similarity' do
      vec_a = [1.0, 0.0]
      vec_b = [1.0, 0.0]
      vec_c = [0.0, 1.0]

      require_relative '../../lib/knowverse_vector'

      # Same direction = 1.0
      expect(KnowverseVector::Distance.cosine_similarity(vec_a, vec_b)).to be_within(0.001).of(1.0)

      # Orthogonal = 0.0
      expect(KnowverseVector::Distance.cosine_similarity(vec_a, vec_c)).to be_within(0.001).of(0.0)
    end

    it 'finds correct nearest neighbors' do
      require_relative '../../lib/knowverse_vector'

      query = [1.0, 0.0, 0.0]
      candidates = [
        [0.9, 0.1, 0.0],  # Closest to query
        [0.0, 1.0, 0.0],  # Orthogonal
        [0.5, 0.5, 0.0],  # Middle
        [-1.0, 0.0, 0.0]  # Opposite
      ]

      results = KnowverseVector::Batch.find_nearest(query, candidates, 2, 'euclidean')

      # Index 0 should be closest
      expect(results.first[0]).to eq(0)
    end
  end

  describe 'Distributed Search (when enabled)' do
    before do
      skip 'Distributed mode not configured' unless distributed_mode_enabled?
    end

    it 'aggregates results from multiple shards' do
      # This test validates the RemoteShardClient and DistributedSearchService
      results = SearchRouter.route_query(
        'test query',
        organization.id,
        provider: :distributed,
        limit: 10
      )

      expect(results).to be_an(Array)
      # Results should have shard metadata in distributed mode
    end
  end

  private

  def haystack_available?
    response = Net::HTTP.get_response(URI('http://localhost:8000/health'))
    response.is_a?(Net::HTTPSuccess)
  rescue Errno::ECONNREFUSED, SocketError
    false
  end

  def provider_requires_external?(provider)
    %i[haystack distributed].include?(provider)
  end

  def distributed_mode_enabled?
    ENV['DISTRIBUTED_MODE'] == 'true' || Rails.configuration.respond_to?(:distributed_enabled)
  end
end
