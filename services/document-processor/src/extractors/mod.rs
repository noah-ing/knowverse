//! Document extractors for various file formats

mod pdf;
mod excel;
mod docx;
mod csv;
mod text;
mod chunker;

pub use pdf::PdfExtractor;
pub use excel::ExcelExtractor;
pub use docx::DocxExtractor;
pub use csv::CsvExtractor;
pub use text::TextExtractor;
pub use chunker::TextChunker;

use crate::error::{DocProcError, Result};
use serde::{Deserialize, Serialize};

/// Extracted document content
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractionResult {
    /// Extracted text content
    pub content: String,
    /// Document metadata
    pub metadata: DocumentMetadata,
    /// Structured content blocks (if available)
    pub blocks: Vec<ContentBlock>,
    /// Processing statistics
    pub stats: ProcessingStats,
}

/// Document metadata
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DocumentMetadata {
    /// Original filename
    pub filename: Option<String>,
    /// Detected file type
    pub file_type: String,
    /// Number of pages (for PDF/DOCX)
    pub page_count: Option<usize>,
    /// Number of sheets (for Excel)
    pub sheet_count: Option<usize>,
    /// Character count
    pub char_count: usize,
    /// Word count (approximate)
    pub word_count: usize,
    /// Document title (if available)
    pub title: Option<String>,
    /// Document author (if available)
    pub author: Option<String>,
}

/// Content block (paragraph, table, etc.)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentBlock {
    /// Block type
    pub block_type: BlockType,
    /// Block content
    pub content: String,
    /// Page number (if applicable)
    pub page: Option<usize>,
    /// Sheet name (if applicable)
    pub sheet: Option<String>,
    /// Additional block metadata
    pub metadata: serde_json::Value,
}

/// Type of content block
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BlockType {
    Paragraph,
    Heading,
    Table,
    List,
    Code,
    Image,
    Header,
    Footer,
    Cell,
    Row,
}

/// Processing statistics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProcessingStats {
    /// Processing time in milliseconds
    pub processing_time_ms: f64,
    /// Number of tables extracted
    pub tables_extracted: usize,
    /// Number of images found
    pub images_found: usize,
    /// Errors encountered (non-fatal)
    pub warnings: Vec<String>,
}

/// Detect file type from content
pub fn detect_file_type(content: &[u8], filename: Option<&str>) -> Result<FileType> {
    // Try magic number detection first
    if let Some(kind) = infer::get(content) {
        return match kind.mime_type() {
            "application/pdf" => Ok(FileType::Pdf),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => {
                Ok(FileType::Excel)
            }
            "application/vnd.ms-excel" => Ok(FileType::Excel),
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => {
                Ok(FileType::Docx)
            }
            "text/csv" => Ok(FileType::Csv),
            "text/plain" => Ok(FileType::Text),
            _ => {
                // Fall back to extension
                detect_by_extension(filename)
            }
        };
    }

    // Fall back to extension-based detection
    detect_by_extension(filename)
}

fn detect_by_extension(filename: Option<&str>) -> Result<FileType> {
    let filename = filename.ok_or_else(|| {
        DocProcError::UnsupportedFileType("Cannot determine file type".to_string())
    })?;

    let ext = filename
        .rsplit('.')
        .next()
        .map(|s| s.to_lowercase())
        .ok_or_else(|| DocProcError::UnsupportedFileType("No file extension".to_string()))?;

    match ext.as_str() {
        "pdf" => Ok(FileType::Pdf),
        "xlsx" | "xls" | "xlsm" | "xlsb" => Ok(FileType::Excel),
        "docx" | "doc" => Ok(FileType::Docx),
        "csv" => Ok(FileType::Csv),
        "txt" | "md" | "rst" | "rtf" => Ok(FileType::Text),
        "json" => Ok(FileType::Json),
        "xml" | "html" | "htm" => Ok(FileType::Xml),
        _ => Err(DocProcError::UnsupportedFileType(format!(
            "Unsupported extension: {}",
            ext
        ))),
    }
}

/// Supported file types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileType {
    Pdf,
    Excel,
    Docx,
    Csv,
    Text,
    Json,
    Xml,
}

impl std::fmt::Display for FileType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FileType::Pdf => write!(f, "pdf"),
            FileType::Excel => write!(f, "excel"),
            FileType::Docx => write!(f, "docx"),
            FileType::Csv => write!(f, "csv"),
            FileType::Text => write!(f, "text"),
            FileType::Json => write!(f, "json"),
            FileType::Xml => write!(f, "xml"),
        }
    }
}
