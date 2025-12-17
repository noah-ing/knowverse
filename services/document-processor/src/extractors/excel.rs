//! Excel extraction using calamine (Rust/calamine - 10x faster than openpyxl)

use crate::error::{DocProcError, Result};
use super::{BlockType, ContentBlock, DocumentMetadata, ExtractionResult, ProcessingStats};
use calamine::{open_workbook_auto_from_rs, Reader, Sheets};
use std::io::Cursor;
use std::time::Instant;

/// Excel document extractor
pub struct ExcelExtractor;

impl ExcelExtractor {
    /// Extract text from Excel content
    pub fn extract(content: &[u8], filename: Option<&str>) -> Result<ExtractionResult> {
        let start = Instant::now();
        let mut warnings = Vec::new();

        // Open workbook
        let cursor = Cursor::new(content);
        let mut workbook: Sheets<_> = open_workbook_auto_from_rs(cursor)
            .map_err(|e| DocProcError::ParseError(format!("Failed to parse Excel: {}", e)))?;

        let sheet_names: Vec<String> = workbook.sheet_names().to_vec();
        let sheet_count = sheet_names.len();

        let mut all_text = String::new();
        let mut blocks = Vec::new();
        let mut tables_extracted = 0;

        // Process each sheet
        for sheet_name in &sheet_names {
            if let Ok(range) = workbook.worksheet_range(sheet_name) {
                let mut sheet_text = format!("## Sheet: {}\n\n", sheet_name);
                let mut rows_text = Vec::new();

                // Build header row
                let mut header_row: Option<Vec<String>> = None;

                for (row_idx, row) in range.rows().enumerate() {
                    let cells: Vec<String> = row
                        .iter()
                        .map(|cell| {
                            match cell {
                                calamine::Data::Empty => String::new(),
                                calamine::Data::String(s) => s.clone(),
                                calamine::Data::Float(f) => {
                                    if f.fract() == 0.0 {
                                        format!("{}", *f as i64)
                                    } else {
                                        format!("{:.4}", f)
                                    }
                                }
                                calamine::Data::Int(i) => format!("{}", i),
                                calamine::Data::Bool(b) => format!("{}", b),
                                calamine::Data::DateTime(dt) => format!("{}", dt),
                                calamine::Data::DateTimeIso(s) => s.clone(),
                                calamine::Data::DurationIso(s) => s.clone(),
                                calamine::Data::Error(e) => format!("#ERR:{:?}", e),
                            }
                        })
                        .collect();

                    // Skip completely empty rows
                    if cells.iter().all(|c| c.is_empty()) {
                        continue;
                    }

                    // First non-empty row is header
                    if header_row.is_none() {
                        header_row = Some(cells.clone());
                    }

                    // Format as markdown table row
                    let row_text = format!("| {} |", cells.join(" | "));
                    rows_text.push(row_text);

                    // Add separator after header
                    if rows_text.len() == 1 {
                        let separator: Vec<&str> = (0..cells.len()).map(|_| "---").collect();
                        rows_text.push(format!("| {} |", separator.join(" | ")));
                    }

                    // Create block for each row
                    blocks.push(ContentBlock {
                        block_type: BlockType::Row,
                        content: cells.join("\t"),
                        page: None,
                        sheet: Some(sheet_name.clone()),
                        metadata: serde_json::json!({
                            "row_index": row_idx,
                            "cell_count": cells.len()
                        }),
                    });
                }

                if !rows_text.is_empty() {
                    sheet_text.push_str(&rows_text.join("\n"));
                    tables_extracted += 1;
                }

                // Add sheet block
                blocks.push(ContentBlock {
                    block_type: BlockType::Table,
                    content: sheet_text.clone(),
                    page: None,
                    sheet: Some(sheet_name.clone()),
                    metadata: serde_json::json!({
                        "row_count": range.height(),
                        "column_count": range.width()
                    }),
                });

                if !all_text.is_empty() {
                    all_text.push_str("\n\n---\n\n");
                }
                all_text.push_str(&sheet_text);
            } else {
                warnings.push(format!("Failed to read sheet: {}", sheet_name));
            }
        }

        let word_count = all_text.split_whitespace().count();

        Ok(ExtractionResult {
            content: all_text.clone(),
            metadata: DocumentMetadata {
                filename: filename.map(String::from),
                file_type: "excel".to_string(),
                page_count: None,
                sheet_count: Some(sheet_count),
                char_count: all_text.len(),
                word_count,
                title: None,
                author: None,
            },
            blocks,
            stats: ProcessingStats {
                processing_time_ms: start.elapsed().as_secs_f64() * 1000.0,
                tables_extracted,
                images_found: 0,
                warnings,
            },
        })
    }
}
