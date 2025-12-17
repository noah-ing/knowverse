//! Plain text extraction with encoding detection

use crate::error::{DocProcError, Result};
use super::{BlockType, ContentBlock, DocumentMetadata, ExtractionResult, ProcessingStats};
use encoding_rs::*;
use std::time::Instant;

/// Plain text extractor
pub struct TextExtractor;

impl TextExtractor {
    /// Extract text from plain text content
    pub fn extract(content: &[u8], filename: Option<&str>) -> Result<ExtractionResult> {
        let start = Instant::now();
        let warnings = Vec::new();

        // Detect encoding and decode
        let (text, encoding_used, had_errors) = Self::decode_with_detection(content);

        let mut all_text = text.trim().to_string();
        let mut blocks = Vec::new();

        // Split into paragraphs
        for (idx, paragraph) in all_text.split("\n\n").enumerate() {
            let trimmed = paragraph.trim();
            if !trimmed.is_empty() {
                // Detect if it's a heading (simple heuristic)
                let block_type = if trimmed.starts_with('#') ||
                    (trimmed.len() < 100 && !trimmed.contains('.') && idx < 3) {
                    BlockType::Heading
                } else {
                    BlockType::Paragraph
                };

                blocks.push(ContentBlock {
                    block_type,
                    content: trimmed.to_string(),
                    page: None,
                    sheet: None,
                    metadata: serde_json::json!({
                        "paragraph_index": idx
                    }),
                });
            }
        }

        let word_count = all_text.split_whitespace().count();

        // Detect file subtype from extension
        let file_type = filename
            .and_then(|f| f.rsplit('.').next())
            .map(|ext| ext.to_lowercase())
            .unwrap_or_else(|| "text".to_string());

        Ok(ExtractionResult {
            content: all_text.clone(),
            metadata: DocumentMetadata {
                filename: filename.map(String::from),
                file_type,
                page_count: None,
                sheet_count: None,
                char_count: all_text.len(),
                word_count,
                title: None,
                author: None,
            },
            blocks,
            stats: ProcessingStats {
                processing_time_ms: start.elapsed().as_secs_f64() * 1000.0,
                tables_extracted: 0,
                images_found: 0,
                warnings: if had_errors {
                    vec![format!("Encoding errors detected, decoded as {}", encoding_used)]
                } else {
                    warnings
                },
            },
        })
    }

    /// Detect encoding and decode bytes to string
    fn decode_with_detection(content: &[u8]) -> (String, &'static str, bool) {
        // Try UTF-8 first (most common)
        if let Ok(text) = std::str::from_utf8(content) {
            return (text.to_string(), "UTF-8", false);
        }

        // Check for BOM
        if content.starts_with(&[0xEF, 0xBB, 0xBF]) {
            // UTF-8 with BOM
            let (text, _, had_errors) = UTF_8.decode(&content[3..]);
            return (text.to_string(), "UTF-8-BOM", had_errors);
        }

        if content.starts_with(&[0xFF, 0xFE]) {
            // UTF-16 LE
            let (text, _, had_errors) = UTF_16LE.decode(&content[2..]);
            return (text.to_string(), "UTF-16LE", had_errors);
        }

        if content.starts_with(&[0xFE, 0xFF]) {
            // UTF-16 BE
            let (text, _, had_errors) = UTF_16BE.decode(&content[2..]);
            return (text.to_string(), "UTF-16BE", had_errors);
        }

        // Try common encodings
        let encodings: &[(Encoding, &'static str)] = &[
            (UTF_8, "UTF-8"),
            (WINDOWS_1252, "Windows-1252"),
            (ISO_8859_1, "ISO-8859-1"),
        ];

        for (encoding, name) in encodings {
            let (text, _, had_errors) = encoding.decode(content);
            if !had_errors {
                return (text.to_string(), name, false);
            }
        }

        // Fallback: decode as UTF-8 with replacement
        let (text, _, had_errors) = UTF_8.decode(content);
        (text.to_string(), "UTF-8 (lossy)", had_errors)
    }
}
