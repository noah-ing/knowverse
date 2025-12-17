//! API routes for the embedding service

use crate::cache::CacheStats;
use crate::error::{EmbeddingError, Result};
use crate::models::ModelInfo;
use crate::AppState;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Instant;

// ============================================================================
// Request/Response Types
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct EmbedRequest {
    /// Text to embed
    pub text: String,
    /// Model to use (optional, defaults to configured default)
    pub model: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct BatchEmbedRequest {
    /// Texts to embed
    pub texts: Vec<String>,
    /// Model to use (optional)
    pub model: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct EmbedResponse {
    /// The embedding vector
    pub embedding: Vec<f32>,
    /// Model used
    pub model: String,
    /// Dimension of the embedding
    pub dimension: usize,
    /// Processing time in milliseconds
    pub processing_time_ms: f64,
    /// Whether result came from cache
    pub cached: bool,
}

#[derive(Debug, Serialize)]
pub struct BatchEmbedResponse {
    /// The embedding vectors
    pub embeddings: Vec<Vec<f32>>,
    /// Model used
    pub model: String,
    /// Dimension of the embeddings
    pub dimension: usize,
    /// Processing time in milliseconds
    pub processing_time_ms: f64,
    /// Number of embeddings from cache
    pub cached_count: usize,
    /// Number of embeddings computed
    pub computed_count: usize,
}

#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
    pub uptime_seconds: u64,
}

#[derive(Debug, Serialize)]
pub struct ReadyResponse {
    pub ready: bool,
    pub models_loaded: usize,
    pub default_model_ready: bool,
}

#[derive(Debug, Serialize)]
pub struct MetricsResponse {
    pub cache: CacheStats,
    pub models_loaded: usize,
    pub total_requests: u64,
}

#[derive(Debug, Serialize)]
pub struct ModelsResponse {
    pub models: Vec<ModelInfo>,
    pub default_model: String,
}

#[derive(Debug, Serialize)]
pub struct LoadModelResponse {
    pub success: bool,
    pub model: String,
    pub message: String,
}

// ============================================================================
// Health Endpoints
// ============================================================================

/// Health check endpoint
pub async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        uptime_seconds: 0, // TODO: Track actual uptime
    })
}

/// Readiness check endpoint
pub async fn ready(State(state): State<Arc<AppState>>) -> Json<ReadyResponse> {
    let default_loaded = state
        .model_registry
        .is_loaded(&state.config.default_model)
        .await;

    let models = state.model_registry.available_models();
    let loaded_count = models.iter().filter(|m| m.loaded).count();

    Json(ReadyResponse {
        ready: default_loaded,
        models_loaded: loaded_count,
        default_model_ready: default_loaded,
    })
}

// ============================================================================
// Embedding Endpoints
// ============================================================================

/// Generate embedding for a single text
pub async fn embed_single(
    State(state): State<Arc<AppState>>,
    Json(request): Json<EmbedRequest>,
) -> Result<Json<EmbedResponse>> {
    let start = Instant::now();
    let model_id = request.model.unwrap_or_else(|| state.config.default_model.clone());

    // Check cache first
    if let Some(cached_embedding) = state.cache.get(&request.text, &model_id).await {
        let model_info = state
            .model_registry
            .get_model_info(&model_id)
            .ok_or_else(|| EmbeddingError::ModelNotFound(model_id.clone()))?;

        return Ok(Json(EmbedResponse {
            embedding: cached_embedding,
            model: model_id,
            dimension: model_info.dimension,
            processing_time_ms: start.elapsed().as_secs_f64() * 1000.0,
            cached: true,
        }));
    }

    // Get model and generate embedding
    let model = state.model_registry.get_model(&model_id).await?;
    let embedding = model.embed_single(&request.text)?;
    let dimension = embedding.len();

    // Cache the result
    state
        .cache
        .insert(&request.text, &model_id, embedding.clone())
        .await;

    Ok(Json(EmbedResponse {
        embedding,
        model: model_id,
        dimension,
        processing_time_ms: start.elapsed().as_secs_f64() * 1000.0,
        cached: false,
    }))
}

