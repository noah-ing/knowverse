//! PDF text extraction using lopdf

use crate::error::{DocProcError, Result};
use super::{BlockType, ContentBlock, DocumentMetadata, ExtractionResult, ProcessingStats};
use lopdf::Document;
use std::io::Cursor;
use std::time::Instant;

/// PDF document extractor
pub struct PdfExtractor;

impl PdfExtractor {
    /// Extract text from PDF content
    pub fn extract(content: &[u8], filename: Option<&str>) -> Result<ExtractionResult> {
        let start = Instant::now();
        let mut warnings = Vec::new();

        // Load PDF document
        let doc = Document::load_from(Cursor::new(content))
            .map_err(|e| DocProcError::ParseError(format!("Failed to parse PDF: {}", e)))?;

        let page_count = doc.get_pages().len();
        let mut all_text = String::new();
        let mut blocks = Vec::new();

        // Extract text from each page
        for (page_num, page_id) in doc.get_pages() {
            match doc.extract_text(&[page_num]) {
                Ok(text) => {
                    let trimmed = text.trim();
                    if !trimmed.is_empty() {
                        blocks.push(ContentBlock {
                            block_type: BlockType::Paragraph,
                            content: trimmed.to_string(),
                            page: Some(page_num as usize),
                            sheet: None,
                            metadata: serde_json::json!({}),
                        });

                        if !all_text.is_empty() {
                            all_text.push_str("\n\n");
                        }
                        all_text.push_str(trimmed);
                    }
                }
                Err(e) => {
                    warnings.push(format!("Failed to extract text from page {}: {}", page_num, e));
                }
            }
        }

        // Try to extract metadata
        let title = doc
            .trailer
            .get(b"Info")
            .and_then(|info| doc.get_dictionary(info.as_reference().ok()?).ok())
            .and_then(|info| info.get(b"Title").ok())
            .and_then(|t| t.as_string().ok())
            .map(|s| String::from_utf8_lossy(s).to_string());

        let author = doc
            .trailer
            .get(b"Info")
            .and_then(|info| doc.get_dictionary(info.as_reference().ok()?).ok())
            .and_then(|info| info.get(b"Author").ok())
            .and_then(|t| t.as_string().ok())
            .map(|s| String::from_utf8_lossy(s).to_string());

        let word_count = all_text.split_whitespace().count();

        Ok(ExtractionResult {
            content: all_text.clone(),
            metadata: DocumentMetadata {
                filename: filename.map(String::from),
                file_type: "pdf".to_string(),
                page_count: Some(page_count),
                sheet_count: None,
                char_count: all_text.len(),
                word_count,
                title,
                author,
            },
            blocks,
            stats: ProcessingStats {
                processing_time_ms: start.elapsed().as_secs_f64() * 1000.0,
                tables_extracted: 0, // lopdf doesn't extract tables directly
                images_found: 0,
                warnings,
            },
        })
    }
}
