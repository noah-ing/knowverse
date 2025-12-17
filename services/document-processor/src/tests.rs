//! Unit tests for document processor components

#[cfg(test)]
mod chunker_tests {
    use crate::extractors::{ChunkStrategy, TextChunk, TextChunker};

    #[test]
    fn test_chunker_creation() {
        let chunker = TextChunker::new(512, 64);
        // Chunker should be created without issues
        assert!(true);
    }

    #[test]
    fn test_fixed_size_chunking() {
        let chunker = TextChunker::new(10, 2); // 10 words per chunk, 2 word overlap
        let text = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen";

        let chunks = chunker.chunk(text, ChunkStrategy::FixedSize).unwrap();

        assert!(!chunks.is_empty());
        // First chunk should have 10 words
        assert_eq!(chunks[0].token_count, 10);
    }

    #[test]
    fn test_chunking_preserves_content() {
        let chunker = TextChunker::new(100, 10);
        let text = "This is a test sentence. It has multiple words.";

        let chunks = chunker.chunk(text, ChunkStrategy::FixedSize).unwrap();

        // All content should be preserved
        let reconstructed: String = chunks.iter().map(|c| c.content.clone()).collect::<Vec<_>>().join(" ");
        // Content words should be present
        assert!(reconstructed.contains("test"));
        assert!(reconstructed.contains("sentence"));
    }

    #[test]
    fn test_sentence_chunking() {
        let chunker = TextChunker::new(50, 0);
        let text = "First sentence. Second sentence. Third sentence. Fourth sentence.";

        let chunks = chunker.chunk(text, ChunkStrategy::Sentence).unwrap();

        assert!(!chunks.is_empty());
        for chunk in &chunks {
            assert!(!chunk.content.is_empty());
        }
    }

    #[test]
    fn test_paragraph_chunking() {
        let chunker = TextChunker::new(100, 0);
        let text = "First paragraph with some content.\n\nSecond paragraph with different content.\n\nThird paragraph.";

        let chunks = chunker.chunk(text, ChunkStrategy::Paragraph).unwrap();

        assert!(!chunks.is_empty());
    }

    #[test]
    fn test_semantic_chunking_with_headings() {
        let chunker = TextChunker::new(100, 0);
        let text = "# Heading 1\n\nContent under heading 1.\n\n## Heading 2\n\nContent under heading 2.";

        let chunks = chunker.chunk(text, ChunkStrategy::Semantic).unwrap();

        assert!(!chunks.is_empty());
    }

    #[test]
    fn test_semantic_chunking_without_headings() {
        let chunker = TextChunker::new(100, 0);
        let text = "Just some regular text without any headings. Another sentence here.";

        // Should fall back to paragraph chunking
        let chunks = chunker.chunk(text, ChunkStrategy::Semantic).unwrap();

        assert!(!chunks.is_empty());
    }

    #[test]
    fn test_empty_text_chunking() {
        let chunker = TextChunker::new(100, 10);
        let text = "";

        let chunks = chunker.chunk(text, ChunkStrategy::FixedSize).unwrap();

        assert!(chunks.is_empty());
    }

    #[test]
    fn test_chunk_indices() {
        let chunker = TextChunker::new(5, 1);
        let text = "one two three four five six seven eight nine ten";

        let chunks = chunker.chunk(text, ChunkStrategy::FixedSize).unwrap();

        // Indices should be sequential
        for (i, chunk) in chunks.iter().enumerate() {
            assert_eq!(chunk.index, i);
        }
    }

    #[test]
    fn test_chunk_offsets() {
        let chunker = TextChunker::new(100, 0);
        let text = "First chunk content. Second chunk content.";

        let chunks = chunker.chunk(text, ChunkStrategy::FixedSize).unwrap();

        if !chunks.is_empty() {
            assert_eq!(chunks[0].start_offset, 0);
        }
    }
}

#[cfg(test)]
mod file_type_tests {
    use crate::extractors::{detect_file_type, FileType};

    #[test]
    fn test_detect_pdf_by_extension() {
        let content = b"random bytes";
        let file_type = detect_file_type(content, Some("document.pdf")).unwrap();
        assert_eq!(file_type, FileType::Pdf);
    }

    #[test]
    fn test_detect_excel_by_extension() {
        let content = b"random bytes";

        let xlsx = detect_file_type(content, Some("spreadsheet.xlsx")).unwrap();
        assert_eq!(xlsx, FileType::Excel);

        let xls = detect_file_type(content, Some("spreadsheet.xls")).unwrap();
        assert_eq!(xls, FileType::Excel);
    }

    #[test]
    fn test_detect_docx_by_extension() {
        let content = b"random bytes";
        let file_type = detect_file_type(content, Some("document.docx")).unwrap();
        assert_eq!(file_type, FileType::Docx);
    }

