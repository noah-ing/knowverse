# frozen_string_literal: true

require 'rails_helper'
require_relative '../../lib/knowverse_vector'

RSpec.describe KnowverseVector do
  describe 'Distance calculations' do
    describe '.euclidean' do
      it 'calculates correct distance for 3D vectors' do
        vec_a = [0.0, 0.0, 0.0]
        vec_b = [1.0, 0.0, 0.0]

        expect(KnowverseVector::Distance.euclidean(vec_a, vec_b)).to eq(1.0)
      end

      it 'calculates correct distance for diagonal' do
        vec_a = [0.0, 0.0, 0.0]
        vec_b = [1.0, 1.0, 1.0]

        expect(KnowverseVector::Distance.euclidean(vec_a, vec_b)).to be_within(0.0001).of(Math.sqrt(3))
      end

      it 'returns 0 for identical vectors' do
        vec = [1.0, 2.0, 3.0]

        expect(KnowverseVector::Distance.euclidean(vec, vec)).to eq(0.0)
      end

      it 'raises error for mismatched dimensions' do
        vec_a = [1.0, 2.0]
        vec_b = [1.0, 2.0, 3.0]

        expect { KnowverseVector::Distance.euclidean(vec_a, vec_b) }.to raise_error(ArgumentError)
      end

      it 'handles high-dimensional vectors (768 dims)' do
        vec_a = Array.new(768) { rand(-1.0..1.0) }
        vec_b = Array.new(768) { rand(-1.0..1.0) }

        result = KnowverseVector::Distance.euclidean(vec_a, vec_b)
        expect(result).to be_a(Float)
        expect(result).to be >= 0
      end
    end

    describe '.cosine_similarity' do
      it 'returns 1.0 for identical vectors' do
        vec = [1.0, 2.0, 3.0]

        expect(KnowverseVector::Distance.cosine_similarity(vec, vec)).to be_within(0.0001).of(1.0)
      end

      it 'returns 0.0 for orthogonal vectors' do
        vec_a = [1.0, 0.0]
        vec_b = [0.0, 1.0]

        expect(KnowverseVector::Distance.cosine_similarity(vec_a, vec_b)).to be_within(0.0001).of(0.0)
      end

      it 'returns -1.0 for opposite vectors' do
        vec_a = [1.0, 0.0]
        vec_b = [-1.0, 0.0]

        expect(KnowverseVector::Distance.cosine_similarity(vec_a, vec_b)).to be_within(0.0001).of(-1.0)
      end

      it 'is scale-invariant' do
        vec_a = [1.0, 2.0, 3.0]
        vec_b = [2.0, 4.0, 6.0]

        expect(KnowverseVector::Distance.cosine_similarity(vec_a, vec_b)).to be_within(0.0001).of(1.0)
      end
    end

    describe '.cosine_distance' do
      it 'returns 0 for identical vectors' do
        vec = [1.0, 2.0, 3.0]

        expect(KnowverseVector::Distance.cosine_distance(vec, vec)).to be_within(0.0001).of(0.0)
      end

      it 'returns 1 for orthogonal vectors' do
        vec_a = [1.0, 0.0]
        vec_b = [0.0, 1.0]

        expect(KnowverseVector::Distance.cosine_distance(vec_a, vec_b)).to be_within(0.0001).of(1.0)
      end
    end

    describe '.dot_product' do
      it 'calculates correct dot product' do
        vec_a = [1.0, 2.0, 3.0]
        vec_b = [4.0, 5.0, 6.0]

        # 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
        expect(KnowverseVector::Distance.dot_product(vec_a, vec_b)).to eq(32.0)
      end
    end
  end

  describe 'Batch operations' do
    describe '.find_nearest' do
      let(:query) { [1.0, 0.0, 0.0] }
      let(:candidates) do
        [
          [0.9, 0.1, 0.0],  # idx 0: closest
          [0.0, 1.0, 0.0],  # idx 1: orthogonal
          [0.5, 0.5, 0.0],  # idx 2: middle
          [-1.0, 0.0, 0.0]  # idx 3: opposite
        ]
      end

      it 'returns correct number of neighbors' do
        results = KnowverseVector::Batch.find_nearest(query, candidates, 2, 'euclidean')

        expect(results.length).to eq(2)
      end

      it 'returns neighbors in order of increasing distance' do
        results = KnowverseVector::Batch.find_nearest(query, candidates, 4, 'euclidean')

        distances = results.map(&:last)
        expect(distances).to eq(distances.sort)
      end

      it 'identifies closest neighbor correctly with euclidean' do
        results = KnowverseVector::Batch.find_nearest(query, candidates, 1, 'euclidean')

        expect(results.first[0]).to eq(0) # Index 0 is closest
      end

      it 'identifies closest neighbor correctly with cosine' do
        results = KnowverseVector::Batch.find_nearest(query, candidates, 1, 'cosine')

        expect(results.first[0]).to eq(0) # Index 0 is closest
      end

      it 'handles large candidate sets' do
        large_candidates = Array.new(1000) { Array.new(768) { rand(-1.0..1.0) } }
        large_query = Array.new(768) { rand(-1.0..1.0) }

        results = KnowverseVector::Batch.find_nearest(large_query, large_candidates, 10, 'cosine')

        expect(results.length).to eq(10)
      end
    end

    describe '.normalize' do
      it 'normalizes vector to unit length' do
        vec = [3.0, 4.0] # 3-4-5 triangle

        normalized = KnowverseVector::Batch.normalize(vec)

        expect(normalized[0]).to be_within(0.0001).of(0.6)
        expect(normalized[1]).to be_within(0.0001).of(0.8)

        # Verify unit length
        norm = Math.sqrt(normalized.sum { |x| x * x })
        expect(norm).to be_within(0.0001).of(1.0)
      end

      it 'handles zero vector' do
        vec = [0.0, 0.0, 0.0]

        normalized = KnowverseVector::Batch.normalize(vec)

        expect(normalized).to eq([0.0, 0.0, 0.0])
      end
    end

    describe '.normalize_batch' do
      it 'normalizes multiple vectors' do
        vectors = [
          [3.0, 4.0],
          [1.0, 0.0],
          [0.0, 2.0]
        ]

        normalized = KnowverseVector::Batch.normalize_batch(vectors)

        expect(normalized.length).to eq(3)
        normalized.each do |vec|
          norm = Math.sqrt(vec.sum { |x| x * x })
          expect(norm).to be_within(0.0001).of(1.0)
        end
      end
    end
  end

  describe 'Stats' do
    describe '.norm' do
      it 'calculates correct L2 norm' do
        vec = [3.0, 4.0]

        expect(KnowverseVector::Stats.norm(vec)).to eq(5.0)
      end
    end

    describe '.is_normalized' do
      it 'returns true for unit vectors' do
        vec = [1.0, 0.0, 0.0]

        expect(KnowverseVector::Stats.is_normalized(vec, 0.0001)).to be true
      end

      it 'returns false for non-unit vectors' do
        vec = [2.0, 0.0, 0.0]

        expect(KnowverseVector::Stats.is_normalized(vec, 0.0001)).to be false
      end
    end

    describe '.dimension' do
      it 'returns correct dimension' do
        expect(KnowverseVector::Stats.dimension([1, 2, 3])).to eq(3)
        expect(KnowverseVector::Stats.dimension(Array.new(768))).to eq(768)
      end
    end

    describe '.is_valid' do
      it 'returns true for valid vectors' do
        expect(KnowverseVector::Stats.is_valid([1.0, 2.0, 3.0])).to be true
      end

      it 'returns false for vectors with NaN' do
        expect(KnowverseVector::Stats.is_valid([1.0, Float::NAN, 3.0])).to be false
      end

      it 'returns false for vectors with Infinity' do
        expect(KnowverseVector::Stats.is_valid([1.0, Float::INFINITY, 3.0])).to be false
      end
    end
  end

  describe 'Implementation detection' do
    it 'reports whether Rust is available' do
      # This will be true if compiled, false otherwise
      expect([true, false]).to include(KnowverseVector.rust_available?)
    end

    it 'has fallback implementation when Rust unavailable' do
      # Even without Rust, all methods should work
      vec_a = [1.0, 2.0, 3.0]
      vec_b = [4.0, 5.0, 6.0]

      expect { KnowverseVector::Distance.euclidean(vec_a, vec_b) }.not_to raise_error
      expect { KnowverseVector::Distance.cosine_similarity(vec_a, vec_b) }.not_to raise_error
    end
  end
end
