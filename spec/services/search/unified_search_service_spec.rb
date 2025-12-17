require 'rails_helper'

RSpec.describe Search::UnifiedSearchService do
  let(:service) { described_class.new }
  let(:organization) { create(:organization) }
  let(:query) { "machine learning algorithms" }

  describe '#search' do
    let(:mock_qdrant) { instance_double(VectorStore::QdrantClusterAdapter) }
    let(:mock_haystack) { instance_double(HaystackClient) }

    before do
      allow(VectorStore::QdrantClusterAdapter).to receive(:new).and_return(mock_qdrant)
      allow(HaystackClient).to receive(:new).and_return(mock_haystack)
      allow(mock_haystack).to receive(:generate_embeddings).and_return(Array.new(768) { rand })
    end

    context 'with semantic mode' do
      it 'performs vector search via Qdrant' do
        expect(mock_qdrant).to receive(:search).with(
          hash_including(
            collection: "org_#{organization.id}",
            vector: kind_of(Array)
          )
        ).and_return([])

        service.search(query, organization.id, mode: :semantic)
      end

      it 'applies score threshold filter' do
        expect(mock_qdrant).to receive(:search).with(
          hash_including(score_threshold: 0.8)
        ).and_return([])

        service.search(query, organization.id, mode: :semantic, score_threshold: 0.8)
      end

      it 'applies limit' do
        expect(mock_qdrant).to receive(:search).with(
          hash_including(limit: 20)
        ).and_return([])

        service.search(query, organization.id, mode: :semantic, limit: 20)
      end
    end

    context 'with keyword mode' do
      let!(:documents) do
        create_list(:document, 3, :with_content, organization: organization)
      end

      it 'performs PostgreSQL full-text search' do
        results = service.search(query, organization.id, mode: :keyword)
        expect(results).to be_an(Array)
      end

      it 'filters by organization' do
        other_org = create(:organization)
        create(:document, :with_content, organization: other_org)

        results = service.search(query, organization.id, mode: :keyword)
        results.each do |result|
          expect(result[:organization_id]).to eq(organization.id)
        end
      end
    end

    context 'with hybrid mode' do
      it 'combines vector and keyword search' do
        expect(mock_qdrant).to receive(:search).and_return([
          { id: 1, score: 0.9 },
          { id: 2, score: 0.8 }
        ])

        results = service.search(query, organization.id, mode: :hybrid)
        expect(results).to be_an(Array)
      end

      it 'applies RRF fusion with configurable weights' do
        allow(mock_qdrant).to receive(:search).and_return([])

        service.search(
          query,
          organization.id,
          mode: :hybrid,
          vector_weight: 0.8,
          keyword_weight: 0.2
        )
      end
    end

    context 'with filters' do
      it 'applies metadata filters to vector search' do
        filter = { file_type: 'pdf', status: 'active' }

        expect(mock_qdrant).to receive(:search).with(
          hash_including(filter: filter)
        ).and_return([])

        service.search(query, organization.id, mode: :semantic, filter: filter)
      end
    end

    context 'error handling' do
      it 'raises CollectionNotFoundError when collection missing' do
        allow(mock_qdrant).to receive(:search)
          .and_raise(VectorStore::QdrantClusterAdapter::CollectionNotFoundError.new("Not found"))

        expect {
          service.search(query, organization.id, mode: :semantic)
        }.to raise_error(Search::UnifiedSearchService::CollectionNotFoundError)
      end

      it 'raises SearchError on Qdrant failure' do
        allow(mock_qdrant).to receive(:search)
          .and_raise(VectorStore::QdrantClusterAdapter::QdrantError.new("Connection failed"))

        expect {
          service.search(query, organization.id, mode: :semantic)
        }.to raise_error(Search::UnifiedSearchService::SearchError)
      end
    end
  end

  describe '#batch_search' do
    let(:mock_qdrant) { instance_double(VectorStore::QdrantClusterAdapter) }
    let(:mock_haystack) { instance_double(HaystackClient) }
    let(:queries) { ["query 1", "query 2", "query 3"] }

    before do
      allow(VectorStore::QdrantClusterAdapter).to receive(:new).and_return(mock_qdrant)
      allow(HaystackClient).to receive(:new).and_return(mock_haystack)
    end

    it 'processes multiple queries' do
      queries.each do |q|
        allow(mock_haystack).to receive(:generate_embeddings).with(q, anything).and_return(Array.new(768) { rand })
      end
      allow(mock_qdrant).to receive(:search).and_return([])

      results = service.batch_search(queries, organization.id)
      expect(results.size).to eq(3)
    end
  end

  describe '#index_document' do
    let(:mock_qdrant) { instance_double(VectorStore::QdrantClusterAdapter) }
    let(:mock_haystack) { instance_double(HaystackClient) }
    let(:document) { create(:document, organization: organization) }

    before do
      allow(VectorStore::QdrantClusterAdapter).to receive(:new).and_return(mock_qdrant)
      allow(HaystackClient).to receive(:new).and_return(mock_haystack)
    end

    it 'generates embedding and indexes in Qdrant' do
      embedding = Array.new(768) { rand }
      allow(mock_haystack).to receive(:generate_embeddings).and_return(embedding)

      expect(mock_qdrant).to receive(:upsert).with(
        hash_including(
          collection: "org_#{organization.id}",
          points: array_including(
            hash_including(
              id: document.id,
              vector: embedding
            )
          )
        )
      )

      service.index_document(document)
    end

    it 'includes document metadata in payload' do
      allow(mock_haystack).to receive(:generate_embeddings).and_return(Array.new(768) { rand })

      expect(mock_qdrant).to receive(:upsert).with(
        hash_including(
          points: array_including(
            hash_including(
              payload: hash_including(
                title: document.title,
                file_type: document.file_type
              )
            )
          )
        )
      )

      service.index_document(document)
    end

    it 'creates collection if not exists' do
      allow(mock_haystack).to receive(:generate_embeddings).and_return(Array.new(768) { rand })
      allow(mock_qdrant).to receive(:upsert)
        .and_raise(VectorStore::QdrantClusterAdapter::CollectionNotFoundError.new("Not found"))
        .once
      allow(mock_qdrant).to receive(:create_collection)
      allow(mock_qdrant).to receive(:upsert)

      service.index_document(document)

      expect(mock_qdrant).to have_received(:create_collection)
    end
  end

  describe '#bulk_index' do
    let(:mock_qdrant) { instance_double(VectorStore::QdrantClusterAdapter) }
    let(:mock_haystack) { instance_double(HaystackClient) }
    let(:documents) { create_list(:document, 5, organization: organization) }

    before do
      allow(VectorStore::QdrantClusterAdapter).to receive(:new).and_return(mock_qdrant)
      allow(HaystackClient).to receive(:new).and_return(mock_haystack)
      allow(mock_haystack).to receive(:generate_embeddings).and_return(Array.new(768) { rand })
      allow(mock_qdrant).to receive(:upsert)
    end

    it 'indexes multiple documents efficiently' do
      expect(mock_qdrant).to receive(:upsert).with(
        hash_including(
          points: have_attributes(size: 5)
        )
      )

      service.bulk_index(documents)
    end
  end

  describe '#remove_document' do
    let(:mock_qdrant) { instance_double(VectorStore::QdrantClusterAdapter) }
    let(:document) { create(:document, organization: organization) }

    before do
      allow(VectorStore::QdrantClusterAdapter).to receive(:new).and_return(mock_qdrant)
    end

    it 'removes document from Qdrant' do
      expect(mock_qdrant).to receive(:delete).with(
        hash_including(
          collection: "org_#{organization.id}",
          points: [document.id]
        )
      )

      service.remove_document(document)
    end
  end

  describe '#stats' do
    let(:mock_qdrant) { instance_double(VectorStore::QdrantClusterAdapter) }

    before do
      allow(VectorStore::QdrantClusterAdapter).to receive(:new).and_return(mock_qdrant)
    end

    it 'returns collection statistics' do
      allow(mock_qdrant).to receive(:collection_info).and_return({
        vectors_count: 1000,
        points_count: 1000,
        status: 'green'
      })

      stats = service.stats(organization.id)
      expect(stats[:vectors_count]).to eq(1000)
    end
  end

  describe '#healthy?' do
    let(:mock_qdrant) { instance_double(VectorStore::QdrantClusterAdapter) }
    let(:mock_haystack) { instance_double(HaystackClient) }

    before do
      allow(VectorStore::QdrantClusterAdapter).to receive(:new).and_return(mock_qdrant)
      allow(HaystackClient).to receive(:new).and_return(mock_haystack)
    end

    it 'returns true when both services are healthy' do
      allow(mock_qdrant).to receive(:healthy?).and_return(true)
      allow(mock_haystack).to receive(:health_check).and_return({ 'status' => 'healthy' })

      expect(service.healthy?).to be true
    end

    it 'returns false when Qdrant is unhealthy' do
      allow(mock_qdrant).to receive(:healthy?).and_return(false)
      allow(mock_haystack).to receive(:health_check).and_return({ 'status' => 'healthy' })

      expect(service.healthy?).to be false
    end

    it 'returns false when Haystack is unhealthy' do
      allow(mock_qdrant).to receive(:healthy?).and_return(true)
      allow(mock_haystack).to receive(:health_check).and_return({ 'status' => 'error' })

      expect(service.healthy?).to be false
    end
  end
end