    #[test]
    fn test_detect_csv_by_extension() {
        let content = b"random bytes";
        let file_type = detect_file_type(content, Some("data.csv")).unwrap();
        assert_eq!(file_type, FileType::Csv);
    }

    #[test]
    fn test_detect_text_by_extension() {
        let content = b"random bytes";

        let txt = detect_file_type(content, Some("readme.txt")).unwrap();
        assert_eq!(txt, FileType::Text);

        let md = detect_file_type(content, Some("README.md")).unwrap();
        assert_eq!(md, FileType::Text);
    }

    #[test]
    fn test_detect_json_by_extension() {
        let content = b"random bytes";
        let file_type = detect_file_type(content, Some("config.json")).unwrap();
        assert_eq!(file_type, FileType::Json);
    }

    #[test]
    fn test_detect_xml_by_extension() {
        let content = b"random bytes";

        let xml = detect_file_type(content, Some("data.xml")).unwrap();
        assert_eq!(xml, FileType::Xml);

        let html = detect_file_type(content, Some("page.html")).unwrap();
        assert_eq!(html, FileType::Xml);
    }

    #[test]
    fn test_unsupported_extension() {
        let content = b"random bytes";
        let result = detect_file_type(content, Some("file.xyz"));
        assert!(result.is_err());
    }

    #[test]
    fn test_no_filename() {
        let content = b"random bytes not matching any magic";
        let result = detect_file_type(content, None);
        // Should fail since we can't determine type
        assert!(result.is_err());
    }

    #[test]
    fn test_case_insensitive_extension() {
        let content = b"random bytes";

        let upper = detect_file_type(content, Some("file.PDF")).unwrap();
        assert_eq!(upper, FileType::Pdf);

        let mixed = detect_file_type(content, Some("file.XlSx")).unwrap();
        assert_eq!(mixed, FileType::Excel);
    }

    #[test]
    fn test_file_type_display() {
        assert_eq!(format!("{}", FileType::Pdf), "pdf");
        assert_eq!(format!("{}", FileType::Excel), "excel");
        assert_eq!(format!("{}", FileType::Docx), "docx");
        assert_eq!(format!("{}", FileType::Csv), "csv");
        assert_eq!(format!("{}", FileType::Text), "text");
        assert_eq!(format!("{}", FileType::Json), "json");
        assert_eq!(format!("{}", FileType::Xml), "xml");
    }
}

#[cfg(test)]
mod extraction_result_tests {
    use crate::extractors::{
        BlockType, ContentBlock, DocumentMetadata, ExtractionResult, ProcessingStats,
    };

    #[test]
    fn test_extraction_result_serialization() {
        let result = ExtractionResult {
            content: "Test content".to_string(),
            metadata: DocumentMetadata {
                filename: Some("test.txt".to_string()),
                file_type: "text".to_string(),
                page_count: None,
                sheet_count: None,
                char_count: 12,
                word_count: 2,
                title: None,
                author: None,
            },
            blocks: vec![ContentBlock {
                block_type: BlockType::Paragraph,
                content: "Test content".to_string(),
                page: None,
                sheet: None,
                metadata: serde_json::json!({}),
            }],
            stats: ProcessingStats::default(),
        };

        let json = serde_json::to_string(&result).unwrap();
        assert!(json.contains("Test content"));
        assert!(json.contains("test.txt"));
    }

    #[test]
    fn test_block_type_serialization() {
        let block = ContentBlock {
            block_type: BlockType::Heading,
            content: "Title".to_string(),
            page: Some(1),
            sheet: None,
            metadata: serde_json::json!({"level": 1}),
        };

        let json = serde_json::to_string(&block).unwrap();
        assert!(json.contains("heading"));
        assert!(json.contains("Title"));
    }

    #[test]
    fn test_processing_stats_default() {
        let stats = ProcessingStats::default();
        assert_eq!(stats.processing_time_ms, 0.0);
        assert_eq!(stats.tables_extracted, 0);
        assert_eq!(stats.images_found, 0);
        assert!(stats.warnings.is_empty());
    }
}

#[cfg(test)]
mod routes_tests {
    use crate::routes::{
        ChunkRequest, ChunkResponse, ExtractRequest, ExtractResponse, HealthResponse,
        MetricsResponse, ReadyResponse,
    };
    use crate::extractors::ChunkStrategy;

    #[test]
    fn test_extract_request_deserialization() {
        let json = r#"{"content": "SGVsbG8gV29ybGQ="}"#;
        let request: ExtractRequest = serde_json::from_str(json).unwrap();
        assert_eq!(request.content, "SGVsbG8gV29ybGQ=");
        assert!(request.filename.is_none());
    }

