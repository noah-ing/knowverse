# frozen_string_literal: true

# KnowverseVector - High-performance vector operations
#
# This module provides SIMD-accelerated vector math when the Rust extension
# is compiled, with automatic fallback to pure Ruby when it's not available.
#
# Usage:
#   KnowverseVector::Distance.euclidean(vec_a, vec_b)
#   KnowverseVector::Distance.cosine_similarity(vec_a, vec_b)
#   KnowverseVector::Batch.find_nearest(query, candidates, k, 'cosine')
#
# Performance:
#   Rust extension: 50-100x faster for high-dimensional vectors (768-2048 dims)
#   Pure Ruby fallback: Works everywhere, slower but functional

module KnowverseVector
  class << self
    def rust_available?
      @rust_available
    end

    def using_rust?
      @rust_available == true
    end

    def using_ruby_fallback?
      @rust_available == false
    end
  end

  # Try to load the Rust extension
  begin
    require 'knowverse_vector/knowverse_vector'
    @rust_available = true
    Rails.logger.info('[KnowverseVector] Rust SIMD extension loaded - 50-100x speedup enabled') if defined?(Rails)
  rescue LoadError => e
    @rust_available = false
    if defined?(Rails)
      Rails.logger.warn("[KnowverseVector] Rust extension not available (#{e.message}), using Ruby fallback")
    end

    # Pure Ruby fallback implementations
    class Distance
      class << self
        def euclidean(a, b)
          raise ArgumentError, "Vector dimension mismatch: #{a.length} vs #{b.length}" if a.length != b.length

          squared_sum = 0.0
          a.length.times do |i|
            diff = a[i] - b[i]
            squared_sum += diff * diff
          end
          Math.sqrt(squared_sum)
        end

        def cosine_similarity(a, b)
          raise ArgumentError, "Vector dimension mismatch: #{a.length} vs #{b.length}" if a.length != b.length

          dot = 0.0
          norm_a = 0.0
          norm_b = 0.0

          a.length.times do |i|
            dot += a[i] * b[i]
            norm_a += a[i] * a[i]
            norm_b += b[i] * b[i]
          end

          denominator = Math.sqrt(norm_a * norm_b)
          return 0.0 if denominator.zero?

          dot / denominator
        end

        def cosine_distance(a, b)
          1.0 - cosine_similarity(a, b)
        end

        def dot_product(a, b)
          raise ArgumentError, "Vector dimension mismatch: #{a.length} vs #{b.length}" if a.length != b.length

          sum = 0.0
          a.length.times { |i| sum += a[i] * b[i] }
          sum
        end
      end
    end

    class Batch
      class << self
        def find_nearest(query, candidates, k, metric = 'cosine')
          distances = candidates.each_with_index.map do |candidate, idx|
            dist = case metric
                   when 'euclidean', 'l2'
                     Distance.euclidean(query, candidate)
                   when 'cosine'
                     Distance.cosine_distance(query, candidate)
                   else
                     raise ArgumentError, "Unknown metric: #{metric}"
                   end
            [idx, dist]
          end

          distances.sort_by(&:last).first(k)
        end

        def normalize(vector)
          norm = Math.sqrt(vector.sum { |x| x * x })
          return vector if norm.zero?

          vector.map { |x| x / norm }
        end

        def normalize_batch(vectors)
          vectors.map { |v| normalize(v) }
        end

        def pairwise_distances(vectors_a, vectors_b, metric = 'cosine')
          vectors_a.map do |vec_a|
            vectors_b.map do |vec_b|
              case metric
              when 'euclidean', 'l2'
                Distance.euclidean(vec_a, vec_b)
              when 'cosine'
                Distance.cosine_distance(vec_a, vec_b)
              else
                raise ArgumentError, "Unknown metric: #{metric}"
              end
            end
          end
        end
      end
    end

    class Stats
      class << self
        def norm(vector)
          Math.sqrt(vector.sum { |x| x * x })
        end

        def is_normalized(vector, tolerance = 0.0001)
          (norm(vector) - 1.0).abs < tolerance
        end

        def dimension(vector)
          vector.length
        end

        def is_valid(vector)
          vector.all? { |x| x.is_a?(Numeric) && x.finite? }
        end
      end
    end
  end
end
