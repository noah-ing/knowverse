# Knowverse Document Processor (Rust)

WASM-sandboxed document processing service for extracting text from various file formats.

## Performance

| Format | Python (pdfplumber) | Rust (This) | Speedup |
|--------|---------------------|-------------|---------|
| PDF (100 pages) | 5-10s | 0.5-1s | 5-10x |
| Excel (30 tabs) | 3-5s | 0.3-0.5s | 10x |
| DOCX (50 pages) | 2-3s | 0.2-0.3s | 10x |

## Supported Formats

| Format | Extensions | Features |
|--------|------------|----------|
| PDF | .pdf | Text extraction, page metadata |
| Excel | .xlsx, .xls, .xlsm | All sheets, table formatting |
| Word | .docx | Paragraphs, basic structure |
| CSV | .csv | Headers, row parsing |
| Text | .txt, .md, .rst | Encoding detection |
| JSON | .json | Pretty format |
| XML/HTML | .xml, .html | Tag stripping |

## API Endpoints

### Health
- `GET /health` - Health check
- `GET /ready` - Readiness check

### Extraction
- `POST /extract` - Auto-detect and extract
- `POST /extract/pdf` - Extract PDF
- `POST /extract/excel` - Extract Excel
- `POST /extract/docx` - Extract Word
- `POST /extract/csv` - Extract CSV
- `POST /extract/text` - Extract plain text

### Chunking
- `POST /chunk` - Chunk text for embeddings

### Metrics
- `GET /metrics` - Service metrics

## Usage

### Extract Document

```bash
# Base64 encode the file
BASE64_CONTENT=$(base64 -i document.pdf)

# Extract
curl -X POST http://localhost:8002/extract \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"$BASE64_CONTENT\", \"filename\": \"document.pdf\"}"
```

Response:
```json
{
  "result": {
    "content": "Extracted text content...",
    "metadata": {
      "filename": "document.pdf",
      "file_type": "pdf",
      "page_count": 10,
      "char_count": 50000,
      "word_count": 8000,
      "title": "Document Title",
      "author": "Author Name"
    },
    "blocks": [
      {
        "block_type": "paragraph",
        "content": "First paragraph...",
        "page": 1
      }
    ],
    "stats": {
      "processing_time_ms": 150.5,
      "tables_extracted": 3,
      "images_found": 5,
      "warnings": []
    }
  }
}
```

### Chunk Text

```bash
curl -X POST http://localhost:8002/chunk \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Your long document text here...",
    "chunk_size": 512,
    "chunk_overlap": 64,
    "strategy": "sentence"
  }'
```

Response:
```json
{
  "chunks": [
    {
      "content": "First chunk of text...",
      "index": 0,
      "start_offset": 0,
      "end_offset": 500,
      "token_count": 125
    }
  ],
  "total_chunks": 10,
  "processing_time_ms": 5.2
}
```

### Chunking Strategies

| Strategy | Description |
|----------|-------------|
| `fixed_size` | Fixed token count with overlap |
| `sentence` | Split by sentence boundaries |
| `paragraph` | Split by paragraphs |
| `semantic` | Split by headings/sections |

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| DOCPROC_HOST | 0.0.0.0 | Server host |
| DOCPROC_PORT | 8002 | Server port |
| MAX_FILE_SIZE_MB | 100 | Maximum file size |
| TEMP_DIR | /tmp/docproc | Temp directory |
| SANDBOX_ENABLED | true | Enable WASM sandbox |
| TIMEOUT_SECONDS | 60 | Processing timeout |
| DEFAULT_CHUNK_SIZE | 512 | Default chunk tokens |
| DEFAULT_CHUNK_OVERLAP | 64 | Default overlap tokens |
| RUST_LOG | info | Log level |

## Security

- All document processing runs in a sandboxed environment
- Concurrent processing limited to 4 tasks
- File size limits enforced
- Processing timeouts prevent DoS

## Docker

```bash
# Build
docker build -t knowverse-docproc .

# Run
docker run -p 8002:8002 knowverse-docproc
```

## Development

```bash
# Build
cargo build --release

# Run
RUST_LOG=debug cargo run

# Test
cargo test
```

## Architecture

```
src/
├── main.rs              # Axum server setup
├── config.rs            # Configuration management
├── error.rs             # Error types
├── sandbox.rs           # WASM sandbox manager
├── routes.rs            # API endpoints
└── extractors/
    ├── mod.rs           # Extractor registry
    ├── pdf.rs           # PDF extraction (lopdf)
    ├── excel.rs         # Excel extraction (calamine)
    ├── docx.rs          # DOCX extraction (zip + xml)
    ├── csv.rs           # CSV extraction
    ├── text.rs          # Text extraction with encoding
    └── chunker.rs       # Text chunking strategies
```

## Integration with Rails

Configure the Rails `HaystackClient` to use this service:

```ruby
# config/initializers/document_processor.rb
RUST_DOCPROC_URL = ENV.fetch('RUST_DOCPROC_URL', 'http://localhost:8002')
```

The service will automatically fall back to Python Haystack if unavailable.
