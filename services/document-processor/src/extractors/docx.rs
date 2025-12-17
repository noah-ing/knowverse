//! DOCX extraction using docx-rs

use crate::error::{DocProcError, Result};
use super::{BlockType, ContentBlock, DocumentMetadata, ExtractionResult, ProcessingStats};
use docx_rs::*;
use std::io::Cursor;
use std::time::Instant;

/// DOCX document extractor
pub struct DocxExtractor;

impl DocxExtractor {
    /// Extract text from DOCX content
    pub fn extract(content: &[u8], filename: Option<&str>) -> Result<ExtractionResult> {
        let start = Instant::now();
        let warnings = Vec::new();

        // Parse DOCX - docx-rs is primarily for writing, so we'll use a simpler approach
        // via the zip and xml libraries for reading
        let cursor = Cursor::new(content);
        let mut archive = zip::ZipArchive::new(cursor)
            .map_err(|e| DocProcError::ParseError(format!("Failed to open DOCX archive: {}", e)))?;

        let mut all_text = String::new();
        let mut blocks = Vec::new();

        // Read document.xml
        let doc_xml = archive
            .by_name("word/document.xml")
            .map_err(|e| DocProcError::ParseError(format!("Failed to find document.xml: {}", e)))?;

        let doc_content = std::io::read_to_string(doc_xml)
            .map_err(|e| DocProcError::ParseError(format!("Failed to read document.xml: {}", e)))?;

        // Simple XML text extraction - extract text between <w:t> tags
        let mut in_text = false;
        let mut current_paragraph = String::new();
        let mut paragraph_count = 0;

        let parser = xml::reader::EventReader::from_str(&doc_content);

        for event in parser {
            match event {
                Ok(xml::reader::XmlEvent::StartElement { name, .. }) => {
                    if name.local_name == "t" {
                        in_text = true;
                    } else if name.local_name == "p" && !current_paragraph.is_empty() {
                        // End of paragraph
                        let trimmed = current_paragraph.trim();
                        if !trimmed.is_empty() {
                            blocks.push(ContentBlock {
                                block_type: BlockType::Paragraph,
                                content: trimmed.to_string(),
                                page: None,
                                sheet: None,
                                metadata: serde_json::json!({
                                    "paragraph_index": paragraph_count
                                }),
                            });

                            if !all_text.is_empty() {
                                all_text.push_str("\n\n");
                            }
                            all_text.push_str(trimmed);
                            paragraph_count += 1;
                        }
                        current_paragraph.clear();
                    }
                }
                Ok(xml::reader::XmlEvent::EndElement { name }) => {
                    if name.local_name == "t" {
                        in_text = false;
                    }
                }
                Ok(xml::reader::XmlEvent::Characters(text)) => {
                    if in_text {
                        current_paragraph.push_str(&text);
                    }
                }
                Err(e) => {
                    tracing::warn!("XML parsing error: {}", e);
                }
                _ => {}
            }
        }

        // Don't forget the last paragraph
        let trimmed = current_paragraph.trim();
        if !trimmed.is_empty() {
            blocks.push(ContentBlock {
                block_type: BlockType::Paragraph,
                content: trimmed.to_string(),
                page: None,
                sheet: None,
                metadata: serde_json::json!({
                    "paragraph_index": paragraph_count
                }),
            });
            if !all_text.is_empty() {
                all_text.push_str("\n\n");
            }
            all_text.push_str(trimmed);
        }

        let word_count = all_text.split_whitespace().count();

        // Try to extract core properties
        let (title, author) = extract_core_properties(&mut archive);

        Ok(ExtractionResult {
            content: all_text.clone(),
            metadata: DocumentMetadata {
                filename: filename.map(String::from),
                file_type: "docx".to_string(),
                page_count: None, // Would need complex layout calculation
                sheet_count: None,
                char_count: all_text.len(),
                word_count,
                title,
                author,
            },
            blocks,
            stats: ProcessingStats {
                processing_time_ms: start.elapsed().as_secs_f64() * 1000.0,
                tables_extracted: 0,
                images_found: 0,
                warnings,
            },
        })
    }
}

/// Extract title and author from core.xml
fn extract_core_properties(archive: &mut zip::ZipArchive<Cursor<&[u8]>>) -> (Option<String>, Option<String>) {
    let mut title = None;
    let mut author = None;

    if let Ok(core_xml) = archive.by_name("docProps/core.xml") {
        if let Ok(content) = std::io::read_to_string(core_xml) {
            let parser = xml::reader::EventReader::from_str(&content);
            let mut current_element = String::new();

            for event in parser {
                match event {
                    Ok(xml::reader::XmlEvent::StartElement { name, .. }) => {
                        current_element = name.local_name.to_string();
                    }
                    Ok(xml::reader::XmlEvent::Characters(text)) => {
                        match current_element.as_str() {
                            "title" => title = Some(text),
                            "creator" => author = Some(text),
                            _ => {}
                        }
                    }
                    _ => {}
                }
            }
        }
    }

    (title, author)
}
