//! Error types for the embedding service

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;
use thiserror::Error;

/// Custom error type for the embedding service
#[derive(Error, Debug)]
pub enum EmbeddingError {
    #[error("Model not found: {0}")]
    ModelNotFound(String),

    #[error("Model not loaded: {0}")]
    ModelNotLoaded(String),

    #[error("Tokenization error: {0}")]
    TokenizationError(String),

    #[error("Inference error: {0}")]
    InferenceError(String),

    #[error("Invalid input: {0}")]
    InvalidInput(String),

    #[error("Batch size exceeds limit: {0} > {1}")]
    BatchTooLarge(usize, usize),

    #[error("Model loading error: {0}")]
    ModelLoadError(String),

    #[error("Configuration error: {0}")]
    ConfigError(String),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("Internal error: {0}")]
    Internal(String),
}

impl IntoResponse for EmbeddingError {
    fn into_response(self) -> Response {
        let (status, error_message) = match &self {
            EmbeddingError::ModelNotFound(_) => (StatusCode::NOT_FOUND, self.to_string()),
            EmbeddingError::ModelNotLoaded(_) => (StatusCode::SERVICE_UNAVAILABLE, self.to_string()),
            EmbeddingError::TokenizationError(_) => (StatusCode::BAD_REQUEST, self.to_string()),
            EmbeddingError::InferenceError(_) => {
                (StatusCode::INTERNAL_SERVER_ERROR, self.to_string())
            }
            EmbeddingError::InvalidInput(_) => (StatusCode::BAD_REQUEST, self.to_string()),
            EmbeddingError::BatchTooLarge(_, _) => (StatusCode::BAD_REQUEST, self.to_string()),
            EmbeddingError::ModelLoadError(_) => {
                (StatusCode::INTERNAL_SERVER_ERROR, self.to_string())
            }
            EmbeddingError::ConfigError(_) => {
                (StatusCode::INTERNAL_SERVER_ERROR, self.to_string())
            }
            EmbeddingError::IoError(_) => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
            EmbeddingError::Internal(_) => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
        };

        let body = Json(json!({
            "error": error_message,
            "code": status.as_u16()
        }));

        (status, body).into_response()
    }
}

pub type Result<T> = std::result::Result<T, EmbeddingError>;
