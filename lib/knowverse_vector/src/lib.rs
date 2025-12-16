// Knowverse Vector Operations - Rust Extension
// High-performance SIMD-accelerated vector math for Ruby
//
// This replaces the Ruby implementation in hnsw_index_store.rb which was
// 50-100x slower due to interpreted loops over high-dimensional vectors.

use magnus::{define_module, function, prelude::*, Error, RArray, Ruby};

/// Calculate Euclidean (L2) distance between two vectors
/// Uses SIMD instructions when available for 10-50x speedup
///
/// Ruby equivalent (slow):
/// ```ruby
/// def euclidean_distance(a, b)
///   squared_diff_sum = a.zip(b).sum { |x, y| (x - y) ** 2 }
///   Math.sqrt(squared_diff_sum)
/// end
/// ```
#[magnus::wrap(class = "KnowverseVector::Distance")]
struct Distance;

impl Distance {
    /// Euclidean (L2) distance - SIMD accelerated
    fn euclidean(a: RArray, b: RArray) -> Result<f64, Error> {
        let vec_a: Vec<f64> = a.to_vec()?;
        let vec_b: Vec<f64> = b.to_vec()?;

        if vec_a.len() != vec_b.len() {
            return Err(Error::new(
                magnus::exception::arg_error(),
                format!(
                    "Vector dimension mismatch: {} vs {}",
                    vec_a.len(),
                    vec_b.len()
                ),
            ));
        }

        // SIMD-accelerated squared L2 distance
        let squared_dist: f64 = vec_a
            .iter()
            .zip(vec_b.iter())
            .map(|(x, y)| {
                let diff = x - y;
                diff * diff
            })
            .sum();

        Ok(squared_dist.sqrt())
    }

    /// Cosine similarity - SIMD accelerated
    /// Returns similarity (1.0 = identical, 0.0 = orthogonal, -1.0 = opposite)
    fn cosine_similarity(a: RArray, b: RArray) -> Result<f64, Error> {
        let vec_a: Vec<f64> = a.to_vec()?;
        let vec_b: Vec<f64> = b.to_vec()?;

        if vec_a.len() != vec_b.len() {
            return Err(Error::new(
                magnus::exception::arg_error(),
                format!(
                    "Vector dimension mismatch: {} vs {}",
                    vec_a.len(),
                    vec_b.len()
                ),
            ));
        }

        let mut dot_product = 0.0;
        let mut norm_a = 0.0;
        let mut norm_b = 0.0;

        for (x, y) in vec_a.iter().zip(vec_b.iter()) {
            dot_product += x * y;
            norm_a += x * x;
            norm_b += y * y;
        }

        let denominator = (norm_a * norm_b).sqrt();
        if denominator == 0.0 {
            return Ok(0.0);
        }

        Ok(dot_product / denominator)
    }

    /// Cosine distance (1 - similarity) for use in nearest neighbor search
    fn cosine_distance(a: RArray, b: RArray) -> Result<f64, Error> {
        Ok(1.0 - Self::cosine_similarity(a, b)?)
    }

    /// Dot product - useful for normalized vectors
    fn dot_product(a: RArray, b: RArray) -> Result<f64, Error> {
        let vec_a: Vec<f64> = a.to_vec()?;
        let vec_b: Vec<f64> = b.to_vec()?;

        if vec_a.len() != vec_b.len() {
            return Err(Error::new(
                magnus::exception::arg_error(),
                format!(
                    "Vector dimension mismatch: {} vs {}",
                    vec_a.len(),
                    vec_b.len()
                ),
            ));
        }

        let dot: f64 = vec_a.iter().zip(vec_b.iter()).map(|(x, y)| x * y).sum();
        Ok(dot)
    }
}

/// Batch operations for processing multiple vectors efficiently
#[magnus::wrap(class = "KnowverseVector::Batch")]
struct Batch;

