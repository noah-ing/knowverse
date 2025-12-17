require 'rails_helper'

RSpec.describe VectorEmbedding, type: :model do
  describe 'associations' do
    it { should belong_to(:document) }
  end

  describe 'validations' do
    it { should validate_presence_of(:model_name) }
    it { should validate_presence_of(:dimension) }
    it { should validate_presence_of(:embedding) }

    it 'validates dimension matches embedding size' do
      embedding = build(:vector_embedding, dimension: 768, embedding: Array.new(384) { 0 })
      expect(embedding).not_to be_valid
      expect(embedding.errors[:embedding]).to include('dimension mismatch')
    end
  end

  describe 'scopes' do
    let!(:active_embedding) { create(:vector_embedding, status: 'active') }
    let!(:inactive_embedding) { create(:vector_embedding, :inactive) }

    describe '.active' do
      it 'returns only active embeddings' do
        expect(VectorEmbedding.active).to include(active_embedding)
        expect(VectorEmbedding.active).not_to include(inactive_embedding)
      end
    end

    describe '.for_model' do
      let!(:mpnet_embedding) { create(:vector_embedding, model_name: 'all-mpnet-base-v2') }
      let!(:minilm_embedding) { create(:vector_embedding, :mini_lm) }

      it 'filters by model name' do
        results = VectorEmbedding.for_model('all-MiniLM-L6-v2')
        expect(results).to include(minilm_embedding)
        expect(results).not_to include(mpnet_embedding)
      end
    end
  end

  describe '#normalized_embedding' do
    it 'returns L2 normalized embedding' do
      embedding = create(:vector_embedding, embedding: [3, 4, 0])
      normalized = embedding.normalized_embedding

      # L2 norm of [3,4,0] is 5, so normalized should be [0.6, 0.8, 0]
      expect(normalized[0]).to be_within(0.01).of(0.6)
      expect(normalized[1]).to be_within(0.01).of(0.8)
    end
  end

  describe '#cosine_similarity' do
    let(:embedding1) { create(:vector_embedding, embedding: [1, 0, 0]) }

    it 'calculates cosine similarity with another embedding' do
      other_embedding = [1, 0, 0]
      expect(embedding1.cosine_similarity(other_embedding)).to be_within(0.001).of(1.0)
    end

    it 'returns 0 for orthogonal vectors' do
      other_embedding = [0, 1, 0]
      expect(embedding1.cosine_similarity(other_embedding)).to be_within(0.001).of(0.0)
    end

    it 'returns -1 for opposite vectors' do
      other_embedding = [-1, 0, 0]
      expect(embedding1.cosine_similarity(other_embedding)).to be_within(0.001).of(-1.0)
    end
  end

  describe 'factory' do
    it 'creates valid embedding' do
      embedding = build(:vector_embedding)
      expect(embedding).to be_valid
    end

    it 'creates mini_lm embedding with correct dimension' do
      embedding = create(:vector_embedding, :mini_lm)
      expect(embedding.dimension).to eq(384)
      expect(embedding.embedding.size).to eq(384)
    end

    it 'creates bge_large embedding with correct dimension' do
      embedding = create(:vector_embedding, :bge_large)
      expect(embedding.dimension).to eq(1024)
      expect(embedding.embedding.size).to eq(1024)
    end
  end
end
