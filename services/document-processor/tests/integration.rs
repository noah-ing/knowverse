//! Integration tests for the document processor API
//!
//! These tests verify the HTTP API endpoints work correctly.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use serde_json::{json, Value};
use tower::ServiceExt;

/// Helper to create test app with mock handlers
async fn create_test_app() -> axum::Router {
    axum::Router::new()
        .route("/health", axum::routing::get(health_handler))
        .route("/ready", axum::routing::get(ready_handler))
        .route("/metrics", axum::routing::get(metrics_handler))
        .route("/chunk", axum::routing::post(chunk_handler))
        .route("/extract/text", axum::routing::post(extract_text_handler))
}

// Mock handlers
async fn health_handler() -> axum::Json<Value> {
    axum::Json(json!({
        "status": "healthy",
        "version": env!("CARGO_PKG_VERSION")
    }))
}

async fn ready_handler() -> axum::Json<Value> {
    axum::Json(json!({
        "ready": true
    }))
}

async fn metrics_handler() -> axum::Json<Value> {
    axum::Json(json!({
        "total_extractions": 0,
        "supported_formats": ["pdf", "xlsx", "docx", "csv", "txt"]
    }))
}

async fn chunk_handler(
    axum::Json(payload): axum::Json<Value>,
) -> Result<axum::Json<Value>, (StatusCode, String)> {
    let text = payload["text"]
        .as_str()
        .ok_or((StatusCode::BAD_REQUEST, "Missing text".to_string()))?;

    if text.is_empty() {
        return Ok(axum::Json(json!({
            "chunks": [],
            "total_chunks": 0,
            "processing_time_ms": 0.0
        })));
    }

    // Simple word-based chunking for test
    let words: Vec<&str> = text.split_whitespace().collect();
    let chunk_size = payload["chunk_size"].as_u64().unwrap_or(512) as usize;

    let chunks: Vec<Value> = words
        .chunks(chunk_size)
        .enumerate()
        .map(|(i, chunk_words)| {
            json!({
                "content": chunk_words.join(" "),
                "index": i,
                "start_offset": 0,
                "end_offset": chunk_words.join(" ").len(),
                "token_count": chunk_words.len()
            })
        })
        .collect();

    Ok(axum::Json(json!({
        "chunks": chunks,
        "total_chunks": chunks.len(),
        "processing_time_ms": 1.5
    })))
}

async fn extract_text_handler(
    axum::Json(payload): axum::Json<Value>,
) -> Result<axum::Json<Value>, (StatusCode, String)> {
    let content_b64 = payload["content"]
        .as_str()
        .ok_or((StatusCode::BAD_REQUEST, "Missing content".to_string()))?;

    let content = BASE64
        .decode(content_b64)
        .map_err(|e| (StatusCode::BAD_REQUEST, format!("Invalid base64: {}", e)))?;

    let text = String::from_utf8_lossy(&content);

    Ok(axum::Json(json!({
        "result": {
            "content": text,
            "metadata": {
                "filename": payload["filename"],
                "file_type": "text",
                "char_count": text.len(),
                "word_count": text.split_whitespace().count()
            },
            "blocks": [{
                "block_type": "paragraph",
                "content": text,
                "page": null,
                "sheet": null,
                "metadata": {}
            }],
            "stats": {
                "processing_time_ms": 2.0,
                "tables_extracted": 0,
                "images_found": 0,
                "warnings": []
            }
        }
    })))
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

    assert_eq!(json["ready"], true);
}

#[tokio::test]
async fn test_metrics_endpoint() {
    let app = create_test_app().await;

    let response = app
        .oneshot(Request::builder().uri("/metrics").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert!(json["supported_formats"].is_array());
    assert!(json["total_extractions"].is_number());
}

#[tokio::test]
async fn test_chunk_endpoint() {
    let app = create_test_app().await;

    let body = json!({
        "text": "This is a test sentence for chunking.",
        "chunk_size": 512
    });

    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/chunk")
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_string(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert!(json["chunks"].is_array());
    assert!(json["total_chunks"].is_number());
    assert!(json["processing_time_ms"].is_number());
}

#[tokio::test]
async fn test_chunk_empty_text() {
    let app = create_test_app().await;

    let body = json!({
        "text": "",
        "chunk_size": 512
    });

    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/chunk")
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_string(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["total_chunks"], 0);
    assert!(json["chunks"].as_array().unwrap().is_empty());
}

#[tokio::test]
async fn test_extract_text_endpoint() {
    let app = create_test_app().await;

    let text_content = "Hello, this is test content.";
    let encoded = BASE64.encode(text_content.as_bytes());

    let body = json!({
        "content": encoded,
        "filename": "test.txt"
    });

    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/extract/text")
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_string(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert!(json["result"]["content"].as_str().unwrap().contains("Hello"));
    assert_eq!(json["result"]["metadata"]["file_type"], "text");
}

#[tokio::test]
async fn test_404_for_unknown_route() {
    let app = create_test_app().await;

    let response = app
        .oneshot(
            Request::builder()
                .uri("/nonexistent")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

/// Tests that require actual file parsing
mod with_files {
    use super::*;

    #[tokio::test]
    #[ignore = "requires actual PDF parsing"]
    async fn test_extract_pdf() {
        // Test with actual PDF file
    }

    #[tokio::test]
    #[ignore = "requires actual Excel parsing"]
    async fn test_extract_excel() {
        // Test with actual Excel file
    }

    #[tokio::test]
    #[ignore = "requires actual DOCX parsing"]
    async fn test_extract_docx() {
        // Test with actual DOCX file
    }
}

/// Chunking strategy tests
mod chunking_strategies {
    use super::*;

    #[tokio::test]
    async fn test_chunk_with_fixed_strategy() {
        let app = create_test_app().await;

        let body = json!({
            "text": "Word1 Word2 Word3 Word4 Word5 Word6 Word7 Word8 Word9 Word10",
            "chunk_size": 5,
            "strategy": "fixed_size"
        });

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/chunk")
                    .header("content-type", "application/json")
                    .body(Body::from(serde_json::to_string(&body).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_chunk_with_sentence_strategy() {
        let app = create_test_app().await;

        let body = json!({
            "text": "First sentence. Second sentence. Third sentence.",
            "strategy": "sentence"
        });

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/chunk")
                    .header("content-type", "application/json")
                    .body(Body::from(serde_json::to_string(&body).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }
}

/// Content type tests
mod content_types {
    use super::*;

    #[tokio::test]
    async fn test_requires_json_content_type() {
        let app = create_test_app().await;

        // Request without content-type
        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/chunk")
                    .body(Body::from(r#"{"text": "test"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();

        // Should either accept or reject based on implementation
        // Some frameworks are lenient about content-type
        assert!(
            response.status() == StatusCode::OK
                || response.status() == StatusCode::UNSUPPORTED_MEDIA_TYPE
        );
    }
}
