//! Error types for the document processor

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;
use thiserror::Error;

/// Custom error type for the document processor
#[derive(Error, Debug)]
pub enum DocProcError {
    #[error("Unsupported file type: {0}")]
    UnsupportedFileType(String),

    #[error("File too large: {0}MB exceeds {1}MB limit")]
    FileTooLarge(usize, usize),

    #[error("Extraction failed: {0}")]
    ExtractionFailed(String),

    #[error("Parsing error: {0}")]
    ParseError(String),

    #[error("Invalid input: {0}")]
    InvalidInput(String),

    #[error("Sandbox error: {0}")]
    SandboxError(String),

    #[error("Timeout: processing exceeded {0} seconds")]
    Timeout(u64),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("Internal error: {0}")]
    Internal(String),
}

impl IntoResponse for DocProcError {
    fn into_response(self) -> Response {
        let (status, error_message) = match &self {
            DocProcError::UnsupportedFileType(_) => {
                (StatusCode::UNSUPPORTED_MEDIA_TYPE, self.to_string())
            }
            DocProcError::FileTooLarge(_, _) => {
                (StatusCode::PAYLOAD_TOO_LARGE, self.to_string())
            }
            DocProcError::ExtractionFailed(_) => {
                (StatusCode::UNPROCESSABLE_ENTITY, self.to_string())
            }
            DocProcError::ParseError(_) => (StatusCode::UNPROCESSABLE_ENTITY, self.to_string()),
            DocProcError::InvalidInput(_) => (StatusCode::BAD_REQUEST, self.to_string()),
            DocProcError::SandboxError(_) => {
                (StatusCode::INTERNAL_SERVER_ERROR, self.to_string())
            }
            DocProcError::Timeout(_) => (StatusCode::REQUEST_TIMEOUT, self.to_string()),
            DocProcError::IoError(_) => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
            DocProcError::Internal(_) => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
        };

        let body = Json(json!({
            "error": error_message,
            "code": status.as_u16()
        }));

        (status, body).into_response()
    }
}

pub type Result<T> = std::result::Result<T, DocProcError>;
