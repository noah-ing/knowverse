//! Embedding cache using moka for high-performance async caching

use moka::future::Cache;
use std::hash::{Hash, Hasher};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

/// Cache key combining text hash and model name
#[derive(Clone, Debug, Eq, PartialEq, Hash)]
struct CacheKey {
    text_hash: u64,
    model: String,
}

impl CacheKey {
    fn new(text: &str, model: &str) -> Self {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        text.hash(&mut hasher);
        CacheKey {
            text_hash: hasher.finish(),
            model: model.to_string(),
        }
    }
}

/// High-performance embedding cache
pub struct EmbeddingCache {
    cache: Cache<CacheKey, Vec<f32>>,
    hits: AtomicU64,
    misses: AtomicU64,
}

impl EmbeddingCache {
    /// Create a new cache with specified size in MB
    pub fn new(size_mb: u64) -> Self {
        // Estimate: 768-dim embedding = 3KB, so size_mb * 1024 / 3 entries
        let max_entries = (size_mb * 1024 / 3) as u64;

        let cache = Cache::builder()
            .max_capacity(max_entries)
            .time_to_idle(Duration::from_secs(3600)) // 1 hour TTL
            .build();

        EmbeddingCache {
            cache,
            hits: AtomicU64::new(0),
            misses: AtomicU64::new(0),
        }
    }

    /// Get embedding from cache
    pub async fn get(&self, text: &str, model: &str) -> Option<Vec<f32>> {
        let key = CacheKey::new(text, model);
        match self.cache.get(&key).await {
            Some(embedding) => {
                self.hits.fetch_add(1, Ordering::Relaxed);
                Some(embedding)
            }
            None => {
                self.misses.fetch_add(1, Ordering::Relaxed);
                None
            }
        }
    }

    /// Insert embedding into cache
    pub async fn insert(&self, text: &str, model: &str, embedding: Vec<f32>) {
        let key = CacheKey::new(text, model);
        self.cache.insert(key, embedding).await;
    }

    /// Get multiple embeddings from cache, returning (cached, missing_indices)
    pub async fn get_batch(
        &self,
        texts: &[String],
        model: &str,
    ) -> (Vec<(usize, Vec<f32>)>, Vec<usize>) {
        let mut cached = Vec::new();
        let mut missing = Vec::new();

        for (idx, text) in texts.iter().enumerate() {
            match self.get(text, model).await {
                Some(embedding) => cached.push((idx, embedding)),
                None => missing.push(idx),
            }
        }

        (cached, missing)
    }

    /// Insert batch of embeddings
    pub async fn insert_batch(&self, texts: &[String], model: &str, embeddings: &[Vec<f32>]) {
        for (text, embedding) in texts.iter().zip(embeddings.iter()) {
            self.insert(text, model, embedding.clone()).await;
        }
    }

    /// Get cache statistics
    pub fn stats(&self) -> CacheStats {
        let hits = self.hits.load(Ordering::Relaxed);
        let misses = self.misses.load(Ordering::Relaxed);
        let total = hits + misses;
        let hit_rate = if total > 0 {
            hits as f64 / total as f64
        } else {
            0.0
        };

        CacheStats {
            hits,
            misses,
            hit_rate,
            entry_count: self.cache.entry_count(),
            weighted_size: self.cache.weighted_size(),
        }
    }

    /// Clear all cache entries
    pub fn clear(&self) {
        self.cache.invalidate_all();
        self.hits.store(0, Ordering::Relaxed);
        self.misses.store(0, Ordering::Relaxed);
    }
}

/// Cache statistics
#[derive(Debug, Clone, serde::Serialize)]
pub struct CacheStats {
    pub hits: u64,
    pub misses: u64,
    pub hit_rate: f64,
    pub entry_count: u64,
    pub weighted_size: u64,
}
