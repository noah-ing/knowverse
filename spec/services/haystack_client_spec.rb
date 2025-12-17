require 'rails_helper'

RSpec.describe HaystackClient do
  let(:client) { described_class.new }
  let(:base_url) { 'http://localhost:8000' }
  let(:organization) { create(:organization) }

  before do
    stub_request(:any, /localhost:8000/).to_return(
      status: 200,
      body: '{"status": "ok"}',
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  describe '#initialize' do
    it 'uses default configuration' do
      expect(client.instance_variable_get(:@config)[:base_url]).to eq(base_url)
      expect(client.instance_variable_get(:@config)[:timeout]).to eq(30)
    end

    it 'accepts custom configuration' do
      custom_client = described_class.new(timeout: 60)
      expect(custom_client.instance_variable_get(:@config)[:timeout]).to eq(60)
    end
  end

  describe '#health_check' do
    it 'returns health status on success' do
      stub_request(:get, "#{base_url}/health")
        .to_return(
          status: 200,
          body: '{"status": "healthy", "version": "1.0.0"}',
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.health_check
      expect(result['status']).to eq('healthy')
    end

    it 'returns error status on failure' do
      stub_request(:get, "#{base_url}/health")
        .to_raise(Errno::ECONNREFUSED)

      result = client.health_check
      expect(result[:status]).to eq('error')
    end
  end

  describe '#search' do
    it 'performs search with query and organization' do
      stub_request(:post, "#{base_url}/search")
        .with(
          body: hash_including(
            'query' => 'test query',
            'filters' => { 'organization_id' => organization.id }
          )
        )
        .to_return(
          status: 200,
          body: '{"results": [], "total": 0}',
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.search(query: 'test query', organization_id: organization.id)
      expect(result).to include('results')
    end

    it 'passes limit parameter' do
      stub_request(:post, "#{base_url}/search")
        .with(body: hash_including('top_k' => 20))
        .to_return(
          status: 200,
          body: '{"results": []}',
          headers: { 'Content-Type' => 'application/json' }
        )

      client.search(query: 'test', organization_id: organization.id, limit: 20)
    end
  end

  describe '#hybrid_search' do
    it 'performs hybrid search with weights' do
      stub_request(:post, "#{base_url}/hybrid-search")
        .with(
          body: hash_including(
            'query' => 'hybrid test',
            'vector_weight' => 0.8,
            'keyword_weight' => 0.2
          )
        )
        .to_return(
          status: 200,
          body: '{"results": [], "vector_score": 0.9, "keyword_score": 0.7}',
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.hybrid_search(
        query: 'hybrid test',
        organization_id: organization.id,
        vector_weight: 0.8,
        keyword_weight: 0.2
      )
      expect(result).to include('results')
    end
  end

  describe '#generate_embeddings' do
    before do
      # Mock the cache manager to avoid cache lookup
      allow(EmbeddingCache::CacheManager).to receive(:instance).and_return(
        double('CacheManager', fetch: nil)
      )
    end

    it 'generates embeddings for text' do
      embedding = Array.new(768) { rand }
      stub_request(:post, "#{base_url}/embeddings/generate")
        .to_return(
          status: 200,
          body: { embedding: embedding, dimension: 768 }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.generate_embeddings('test text', use_cache: false)
      expect(result).to be_an(Array)
      expect(result.size).to eq(768)
    end

    it 'accepts model_name parameter' do
      stub_request(:post, "#{base_url}/embeddings/generate")
        .with(body: hash_including('model_name' => 'large'))
        .to_return(
          status: 200,
          body: { embedding: Array.new(1024) { 0 } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      client.generate_embeddings('test', model_name: 'large', use_cache: false)
    end
  end

  describe '#generate_answer' do
    it 'generates RAG answer' do
      stub_request(:post, "#{base_url}/rag/answer")
        .to_return(
          status: 200,
          body: {
            answer: 'This is the answer based on the documents.',
            sources: [{ document_id: 1, relevance: 0.95 }],
            confidence: 0.88
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.generate_answer('What is machine learning?', organization.id)
      expect(result).to be_a(HaystackClient::Response)
      expect(result.success?).to be true
      expect(result.data['answer']).to include('answer')
    end

    it 'handles generation options' do
      stub_request(:post, "#{base_url}/rag/answer")
        .with(
          body: hash_including(
            'generation_options' => hash_including(
              'temperature' => 0.5,
              'max_tokens' => 1000
            )
          )
        )
        .to_return(
          status: 200,
          body: { answer: 'Response' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      client.generate_answer(
        'Question',
        organization.id,
        temperature: 0.5,
        max_tokens: 1000
      )
    end
  end

  describe '#list_llm_providers' do
    it 'returns available LLM providers' do
      stub_request(:get, "#{base_url}/rag/providers")
        .to_return(
          status: 200,
          body: [
            { id: 'openai', name: 'OpenAI GPT-4', available: true },
            { id: 'anthropic', name: 'Claude', available: true }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.list_llm_providers
      expect(result).to be_a(HaystackClient::Response)
      expect(result.success?).to be true
    end
  end

  describe '#detect_domain' do
    it 'detects domain from query' do
      stub_request(:post, "#{base_url}/domains/detect")
        .to_return(
          status: 200,
          body: {
            domain: 'technology',
            confidence: 0.92,
            alternatives: [
              { domain: 'science', confidence: 0.78 }
            ]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.detect_domain('neural network architectures', organization.id)
      expect(result).to be_a(HaystackClient::Response)
      expect(result.data['domain']).to eq('technology')
    end
  end

  describe '#extract_pdf' do
    it 'extracts text from PDF' do
      stub_request(:post, "#{base_url}/extract/pdf")
        .to_return(
          status: 200,
          body: {
            success: true,
            content: 'Extracted PDF content',
            metadata: { page_count: 10 }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.extract_pdf('fake pdf content', filename: 'test.pdf')
      expect(result).to be_a(HaystackClient::Response)
      expect(result.data['content']).to eq('Extracted PDF content')
    end
  end

  describe '#extract_excel' do
    it 'extracts text from Excel' do
      stub_request(:post, "#{base_url}/extract/excel")
        .to_return(
          status: 200,
          body: {
            success: true,
            content: 'Sheet1: Data...',
            metadata: { sheet_count: 3 }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.extract_excel('fake excel content', filename: 'data.xlsx')
      expect(result).to be_a(HaystackClient::Response)
    end
  end

  describe '#extract_docx' do
    it 'extracts text from DOCX' do
      stub_request(:post, "#{base_url}/extract/docx")
        .to_return(
          status: 200,
          body: {
            success: true,
            content: 'Document content here',
            metadata: { paragraph_count: 15 }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.extract_docx('fake docx content', filename: 'doc.docx')
      expect(result).to be_a(HaystackClient::Response)
    end
  end

  describe '#chunk_text' do
    it 'chunks text for embedding' do
      stub_request(:post, "#{base_url}/chunk")
        .to_return(
          status: 200,
          body: {
            chunks: [
              { content: 'Chunk 1', start: 0, end: 100 },
              { content: 'Chunk 2', start: 80, end: 180 }
            ],
            total_chunks: 2
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.chunk_text('Long text content...', chunk_size: 512)
      expect(result).to be_a(HaystackClient::Response)
      expect(result.data['chunks'].size).to eq(2)
    end
  end

  describe '#dimension_reduction' do
    it 'reduces vector dimensions' do
      vectors = [Array.new(768) { rand }, Array.new(768) { rand }]

      stub_request(:post, "#{base_url}/visualization/dimension-reduction")
        .to_return(
          status: 200,
          body: {
            reduced_vectors: [[0.1, 0.2], [0.3, 0.4]],
            algorithm: 'tsne'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.dimension_reduction(vectors: vectors, algorithm: 'tsne')
      expect(result).to be_a(HaystackClient::Response)
      expect(result.success?).to be true
    end
  end

  describe '#cluster_documents' do
    it 'clusters document embeddings' do
      stub_request(:post, "#{base_url}/visualization/clustering")
        .to_return(
          status: 200,
          body: {
            clusters: { '0' => [1, 2], '1' => [3, 4] },
            centroids: [[0.5, 0.5], [0.8, 0.2]]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.cluster_documents(
        vectors: [Array.new(768) { rand }],
        document_ids: [1, 2, 3, 4],
        algorithm: 'kmeans'
      )
      expect(result).to be_a(HaystackClient::Response)
    end
  end

  describe 'retry behavior' do
    it 'retries on failure with exponential backoff' do
      call_count = 0

      stub_request(:get, "#{base_url}/health")
        .to_return do |_request|
          call_count += 1
          if call_count < 3
            raise Errno::ECONNRESET
          else
            {
              status: 200,
              body: '{"status": "healthy"}',
              headers: { 'Content-Type' => 'application/json' }
            }
          end
        end

      # Allow retries to happen quickly in tests
      allow(client).to receive(:sleep)

      result = client.health_check
      expect(result['status']).to eq('healthy')
      expect(call_count).to eq(3)
    end
  end

  describe HaystackClient::Response do
    describe '#success?' do
      it 'returns true for successful response' do
        response = HaystackClient::Response.new(true, { data: 'test' }, nil)
        expect(response.success?).to be true
      end

      it 'returns false for failed response' do
        response = HaystackClient::Response.new(false, nil, 'Error message')
        expect(response.success?).to be false
      end
    end

    describe '#data' do
      it 'returns the data' do
        response = HaystackClient::Response.new(true, { key: 'value' }, nil)
        expect(response.data[:key]).to eq('value')
      end
    end

    describe '#error' do
      it 'returns the error message' do
        response = HaystackClient::Response.new(false, nil, 'Something went wrong')
        expect(response.error).to eq('Something went wrong')
      end
    end
  end
end
