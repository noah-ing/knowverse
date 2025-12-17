//! API routes for the document processor

use crate::error::{DocProcError, Result};
use crate::extractors::{
    detect_file_type, ChunkStrategy, CsvExtractor, DocxExtractor, ExcelExtractor,
    ExtractionResult, FileType, PdfExtractor, TextChunk, TextChunker, TextExtractor,
};
use crate::AppState;
use axum::{
    extract::{Multipart, State},
    Json,
};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Instant;

// ============================================================================
// Request/Response Types
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct ExtractRequest {
    /// Base64-encoded file content
    pub content: String,
    /// Original filename (for type detection)
    pub filename: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ExtractResponse {
    pub result: ExtractionResult,
}

#[derive(Debug, Deserialize)]
pub struct ChunkRequest {
    /// Text to chunk
    pub text: String,
    /// Chunk size (tokens, default: 512)
    pub chunk_size: Option<usize>,
    /// Chunk overlap (tokens, default: 64)
    pub chunk_overlap: Option<usize>,
    /// Chunking strategy
    pub strategy: Option<ChunkStrategy>,
}

#[derive(Debug, Serialize)]
pub struct ChunkResponse {
    pub chunks: Vec<TextChunk>,
    pub total_chunks: usize,
    pub processing_time_ms: f64,
}

#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
}

#[derive(Debug, Serialize)]
pub struct ReadyResponse {
    pub ready: bool,
}

#[derive(Debug, Serialize)]
pub struct MetricsResponse {
    pub total_extractions: u64,
    pub supported_formats: Vec<String>,
}

// ============================================================================
// Health Endpoints
// ============================================================================

/// Health check endpoint
pub async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}

/// Readiness check endpoint
pub async fn ready() -> Json<ReadyResponse> {
    Json(ReadyResponse { ready: true })
}

// ============================================================================
// Extraction Endpoints
// ============================================================================

/// Auto-detect file type and extract
pub async fn extract_auto(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ExtractRequest>,
) -> Result<Json<ExtractResponse>> {
    let _permit = state.sandbox.acquire_permit().await?;

    let content = BASE64
        .decode(&request.content)
        .map_err(|e| DocProcError::InvalidInput(format!("Invalid base64: {}", e)))?;

    let file_type = detect_file_type(&content, request.filename.as_deref())?;

    let result = match file_type {
        FileType::Pdf => PdfExtractor::extract(&content, request.filename.as_deref())?,
        FileType::Excel => ExcelExtractor::extract(&content, request.filename.as_deref())?,
        FileType::Docx => DocxExtractor::extract(&content, request.filename.as_deref())?,
        FileType::Csv => CsvExtractor::extract(&content, request.filename.as_deref())?,
        FileType::Text | FileType::Json | FileType::Xml => {
            TextExtractor::extract(&content, request.filename.as_deref())?
        }
    };

    Ok(Json(ExtractResponse { result }))
}

/// Extract PDF
pub async fn extract_pdf(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ExtractRequest>,
) -> Result<Json<ExtractResponse>> {
    let _permit = state.sandbox.acquire_permit().await?;

    let content = BASE64
        .decode(&request.content)
        .map_err(|e| DocProcError::InvalidInput(format!("Invalid base64: {}", e)))?;

    let result = PdfExtractor::extract(&content, request.filename.as_deref())?;
    Ok(Json(ExtractResponse { result }))
}

/// Extract Excel
pub async fn extract_excel(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ExtractRequest>,
) -> Result<Json<ExtractResponse>> {
    let _permit = state.sandbox.acquire_permit().await?;

    let content = BASE64
        .decode(&request.content)
        .map_err(|e| DocProcError::InvalidInput(format!("Invalid base64: {}", e)))?;

    let result = ExcelExtractor::extract(&content, request.filename.as_deref())?;
    Ok(Json(ExtractResponse { result }))
}

/// Extract DOCX
pub async fn extract_docx(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ExtractRequest>,
) -> Result<Json<ExtractResponse>> {
    let _permit = state.sandbox.acquire_permit().await?;

    let content = BASE64
        .decode(&request.content)
        .map_err(|e| DocProcError::InvalidInput(format!("Invalid base64: {}", e)))?;

    let result = DocxExtractor::extract(&content, request.filename.as_deref())?;
    Ok(Json(ExtractResponse { result }))
}

/// Extract CSV
pub async fn extract_csv(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ExtractRequest>,
) -> Result<Json<ExtractResponse>> {
    let _permit = state.sandbox.acquire_permit().await?;

    let content = BASE64
        .decode(&request.content)
        .map_err(|e| DocProcError::InvalidInput(format!("Invalid base64: {}", e)))?;

    let result = CsvExtractor::extract(&content, request.filename.as_deref())?;
    Ok(Json(ExtractResponse { result }))
}

/// Extract plain text
pub async fn extract_text(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ExtractRequest>,
) -> Result<Json<ExtractResponse>> {
    let _permit = state.sandbox.acquire_permit().await?;

    let content = BASE64
        .decode(&request.content)
        .map_err(|e| DocProcError::InvalidInput(format!("Invalid base64: {}", e)))?;

    let result = TextExtractor::extract(&content, request.filename.as_deref())?;
    Ok(Json(ExtractResponse { result }))
}

// ============================================================================
// Chunking Endpoint
// ============================================================================

/// Chunk text for embedding generation
pub async fn chunk_text(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ChunkRequest>,
) -> Result<Json<ChunkResponse>> {
    let start = Instant::now();

    let chunk_size = request.chunk_size.unwrap_or(state.config.default_chunk_size);
    let chunk_overlap = request
        .chunk_overlap
        .unwrap_or(state.config.default_chunk_overlap);
    let strategy = request.strategy.unwrap_or_default();

    let chunker = TextChunker::new(chunk_size, chunk_overlap);
    let chunks = chunker.chunk(&request.text, strategy)?;

    Ok(Json(ChunkResponse {
        total_chunks: chunks.len(),
        chunks,
        processing_time_ms: start.elapsed().as_secs_f64() * 1000.0,
    }))
}

// ============================================================================
// Metrics Endpoint
// ============================================================================

/// Get service metrics
pub async fn metrics() -> Json<MetricsResponse> {
    Json(MetricsResponse {
        total_extractions: 0, // TODO: Track actual metrics
        supported_formats: vec![
            "pdf".to_string(),
            "xlsx".to_string(),
            "xls".to_string(),
            "docx".to_string(),
            "csv".to_string(),
            "txt".to_string(),
            "md".to_string(),
            "json".to_string(),
            "xml".to_string(),
        ],
    })
}
