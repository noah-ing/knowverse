//! CSV text extraction

use crate::error::{DocProcError, Result};
use super::{BlockType, ContentBlock, DocumentMetadata, ExtractionResult, ProcessingStats};
use std::time::Instant;

/// CSV document extractor
pub struct CsvExtractor;

impl CsvExtractor {
    /// Extract text from CSV content
    pub fn extract(content: &[u8], filename: Option<&str>) -> Result<ExtractionResult> {
        let start = Instant::now();
        let warnings = Vec::new();

        // Convert to string (handle encoding)
        let text = String::from_utf8_lossy(content);

        // Parse CSV
        let mut reader = csv::ReaderBuilder::new()
            .flexible(true) // Allow variable column counts
            .has_headers(true)
            .from_reader(text.as_bytes());

        let mut all_text = String::new();
        let mut blocks = Vec::new();
        let mut row_count = 0;

        // Get headers
        let headers: Vec<String> = reader
            .headers()
            .map(|h| h.iter().map(|s| s.to_string()).collect())
            .unwrap_or_default();

        if !headers.is_empty() {
            // Build markdown table header
            all_text.push_str(&format!("| {} |\n", headers.join(" | ")));
            let separator: Vec<&str> = (0..headers.len()).map(|_| "---").collect();
            all_text.push_str(&format!("| {} |\n", separator.join(" | ")));
        }

        // Process rows
        for result in reader.records() {
            match result {
                Ok(record) => {
                    let cells: Vec<&str> = record.iter().collect();
                    let row_text = format!("| {} |", cells.join(" | "));
                    all_text.push_str(&row_text);
                    all_text.push('\n');

                    blocks.push(ContentBlock {
                        block_type: BlockType::Row,
                        content: cells.join("\t"),
                        page: None,
                        sheet: None,
                        metadata: serde_json::json!({
                            "row_index": row_count,
                            "cell_count": cells.len()
                        }),
                    });

                    row_count += 1;
                }
                Err(e) => {
                    tracing::warn!("CSV parsing error at row {}: {}", row_count, e);
                }
            }
        }

        let word_count = all_text.split_whitespace().count();

        Ok(ExtractionResult {
            content: all_text.clone(),
            metadata: DocumentMetadata {
                filename: filename.map(String::from),
                file_type: "csv".to_string(),
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
                tables_extracted: 1,
                images_found: 0,
                warnings,
            },
        })
    }
}
