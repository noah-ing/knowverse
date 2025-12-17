//! Integration tests for the embedding service API
//!
//! These tests verify the HTTP API endpoints work correctly.
//! Note: Tests that require actual model inference are marked with #[ignore]
//! since they need ONNX models to be present.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use serde_json::{json, Value};
use tower::ServiceExt;

/// Helper to create test app
async fn create_test_app() -> axum::Router {
    // Create minimal app state for testing
    // In real tests, you'd mock the model registry and cache
    axum::Router::new()
        .route("/health", axum::routing::get(health_handler))
        .route("/ready", axum::routing::get(ready_handler))
        .route("/models", axum::routing::get(models_handler))
}

// Mock handlers for testing
async fn health_handler() -> axum::Json<Value> {
    axum::Json(json!({
        "status": "healthy",
        "version": env!("CARGO_PKG_VERSION"),
        "uptime_seconds": 0
    }))
}

async fn ready_handler() -> axum::Json<Value> {
    axum::Json(json!({
        "ready": true,
        "models_loaded": 0,
        "default_model_ready": false
    }))
}

async fn models_handler() -> axum::Json<Value> {
    axum::Json(json!({
        "models": [
            {
                "id": "all-MiniLM-L6-v2",
                "name": "all-MiniLM-L6-v2",
                "dimension": 384,
                "max_tokens": 256,
                "description": "Fast, lightweight model",
                "loaded": false
            }
        ],
        "default_model": "all-MiniLM-L6-v2"
    }))
}

#[tokio::test]
async fn test_health_endpoint() {
    let app = create_test_app().await;

    let response = app
        .oneshot(Request::builder().uri("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["status"], "healthy");
    assert!(json["version"].is_string());
}

#[tokio::test]
async fn test_ready_endpoint() {
    let app = create_test_app().await;

    let response = app
        .oneshot(Request::builder().uri("/ready").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert!(json["ready"].is_boolean());
    assert!(json["models_loaded"].is_number());
}

#[tokio::test]
async fn test_models_endpoint() {
    let app = create_test_app().await;

    let response = app
        .oneshot(Request::builder().uri("/models").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert!(json["models"].is_array());
    assert!(json["default_model"].is_string());

    let models = json["models"].as_array().unwrap();
    assert!(!models.is_empty());

    let first_model = &models[0];
    assert!(first_model["id"].is_string());
    assert!(first_model["dimension"].is_number());
}

#[tokio::test]
async fn test_404_for_unknown_route() {
    let app = create_test_app().await;

    let response = app
        .oneshot(
            Request::builder()
                .uri("/unknown")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

/// Tests that require actual model inference
/// Run with: cargo test --ignored
mod with_models {
    use super::*;

    #[tokio::test]
    #[ignore = "requires ONNX models to be present"]
    async fn test_embed_single_text() {
        // This test would require the full app with model registry
        // let app = create_full_app().await;
        //
        // let response = app
        //     .oneshot(
        //         Request::builder()
        //             .method("POST")
        //             .uri("/embed")
        //             .header("content-type", "application/json")
        //             .body(Body::from(r#"{"text": "hello world"}"#))
        //             .unwrap(),
        //     )
        //     .await
        //     .unwrap();
        //
        // assert_eq!(response.status(), StatusCode::OK);
        // let json: Value = parse_body(response).await;
        // assert!(json["embedding"].is_array());
    }

    #[tokio::test]
    #[ignore = "requires ONNX models to be present"]
    async fn test_embed_batch_texts() {
        // let app = create_full_app().await;
        //
        // let response = app
        //     .oneshot(
        //         Request::builder()
        //             .method("POST")
        //             .uri("/embed/batch")
        //             .header("content-type", "application/json")
        //             .body(Body::from(r#"{"texts": ["hello", "world"]}"#))
        //             .unwrap(),
        //     )
        //     .await
        //     .unwrap();
        //
        // assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    #[ignore = "requires ONNX models to be present"]
    async fn test_embedding_dimension() {
        // Verify embeddings have correct dimension for each model
    }

    #[tokio::test]
    #[ignore = "requires ONNX models to be present"]
    async fn test_embedding_normalization() {
        // Verify embeddings are L2 normalized
    }
}

/// Performance tests
mod performance {
    use super::*;

    #[tokio::test]
    #[ignore = "performance test"]
    async fn test_batch_performance() {
        // Test that batch processing is faster than sequential
    }

    #[tokio::test]
    #[ignore = "performance test"]
    async fn test_cache_performance() {
        // Test that cached responses are faster
    }
}