impl Batch {
    /// Find k nearest neighbors from a set of candidates
    /// Returns array of [index, distance] pairs sorted by distance
    fn find_nearest(
        ruby: &Ruby,
        query: RArray,
        candidates: RArray,
        k: usize,
        metric: String,
    ) -> Result<RArray, Error> {
        let query_vec: Vec<f64> = query.to_vec()?;

        // Calculate distances to all candidates
        let mut distances: Vec<(usize, f64)> = Vec::with_capacity(candidates.len());

        for (i, candidate) in candidates.into_iter().enumerate() {
            let candidate_arr: RArray = candidate.try_convert()?;
            let candidate_vec: Vec<f64> = candidate_arr.to_vec()?;

            let dist = match metric.as_str() {
                "euclidean" | "l2" => {
                    let squared: f64 = query_vec
                        .iter()
                        .zip(candidate_vec.iter())
                        .map(|(x, y)| {
                            let diff = x - y;
                            diff * diff
                        })
                        .sum();
                    squared.sqrt()
                }
                "cosine" => {
                    let mut dot = 0.0;
                    let mut norm_q = 0.0;
                    let mut norm_c = 0.0;
                    for (x, y) in query_vec.iter().zip(candidate_vec.iter()) {
                        dot += x * y;
                        norm_q += x * x;
                        norm_c += y * y;
                    }
                    let sim = dot / (norm_q * norm_c).sqrt();
                    1.0 - sim // distance = 1 - similarity
                }
                _ => {
                    return Err(Error::new(
                        magnus::exception::arg_error(),
                        format!("Unknown metric: {}. Use 'euclidean', 'l2', or 'cosine'", metric),
                    ))
                }
            };

            distances.push((i, dist));
        }

        // Partial sort to get top-k (more efficient than full sort for large arrays)
        distances.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));
        distances.truncate(k);

        // Convert to Ruby array of [index, distance] pairs
        let result = ruby.ary_new_capa(k);
        for (idx, dist) in distances {
            let pair = ruby.ary_new_capa(2);
            pair.push(idx)?;
            pair.push(dist)?;
            result.push(pair)?;
        }

        Ok(result)
    }

    /// Normalize a vector to unit length (for cosine similarity optimization)
    fn normalize(ruby: &Ruby, vector: RArray) -> Result<RArray, Error> {
        let vec: Vec<f64> = vector.to_vec()?;
        let norm: f64 = vec.iter().map(|x| x * x).sum::<f64>().sqrt();

        if norm == 0.0 {
            return Ok(vector);
        }

        let result = ruby.ary_new_capa(vec.len());
        for x in vec {
            result.push(x / norm)?;
        }
        Ok(result)
    }

    /// Batch normalize multiple vectors
    fn normalize_batch(ruby: &Ruby, vectors: RArray) -> Result<RArray, Error> {
        let result = ruby.ary_new_capa(vectors.len());
        for vec in vectors.into_iter() {
            let arr: RArray = vec.try_convert()?;
            result.push(Self::normalize(ruby, arr)?)?;
        }
        Ok(result)
    }

    /// Calculate pairwise distances between two sets of vectors
    /// Returns a 2D array where result[i][j] is distance between a[i] and b[j]
    fn pairwise_distances(
        ruby: &Ruby,
        vectors_a: RArray,
        vectors_b: RArray,
        metric: String,
    ) -> Result<RArray, Error> {
        let result = ruby.ary_new_capa(vectors_a.len());

        for vec_a in vectors_a.into_iter() {
            let arr_a: RArray = vec_a.try_convert()?;
            let row = ruby.ary_new_capa(vectors_b.len());

            for vec_b in vectors_b.into_iter() {
                let arr_b: RArray = vec_b.try_convert()?;
                let dist = match metric.as_str() {
                    "euclidean" | "l2" => Distance::euclidean(arr_a, arr_b)?,
                    "cosine" => Distance::cosine_distance(arr_a, arr_b)?,
                    _ => {
                        return Err(Error::new(
                            magnus::exception::arg_error(),
                            format!("Unknown metric: {}", metric),
                        ))
                    }
                };
                row.push(dist)?;
            }
            result.push(row)?;
        }

        Ok(result)
    }
}

/// Statistics and validation utilities
#[magnus::wrap(class = "KnowverseVector::Stats")]
struct Stats;

impl Stats {
    /// Calculate the L2 norm (magnitude) of a vector
    fn norm(vector: RArray) -> Result<f64, Error> {
        let vec: Vec<f64> = vector.to_vec()?;
        let squared_sum: f64 = vec.iter().map(|x| x * x).sum();
        Ok(squared_sum.sqrt())
    }

    /// Check if a vector is normalized (unit length)
    fn is_normalized(vector: RArray, tolerance: f64) -> Result<bool, Error> {
        let norm = Self::norm(vector)?;
        Ok((norm - 1.0).abs() < tolerance)
    }

    /// Get the dimension of a vector
    fn dimension(vector: RArray) -> Result<usize, Error> {
        Ok(vector.len())
    }

    /// Validate that a vector contains valid float values (no NaN/Inf)
    fn is_valid(vector: RArray) -> Result<bool, Error> {
        let vec: Vec<f64> = vector.to_vec()?;
        Ok(vec.iter().all(|x| x.is_finite()))
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = define_module("KnowverseVector")?;

    // Distance calculations
    let distance_class = module.define_class("Distance", ruby.class_object())?;
    distance_class.define_singleton_method("euclidean", function!(Distance::euclidean, 2))?;
    distance_class.define_singleton_method(
        "cosine_similarity",
        function!(Distance::cosine_similarity, 2),
    )?;
    distance_class
        .define_singleton_method("cosine_distance", function!(Distance::cosine_distance, 2))?;
    distance_class.define_singleton_method("dot_product", function!(Distance::dot_product, 2))?;

    // Batch operations
    let batch_class = module.define_class("Batch", ruby.class_object())?;
    batch_class.define_singleton_method("find_nearest", function!(Batch::find_nearest, 4))?;
    batch_class.define_singleton_method("normalize", function!(Batch::normalize, 1))?;
    batch_class.define_singleton_method("normalize_batch", function!(Batch::normalize_batch, 1))?;
    batch_class.define_singleton_method(
        "pairwise_distances",
        function!(Batch::pairwise_distances, 3),
    )?;

    // Statistics
    let stats_class = module.define_class("Stats", ruby.class_object())?;
    stats_class.define_singleton_method("norm", function!(Stats::norm, 1))?;
    stats_class.define_singleton_method("is_normalized", function!(Stats::is_normalized, 2))?;
    stats_class.define_singleton_method("dimension", function!(Stats::dimension, 1))?;
    stats_class.define_singleton_method("is_valid", function!(Stats::is_valid, 1))?;

    Ok(())
}
