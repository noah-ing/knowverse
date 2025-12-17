//! Knowverse Document Processor
//!
//! WASM-sandboxed document processing service for extracting text
//! from PDF, Excel, DOCX, and other document formats.

mod config;
mod error;
mod extractors;
mod routes;
mod sandbox;

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
    limit::RequestBodyLimitLayer,
    trace::TraceLayer,
};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use crate::config::Config;
use crate::sandbox::SandboxManager;

/// Shared application state
pub struct AppState {
    pub sandbox: SandboxManager,
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
                .unwrap_or_else(|_| "knowverse_docproc=info,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("Starting Knowverse Document Processor");

    // Load configuration
    let config = Config::from_env()?;
    tracing::info!("Configuration loaded: {:?}", config);

    // Initialize sandbox manager
    let sandbox = SandboxManager::new(&config)?;
    tracing::info!("Sandbox manager initialized");

    // Create shared state
    let state = Arc::new(AppState { sandbox, config: config.clone() });

    // Build router
    let app = Router::new()
        // Health endpoints
        .route("/health", get(routes::health))
        .route("/ready", get(routes::ready))
        // Extraction endpoints
        .route("/extract", post(routes::extract_auto))
        .route("/extract/pdf", post(routes::extract_pdf))
        .route("/extract/excel", post(routes::extract_excel))
        .route("/extract/docx", post(routes::extract_docx))
        .route("/extract/csv", post(routes::extract_csv))
        .route("/extract/text", post(routes::extract_text))
        // Chunking endpoint
        .route("/chunk", post(routes::chunk_text))
        // Metrics
        .route("/metrics", get(routes::metrics))
        // Add middleware
        .layer(TraceLayer::new_for_http())
        .layer(CompressionLayer::new())
        .layer(RequestBodyLimitLayer::new(config.max_file_size_mb * 1024 * 1024))
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