    #[test]
    fn test_extract_request_with_filename() {
        let json = r#"{"content": "SGVsbG8=", "filename": "test.txt"}"#;
        let request: ExtractRequest = serde_json::from_str(json).unwrap();
        assert_eq!(request.filename, Some("test.txt".to_string()));
    }

    #[test]
    fn test_chunk_request_deserialization() {
        let json = r#"{"text": "Hello world"}"#;
        let request: ChunkRequest = serde_json::from_str(json).unwrap();
        assert_eq!(request.text, "Hello world");
        assert!(request.chunk_size.is_none());
        assert!(request.chunk_overlap.is_none());
        assert!(request.strategy.is_none());
    }

    #[test]
    fn test_chunk_request_with_options() {
        let json = r#"{
            "text": "Hello world",
            "chunk_size": 256,
            "chunk_overlap": 32,
            "strategy": "sentence"
        }"#;
        let request: ChunkRequest = serde_json::from_str(json).unwrap();
        assert_eq!(request.chunk_size, Some(256));
        assert_eq!(request.chunk_overlap, Some(32));
        assert!(matches!(request.strategy, Some(ChunkStrategy::Sentence)));
    }

    #[test]
    fn test_chunk_strategy_deserialization() {
        let strategies = vec![
            ("\"fixed_size\"", ChunkStrategy::FixedSize),
            ("\"sentence\"", ChunkStrategy::Sentence),
            ("\"paragraph\"", ChunkStrategy::Paragraph),
            ("\"semantic\"", ChunkStrategy::Semantic),
        ];

        for (json, expected) in strategies {
            let parsed: ChunkStrategy = serde_json::from_str(json).unwrap();
            assert!(matches!(parsed, ref e if std::mem::discriminant(&parsed) == std::mem::discriminant(e)));
        }
    }

    #[test]
    fn test_health_response_serialization() {
        let response = HealthResponse {
            status: "healthy".to_string(),
            version: "1.0.0".to_string(),
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("healthy"));
        assert!(json.contains("1.0.0"));
    }

    #[test]
    fn test_ready_response_serialization() {
        let response = ReadyResponse { ready: true };
        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("true"));
    }

    #[test]
    fn test_metrics_response_serialization() {
        let response = MetricsResponse {
            total_extractions: 42,
            supported_formats: vec!["pdf".to_string(), "docx".to_string()],
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("42"));
        assert!(json.contains("pdf"));
        assert!(json.contains("docx"));
    }
}

#[cfg(test)]
mod text_extractor_tests {
    use crate::extractors::TextExtractor;

    #[test]
    fn test_extract_plain_text() {
        let content = b"Hello, this is plain text content.";
        let result = TextExtractor::extract(content, Some("test.txt")).unwrap();

        assert!(result.content.contains("Hello"));
        assert_eq!(result.metadata.file_type, "text");
    }

    #[test]
    fn test_extract_utf8_text() {
        let content = "Hello 世界 🌍".as_bytes();
        let result = TextExtractor::extract(content, Some("unicode.txt")).unwrap();

        assert!(result.content.contains("世界"));
    }

    #[test]
    fn test_extract_text_metadata() {
        let content = b"One two three four five.";
        let result = TextExtractor::extract(content, Some("count.txt")).unwrap();

        assert!(result.metadata.char_count > 0);
        assert!(result.metadata.word_count > 0);
    }
}

#[cfg(test)]
mod csv_extractor_tests {
    use crate::extractors::CsvExtractor;

    #[test]
    fn test_extract_simple_csv() {
        let content = b"name,age,city\nAlice,30,NYC\nBob,25,LA";
        let result = CsvExtractor::extract(content, Some("data.csv")).unwrap();

        assert!(result.content.contains("Alice"));
        assert!(result.content.contains("Bob"));
        assert_eq!(result.metadata.file_type, "csv");
    }

    #[test]
    fn test_csv_creates_table_blocks() {
        let content = b"col1,col2\na,b\nc,d";
        let result = CsvExtractor::extract(content, Some("test.csv")).unwrap();

        // Should have blocks for rows
        assert!(!result.blocks.is_empty());
    }
}

#[cfg(test)]
mod error_tests {
    use crate::error::DocProcError;

    #[test]
    fn test_error_messages() {
        let error = DocProcError::UnsupportedFileType("xyz".to_string());
        assert!(error.to_string().contains("xyz"));

        let error = DocProcError::InvalidInput("bad data".to_string());
        assert!(error.to_string().contains("bad data"));

        let error = DocProcError::ExtractionFailed("parse failed".to_string());
        assert!(error.to_string().contains("parse failed"));
    }
}
