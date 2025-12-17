require 'rails_helper'

RSpec.describe SearchRouter do
  let(:organization) { create(:organization) }
  let(:query) { "machine learning optimization" }

  describe '.route_query' do
    let(:mock_service) { instance_double(Search::UnifiedSearchService) }

    before do
      allow(Search::UnifiedSearchService).to receive(:new).and_return(mock_service)
    end

    context 'with semantic search' do
      it 'routes to semantic mode by default' do
        expect(mock_service).to receive(:search).with(
          query,
          organization.id,
          hash_including(mode: :semantic)
        ).and_return([])

        SearchRouter.route_query(query, organization.id)
      end

      it 'routes legacy pgvector_cosine to semantic' do
        expect(mock_service).to receive(:search).with(
          query,
          organization.id,
          hash_including(mode: :semantic)
        ).and_return([])

        SearchRouter.route_query(query, organization.id, provider: :pgvector_cosine)
      end

      it 'routes legacy hnsw to semantic' do
        expect(mock_service).to receive(:search).with(
          query,
          organization.id,
          hash_including(mode: :semantic)
        ).and_return([])

        SearchRouter.route_query(query, organization.id, provider: :hnsw)
      end
    end

    context 'with hybrid search' do
      it 'routes hybrid provider to hybrid mode' do
        expect(mock_service).to receive(:search).with(
          query,
          organization.id,
          hash_including(mode: :hybrid)
        ).and_return([])

        SearchRouter.route_query(query, organization.id, provider: :hybrid)
      end

      it 'routes hybrid_advanced provider to hybrid mode' do
        expect(mock_service).to receive(:search).with(
          query,
          organization.id,
          hash_including(mode: :hybrid)
        ).and_return([])

        SearchRouter.route_query(query, organization.id, provider: :hybrid_advanced)
      end
    end

    context 'with keyword search' do
      it 'routes keyword provider to keyword mode' do
        expect(mock_service).to receive(:search).with(
          query,
          organization.id,
          hash_including(mode: :keyword)
        ).and_return([])

        SearchRouter.route_query(query, organization.id, provider: :keyword)
      end
    end

    context 'with options' do
      it 'passes limit option' do
        expect(mock_service).to receive(:search).with(
          query,
          organization.id,
          hash_including(limit: 25)
        ).and_return([])

        SearchRouter.route_query(query, organization.id, limit: 25)
      end

      it 'passes filter option' do
        filter = { file_type: 'pdf' }
        expect(mock_service).to receive(:search).with(
          query,
          organization.id,
          hash_including(filter: filter)
        ).and_return([])

        SearchRouter.route_query(query, organization.id, filter: filter)
      end

      it 'passes weight options for hybrid search' do
        expect(mock_service).to receive(:search).with(
          query,
          organization.id,
          hash_including(vector_weight: 0.8, keyword_weight: 0.2)
        ).and_return([])

        SearchRouter.route_query(
          query,
          organization.id,
          provider: :hybrid,
          vector_weight: 0.8,
          keyword_weight: 0.2
        )
      end
    end

    context 'with error handling' do
      it 'returns empty array on CollectionNotFoundError' do
        allow(mock_service).to receive(:search)
          .and_raise(Search::UnifiedSearchService::CollectionNotFoundError.new("Collection not found"))

        result = SearchRouter.route_query(query, organization.id)
        expect(result).to eq([])
      end

      it 'returns empty array on SearchError' do
        allow(mock_service).to receive(:search)
          .and_raise(Search::UnifiedSearchService::SearchError.new("Search failed"))

        result = SearchRouter.route_query(query, organization.id)
        expect(result).to eq([])
      end
    end
  end

  describe '.semantic_search' do
    let(:mock_service) { instance_double(Search::UnifiedSearchService) }

    before do
      allow(Search::UnifiedSearchService).to receive(:new).and_return(mock_service)
    end

    it 'calls service with semantic mode' do
      expect(mock_service).to receive(:search).with(
        query,
        organization.id,
        hash_including(mode: :semantic)
      ).and_return([])

      SearchRouter.semantic_search(query, organization.id)
    end
  end

  describe '.keyword_search' do
    let(:mock_service) { instance_double(Search::UnifiedSearchService) }

    before do
      allow(Search::UnifiedSearchService).to receive(:new).and_return(mock_service)
    end

    it 'calls service with keyword mode' do
      expect(mock_service).to receive(:search).with(
        query,
        organization.id,
        hash_including(mode: :keyword)
      ).and_return([])

      SearchRouter.keyword_search(query, organization.id)
    end
  end

  describe '.hybrid_search' do
    let(:mock_service) { instance_double(Search::UnifiedSearchService) }

    before do
      allow(Search::UnifiedSearchService).to receive(:new).and_return(mock_service)
    end

    it 'calls service with hybrid mode' do
      expect(mock_service).to receive(:search).with(
        query,
        organization.id,
        hash_including(mode: :hybrid)
      ).and_return([])

      SearchRouter.hybrid_search(query, organization.id)
    end
  end

  describe '.index_document' do
    let(:mock_service) { instance_double(Search::UnifiedSearchService) }
    let(:document) { create(:document, organization: organization) }

    before do
      allow(Search::UnifiedSearchService).to receive(:new).and_return(mock_service)
    end

    it 'calls service index_document' do
      expect(mock_service).to receive(:index_document).with(document)

      SearchRouter.index_document(document)
    end
  end

  describe '.bulk_index' do
    let(:mock_service) { instance_double(Search::UnifiedSearchService) }
    let(:documents) { create_list(:document, 3, organization: organization) }

    before do
      allow(Search::UnifiedSearchService).to receive(:new).and_return(mock_service)
    end

    it 'calls service bulk_index' do
      expect(mock_service).to receive(:bulk_index).with(documents)

      SearchRouter.bulk_index(documents)
    end
  end

  describe '.remove_document' do
    let(:mock_service) { instance_double(Search::UnifiedSearchService) }
    let(:document) { create(:document, organization: organization) }

    before do
      allow(Search::UnifiedSearchService).to receive(:new).and_return(mock_service)
    end

    it 'calls service remove_document' do
      expect(mock_service).to receive(:remove_document).with(document)

      SearchRouter.remove_document(document)
    end
  end

  describe '.healthy?' do
    let(:mock_service) { instance_double(Search::UnifiedSearchService) }

    before do
      allow(Search::UnifiedSearchService).to receive(:new).and_return(mock_service)
    end

    it 'returns true when service is healthy' do
      allow(mock_service).to receive(:healthy?).and_return(true)

      expect(SearchRouter.healthy?).to be true
    end

    it 'returns false when service is unhealthy' do
      allow(mock_service).to receive(:healthy?).and_return(false)

      expect(SearchRouter.healthy?).to be false
    end
  end

  describe '.available_providers' do
    it 'returns all legacy provider names' do
      providers = SearchRouter.available_providers

      expect(providers).to include(:pgvector_cosine)
      expect(providers).to include(:hybrid)
      expect(providers).to include(:hnsw)
      expect(providers).to include(:distributed)
    end
  end

  describe '.available_modes' do
    it 'returns all new modes' do
      modes = SearchRouter.available_modes

      expect(modes).to eq([:semantic, :keyword, :hybrid])
    end
  end

  describe 'PROVIDERS' do
    it 'maps all providers to descriptions' do
      expect(SearchRouter::PROVIDERS.keys.size).to eq(9)
      expect(SearchRouter::PROVIDERS[:pgvector_cosine]).to eq('Semantic Search')
      expect(SearchRouter::PROVIDERS[:hybrid]).to eq('Hybrid Search')
    end
  end

  describe 'MODES' do
    it 'documents all search modes' do
      expect(SearchRouter::MODES[:semantic]).to include('Qdrant')
      expect(SearchRouter::MODES[:keyword]).to include('PostgreSQL')
      expect(SearchRouter::MODES[:hybrid]).to include('Combined')
    end
  end
end