/// Generate embeddings for a batch of texts
pub async fn embed_batch(
    State(state): State<Arc<AppState>>,
    Json(request): Json<BatchEmbedRequest>,
) -> Result<Json<BatchEmbedResponse>> {
    let start = Instant::now();

    if request.texts.is_empty() {
        return Ok(Json(BatchEmbedResponse {
            embeddings: vec![],
            model: state.config.default_model.clone(),
            dimension: 0,
            processing_time_ms: 0.0,
            cached_count: 0,
            computed_count: 0,
        }));
    }

    // Check batch size
    if request.texts.len() > state.config.max_batch_size {
        return Err(EmbeddingError::BatchTooLarge(
            request.texts.len(),
            state.config.max_batch_size,
        ));
    }

    let model_id = request.model.unwrap_or_else(|| state.config.default_model.clone());

    // Check cache for existing embeddings
    let (cached, missing_indices) = state.cache.get_batch(&request.texts, &model_id).await;
    let cached_count = cached.len();

    // If all cached, return immediately
    if missing_indices.is_empty() {
        let model_info = state
            .model_registry
            .get_model_info(&model_id)
            .ok_or_else(|| EmbeddingError::ModelNotFound(model_id.clone()))?;

        // Reconstruct embeddings in original order
        let mut embeddings: Vec<Vec<f32>> = vec![vec![]; request.texts.len()];
        for (idx, embedding) in cached {
            embeddings[idx] = embedding;
        }

        return Ok(Json(BatchEmbedResponse {
            embeddings,
            model: model_id,
            dimension: model_info.dimension,
            processing_time_ms: start.elapsed().as_secs_f64() * 1000.0,
            cached_count,
            computed_count: 0,
        }));
    }

    // Get model and generate missing embeddings
    let model = state.model_registry.get_model(&model_id).await?;

    let missing_texts: Vec<String> = missing_indices
        .iter()
        .map(|&idx| request.texts[idx].clone())
        .collect();

    let computed_embeddings = model.embed(&missing_texts)?;
    let computed_count = computed_embeddings.len();

    // Cache computed embeddings
    state
        .cache
        .insert_batch(&missing_texts, &model_id, &computed_embeddings)
        .await;

    // Reconstruct full result in original order
    let mut embeddings: Vec<Vec<f32>> = vec![vec![]; request.texts.len()];

    // Fill in cached results
    for (idx, embedding) in cached {
        embeddings[idx] = embedding;
    }

    // Fill in computed results
    for (i, &original_idx) in missing_indices.iter().enumerate() {
        embeddings[original_idx] = computed_embeddings[i].clone();
    }

    let dimension = embeddings.first().map(|e| e.len()).unwrap_or(0);

    Ok(Json(BatchEmbedResponse {
        embeddings,
        model: model_id,
        dimension,
        processing_time_ms: start.elapsed().as_secs_f64() * 1000.0,
        cached_count,
        computed_count,
    }))
}

// ============================================================================
// Model Management Endpoints
// ============================================================================

/// List available models
pub async fn list_models(State(state): State<Arc<AppState>>) -> Json<ModelsResponse> {
    let models = state.model_registry.available_models();

    Json(ModelsResponse {
        models,
        default_model: state.config.default_model.clone(),
    })
}

/// Load a specific model
pub async fn load_model(
    State(state): State<Arc<AppState>>,
    Path(model_id): Path<String>,
) -> Result<Json<LoadModelResponse>> {
    state.model_registry.load_model(&model_id).await?;

    Ok(Json(LoadModelResponse {
        success: true,
        model: model_id.clone(),
        message: format!("Model {} loaded successfully", model_id),
    }))
}

// ============================================================================
// Metrics Endpoint
// ============================================================================

/// Get service metrics
pub async fn metrics(State(state): State<Arc<AppState>>) -> Json<MetricsResponse> {
    let cache_stats = state.cache.stats();
    let models_loaded = state
        .model_registry
        .available_models()
        .iter()
        .filter(|m| m.loaded)
        .count();

    Json(MetricsResponse {
        cache: cache_stats,
        models_loaded,
        total_requests: cache_stats.hits + cache_stats.misses,
    })
}
