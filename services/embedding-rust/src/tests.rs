//! Unit tests for embedding service components

#[cfg(test)]
mod cache_tests {
    use crate::cache::{CacheStats, EmbeddingCache};

    #[tokio::test]
    async fn test_cache_insert_and_get() {
        let cache = EmbeddingCache::new(100); // 100MB cache
        let text = "test embedding text";
        let model = "all-MiniLM-L6-v2";
        let embedding = vec![0.1, 0.2, 0.3, 0.4, 0.5];

        // Insert
        cache.insert(text, model, embedding.clone()).await;

        // Get
        let result = cache.get(text, model).await;
        assert!(result.is_some());
        assert_eq!(result.unwrap(), embedding);
    }

    #[tokio::test]
    async fn test_cache_miss() {
        let cache = EmbeddingCache::new(100);

        let result = cache.get("nonexistent", "model").await;
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_cache_model_separation() {
        let cache = EmbeddingCache::new(100);
        let text = "same text";
        let embedding1 = vec![0.1, 0.2];
        let embedding2 = vec![0.3, 0.4];

        // Different models should have different cache entries
        cache.insert(text, "model1", embedding1.clone()).await;
        cache.insert(text, "model2", embedding2.clone()).await;

        let result1 = cache.get(text, "model1").await;
        let result2 = cache.get(text, "model2").await;

        assert_eq!(result1, Some(embedding1));
        assert_eq!(result2, Some(embedding2));
    }

    #[tokio::test]
    async fn test_cache_batch_operations() {
        let cache = EmbeddingCache::new(100);
        let model = "test-model";

        // Insert batch
        let texts = vec![
            "text1".to_string(),
            "text2".to_string(),
            "text3".to_string(),
        ];
        let embeddings = vec![
            vec![0.1, 0.2],
            vec![0.3, 0.4],
            vec![0.5, 0.6],
        ];

        cache.insert_batch(&texts, model, &embeddings).await;

        // Get batch with some missing
        let query_texts = vec![
            "text1".to_string(),
            "text2".to_string(),
            "text4".to_string(), // missing
        ];

        let (cached, missing) = cache.get_batch(&query_texts, model).await;

        assert_eq!(cached.len(), 2);
        assert_eq!(missing.len(), 1);
        assert_eq!(missing[0], 2); // index of "text4"
    }

    #[tokio::test]
    async fn test_cache_stats() {
        let cache = EmbeddingCache::new(100);
        let model = "model";

        // Generate some hits and misses
        cache.insert("hit_text", model, vec![0.1]).await;

        cache.get("hit_text", model).await; // hit
        cache.get("miss_text", model).await; // miss

        let stats = cache.stats();
        assert_eq!(stats.hits, 1);
        assert_eq!(stats.misses, 1);
        assert!((stats.hit_rate - 0.5).abs() < 0.01);
    }

    #[tokio::test]
    async fn test_cache_clear() {
        let cache = EmbeddingCache::new(100);

        cache.insert("text", "model", vec![0.1]).await;
        assert!(cache.get("text", "model").await.is_some());

        cache.clear();

        assert!(cache.get("text", "model").await.is_none());
        let stats = cache.stats();
        assert_eq!(stats.hits, 0);
        assert_eq!(stats.misses, 1);
    }
}

#[cfg(test)]
mod model_tests {
    /// Test normalize function
    #[test]
    fn test_normalize_vector() {
        let vec = vec![3.0, 4.0];
        let normalized = normalize(&vec);

        // L2 norm should be 1.0
        let norm: f32 = normalized.iter().map(|x| x * x).sum::<f32>().sqrt();
        assert!((norm - 1.0).abs() < 0.001);

        // Values should be 3/5 and 4/5
        assert!((normalized[0] - 0.6).abs() < 0.001);
        assert!((normalized[1] - 0.8).abs() < 0.001);
    }

