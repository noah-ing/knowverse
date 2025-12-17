require 'rails_helper'

RSpec.describe VectorStore::QdrantClusterAdapter do
  let(:adapter) { described_class.new }
  let(:base_url) { 'http://localhost:6333' }
  let(:collection_name) { 'test_collection' }

  before do
    stub_request(:any, /localhost:6333/).to_return(
      status: 200,
      body: '{"status": "ok"}',
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  describe '#initialize' do
    it 'uses default Qdrant URL from environment' do
      expect(adapter.instance_variable_get(:@base_url)).to include('6333')
    end

    it 'accepts custom configuration' do
      custom_adapter = described_class.new(url: 'http://custom:6333')
      expect(custom_adapter.instance_variable_get(:@base_url)).to eq('http://custom:6333')
    end
  end

  describe '#healthy?' do
    it 'returns true when Qdrant is healthy' do
      stub_request(:get, "#{base_url}/health")
        .to_return(
          status: 200,
          body: '{"title": "qdrant - vector search engine", "version": "1.12.4"}',
          headers: { 'Content-Type' => 'application/json' }
        )

      expect(adapter.healthy?).to be true
    end

    it 'returns false when Qdrant is unreachable' do
      stub_request(:get, "#{base_url}/health")
        .to_raise(Errno::ECONNREFUSED)

      expect(adapter.healthy?).to be false
    end
  end

  describe '#create_collection' do
    it 'creates a collection with specified parameters' do
      stub_request(:put, "#{base_url}/collections/#{collection_name}")
        .with(
          body: hash_including(
            'vectors' => hash_including(
              'size' => 768,
              'distance' => 'Cosine'
            )
          )
        )
        .to_return(
          status: 200,
          body: '{"result": true, "status": "ok"}',
          headers: { 'Content-Type' => 'application/json' }
        )

      result = adapter.create_collection(
        name: collection_name,
        vector_size: 768,
        distance: 'Cosine'
      )

      expect(result).to be_truthy
    end

    it 'configures HNSW index parameters' do
      stub_request(:put, "#{base_url}/collections/#{collection_name}")
        .with(
          body: hash_including(
            'hnsw_config' => hash_including(
              'm' => 16,
              'ef_construct' => 100
            )
          )
        )
        .to_return(
          status: 200,
          body: '{"result": true}',
          headers: { 'Content-Type' => 'application/json' }
        )

      adapter.create_collection(
        name: collection_name,
        vector_size: 768,
        hnsw_config: { m: 16, ef_construct: 100 }
      )
    end
  end

  describe '#delete_collection' do
    it 'deletes a collection' do
      stub_request(:delete, "#{base_url}/collections/#{collection_name}")
        .to_return(
          status: 200,
          body: '{"result": true}',
          headers: { 'Content-Type' => 'application/json' }
        )

      result = adapter.delete_collection(name: collection_name)
      expect(result).to be_truthy
    end
  end

  describe '#collection_info' do
    it 'returns collection information' do
      stub_request(:get, "#{base_url}/collections/#{collection_name}")
        .to_return(
          status: 200,
          body: {
            result: {
              status: 'green',
              vectors_count: 1000,
              points_count: 1000,
              config: {
                params: { vectors: { size: 768, distance: 'Cosine' } }
              }
            }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      info = adapter.collection_info(name: collection_name)
      expect(info[:vectors_count]).to eq(1000)
      expect(info[:status]).to eq('green')
    end

    it 'raises CollectionNotFoundError for missing collection' do
      stub_request(:get, "#{base_url}/collections/#{collection_name}")
        .to_return(
          status: 404,
          body: '{"status": {"error": "Collection not found"}}',
          headers: { 'Content-Type' => 'application/json' }
        )

      expect {
        adapter.collection_info(name: collection_name)
      }.to raise_error(VectorStore::QdrantClusterAdapter::CollectionNotFoundError)
    end
  end

  describe '#upsert' do
    let(:points) do
      [
        {
          id: 1,
          vector: Array.new(768) { rand },
          payload: { title: 'Document 1', file_type: 'pdf' }
        },
        {
          id: 2,
          vector: Array.new(768) { rand },
          payload: { title: 'Document 2', file_type: 'docx' }
        }
      ]
    end

    it 'upserts points to collection' do
      stub_request(:put, "#{base_url}/collections/#{collection_name}/points")
        .with(
          body: hash_including(
            'points' => array_including(
              hash_including('id' => 1),
              hash_including('id' => 2)
            )
          )
        )
        .to_return(
          status: 200,
          body: '{"result": {"status": "completed"}}',
          headers: { 'Content-Type' => 'application/json' }
        )

      result = adapter.upsert(collection: collection_name, points: points)
      expect(result[:status]).to eq('completed')
    end

    it 'handles batch operations efficiently' do
      large_batch = Array.new(100) do |i|
        {
          id: i,
          vector: Array.new(768) { rand },
          payload: { title: "Document #{i}" }
        }
      end

      stub_request(:put, "#{base_url}/collections/#{collection_name}/points")
        .to_return(
          status: 200,
          body: '{"result": {"status": "completed"}}',
          headers: { 'Content-Type' => 'application/json' }
        )

      result = adapter.upsert(collection: collection_name, points: large_batch)
      expect(result[:status]).to eq('completed')
    end
  end

  describe '#search' do
    let(:query_vector) { Array.new(768) { rand } }

    it 'performs vector search' do
      stub_request(:post, "#{base_url}/collections/#{collection_name}/points/search")
        .with(
          body: hash_including(
            'vector' => query_vector,
            'limit' => 10
          )
        )
        .to_return(
          status: 200,
          body: {
            result: [
              { id: 1, score: 0.95, payload: { title: 'Doc 1' } },
              { id: 2, score: 0.88, payload: { title: 'Doc 2' } }
            ]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      results = adapter.search(
        collection: collection_name,
        vector: query_vector,
        limit: 10
      )

      expect(results.size).to eq(2)
      expect(results.first[:score]).to eq(0.95)
    end

    it 'applies score threshold filter' do
      stub_request(:post, "#{base_url}/collections/#{collection_name}/points/search")
        .with(body: hash_including('score_threshold' => 0.8))
        .to_return(
          status: 200,
          body: { result: [] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      adapter.search(
        collection: collection_name,
        vector: query_vector,
        score_threshold: 0.8
      )
    end

    it 'applies metadata filters' do
      stub_request(:post, "#{base_url}/collections/#{collection_name}/points/search")
        .with(
          body: hash_including(
            'filter' => hash_including(
              'must' => array_including(
                hash_including('key' => 'file_type', 'match' => { 'value' => 'pdf' })
              )
            )
          )
        )
        .to_return(
          status: 200,
          body: { result: [] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      adapter.search(
        collection: collection_name,
        vector: query_vector,
        filter: { file_type: 'pdf' }
      )
    end

    it 'returns with_payload when requested' do
      stub_request(:post, "#{base_url}/collections/#{collection_name}/points/search")
        .with(body: hash_including('with_payload' => true))
        .to_return(
          status: 200,
          body: {
            result: [{ id: 1, score: 0.9, payload: { title: 'Test' } }]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      results = adapter.search(
        collection: collection_name,
        vector: query_vector,
        with_payload: true
      )

      expect(results.first[:payload]).to include(title: 'Test')
    end
  end

  describe '#delete' do
    it 'deletes points by ID' do
      stub_request(:post, "#{base_url}/collections/#{collection_name}/points/delete")
        .with(body: hash_including('points' => [1, 2, 3]))
        .to_return(
          status: 200,
          body: '{"result": {"status": "completed"}}',
          headers: { 'Content-Type' => 'application/json' }
        )

      result = adapter.delete(collection: collection_name, points: [1, 2, 3])
      expect(result[:status]).to eq('completed')
    end

    it 'deletes points by filter' do
      stub_request(:post, "#{base_url}/collections/#{collection_name}/points/delete")
        .with(
          body: hash_including(
            'filter' => hash_including(
              'must' => array_including(
                hash_including('key' => 'status', 'match' => { 'value' => 'archived' })
              )
            )
          )
        )
        .to_return(
          status: 200,
          body: '{"result": {"status": "completed"}}',
          headers: { 'Content-Type' => 'application/json' }
        )

      adapter.delete(
        collection: collection_name,
        filter: { status: 'archived' }
      )
    end
  end

  describe '#scroll' do
    it 'retrieves points with pagination' do
      stub_request(:post, "#{base_url}/collections/#{collection_name}/points/scroll")
        .to_return(
          status: 200,
          body: {
            result: {
              points: [
                { id: 1, payload: { title: 'Doc 1' } },
                { id: 2, payload: { title: 'Doc 2' } }
              ],
              next_page_offset: 'abc123'
            }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = adapter.scroll(collection: collection_name, limit: 100)
      expect(result[:points].size).to eq(2)
      expect(result[:next_page_offset]).to eq('abc123')
    end
  end

  describe 'error handling' do
    it 'raises QdrantError on server error' do
      stub_request(:get, "#{base_url}/collections/#{collection_name}")
        .to_return(
          status: 500,
          body: '{"status": {"error": "Internal server error"}}',
          headers: { 'Content-Type' => 'application/json' }
        )

      expect {
        adapter.collection_info(name: collection_name)
      }.to raise_error(VectorStore::QdrantClusterAdapter::QdrantError)
    end

    it 'raises QdrantError on connection failure' do
      stub_request(:get, "#{base_url}/collections/#{collection_name}")
        .to_raise(Errno::ECONNREFUSED)

      expect {
        adapter.collection_info(name: collection_name)
      }.to raise_error(VectorStore::QdrantClusterAdapter::QdrantError)
    end
  end
end
