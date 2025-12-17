//! Knowverse Embedding Service
//!
//! High-performance ONNX-based embedding generation service.
//! Provides 10-50x faster inference compared to Python alternatives.

mod cache;
mod config;
mod error;
mod models;
mod routes;

#[cfg(test)]
mod tests;

use axum::{
    routing::{get, post},
    Router,
};
use std::sync::Arc;
use tokio::net::TcpListener;
use tower_http::{
    compression::CompressionLayer,
    cors::{Any, CorsLayer},
    trace::TraceLayer,
};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use crate::cache::EmbeddingCache;
use crate::config::Config;
use crate::models::ModelRegistry;

/// Shared application state
pub struct AppState {
    pub model_registry: ModelRegistry,
    pub cache: EmbeddingCache,
    pub config: Config,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load environment variables
    dotenvy::dotenv().ok();

    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "knowverse_embedding=info,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("Starting Knowverse Embedding Service");

    // Load configuration
    let config = Config::from_env()?;
    tracing::info!("Configuration loaded: {:?}", config);

    // Initialize model registry
    let model_registry = ModelRegistry::new(&config).await?;
    tracing::info!(
        "Model registry initialized with {} models",
        model_registry.available_models().len()
    );

    // Initialize cache
    let cache = EmbeddingCache::new(config.cache_size_mb);
    tracing::info!("Embedding cache initialized ({}MB)", config.cache_size_mb);

    // Create shared state
    let state = Arc::new(AppState {
        model_registry,
        cache,
        config: config.clone(),
    });

    // Build router
    let app = Router::new()
        // Health endpoints
        .route("/health", get(routes::health))
        .route("/ready", get(routes::ready))
        // Embedding endpoints
        .route("/embed", post(routes::embed_single))
        .route("/embed/batch", post(routes::embed_batch))
        // Model management
        .route("/models", get(routes::list_models))
        .route("/models/:model_id/load", post(routes::load_model))
        // Metrics
        .route("/metrics", get(routes::metrics))
        // Add middleware
        .layer(TraceLayer::new_for_http())
        .layer(CompressionLayer::new())
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        )
        .with_state(state);

    // Start server
    let addr = format!("{}:{}", config.host, config.port);
    let listener = TcpListener::bind(&addr).await?;
    tracing::info!("Listening on {}", addr);

    axum::serve(listener, app).await?;

    Ok(())
}