    #[test]
    fn test_normalize_zero_vector() {
        let vec = vec![0.0, 0.0, 0.0];
        let normalized = normalize(&vec);

        // Zero vector should remain zero
        assert_eq!(normalized, vec![0.0, 0.0, 0.0]);
    }

    fn normalize(vec: &[f32]) -> Vec<f32> {
        let norm: f32 = vec.iter().map(|x| x * x).sum::<f32>().sqrt();
        if norm > 0.0 {
            vec.iter().map(|x| x / norm).collect()
        } else {
            vec.to_vec()
        }
    }
}

#[cfg(test)]
mod routes_tests {
    use crate::routes::{
        BatchEmbedRequest, BatchEmbedResponse, EmbedRequest, EmbedResponse,
        HealthResponse, MetricsResponse, ModelsResponse, ReadyResponse,
    };

    #[test]
    fn test_embed_request_deserialization() {
        let json = r#"{"text": "hello world"}"#;
        let request: EmbedRequest = serde_json::from_str(json).unwrap();
        assert_eq!(request.text, "hello world");
        assert!(request.model.is_none());
    }

    #[test]
    fn test_embed_request_with_model() {
        let json = r#"{"text": "hello", "model": "all-MiniLM-L6-v2"}"#;
        let request: EmbedRequest = serde_json::from_str(json).unwrap();
        assert_eq!(request.text, "hello");
        assert_eq!(request.model, Some("all-MiniLM-L6-v2".to_string()));
    }

    #[test]
    fn test_batch_embed_request_deserialization() {
        let json = r#"{"texts": ["hello", "world"]}"#;
        let request: BatchEmbedRequest = serde_json::from_str(json).unwrap();
        assert_eq!(request.texts.len(), 2);
    }

    #[test]
    fn test_embed_response_serialization() {
        let response = EmbedResponse {
            embedding: vec![0.1, 0.2, 0.3],
            model: "test-model".to_string(),
            dimension: 3,
            processing_time_ms: 10.5,
            cached: false,
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("\"embedding\":[0.1,0.2,0.3]"));
        assert!(json.contains("\"model\":\"test-model\""));
        assert!(json.contains("\"dimension\":3"));
        assert!(json.contains("\"cached\":false"));
    }

    #[test]
    fn test_batch_embed_response_serialization() {
        let response = BatchEmbedResponse {
            embeddings: vec![vec![0.1], vec![0.2]],
            model: "test-model".to_string(),
            dimension: 1,
            processing_time_ms: 20.0,
            cached_count: 1,
            computed_count: 1,
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("\"cached_count\":1"));
        assert!(json.contains("\"computed_count\":1"));
    }

    #[test]
    fn test_health_response_serialization() {
        let response = HealthResponse {
            status: "healthy".to_string(),
            version: "1.0.0".to_string(),
            uptime_seconds: 3600,
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("\"status\":\"healthy\""));
        assert!(json.contains("\"uptime_seconds\":3600"));
    }

    #[test]
    fn test_ready_response_serialization() {
        let response = ReadyResponse {
            ready: true,
            models_loaded: 2,
            default_model_ready: true,
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("\"ready\":true"));
        assert!(json.contains("\"models_loaded\":2"));
    }
}

#[cfg(test)]
mod config_tests {
    use crate::config::Config;

    #[test]
    fn test_default_config() {
        let config = Config::default();

        assert_eq!(config.host, "0.0.0.0");
        assert_eq!(config.port, 8001);
        assert_eq!(config.default_model, "all-MiniLM-L6-v2");
        assert!(config.cache_size_mb > 0);
        assert!(config.max_batch_size > 0);
    }
}

#[cfg(test)]
mod error_tests {
    use crate::error::EmbeddingError;

    #[test]
    fn test_error_messages() {
        let error = EmbeddingError::ModelNotFound("test-model".to_string());
        assert!(error.to_string().contains("test-model"));

        let error = EmbeddingError::BatchTooLarge(100, 32);
        assert!(error.to_string().contains("100"));
        assert!(error.to_string().contains("32"));
    }
}
