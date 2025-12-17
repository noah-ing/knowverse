# Knowverse

Enterprise AI knowledge management platform with vector search and RAG capabilities.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Rails 8 (Web UI, Auth, Admin, API)             │
│                        Port 3000                            │
└─────────────────────────┬───────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│   PostgreSQL  │ │    Qdrant     │ │   Haystack    │
│   (Metadata)  │ │ (Vector Search│ │   (Python)    │
│   Port 5432   │ │  Port 6333    │ │   Port 8000   │
└───────────────┘ └───────────────┘ └───────────────┘
```

**Tech Stack:**
- **Rails 8** - API, auth, multi-tenancy, background jobs (SolidQueue)
- **Qdrant** - Vector search with HNSW indexes, native Raft consensus
- **Haystack (Python/FastAPI)** - Document extraction, embeddings, RAG
- **PostgreSQL 14+** - Metadata storage, pgvector, full-text search
- **Redis 7+** - Caching, session storage

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| Rails 8 API | Working | Multi-tenant, Devise auth, SolidQueue |
| PostgreSQL | Working | pgvector enabled, full-text search |
| Redis | Working | Two-tier cache (memory + Redis) |
| Qdrant | Working | Docker container, HNSW indexes |
| PDF Extraction | Working | pdfplumber with table extraction |
| DOCX Extraction | Working | python-docx with structure |
| Excel Extraction | Working | fastexcel (Rust/calamine) |
| Embedding Generation | Working | sentence-transformers |
| Semantic Search | Working | Qdrant vector search |
| Hybrid Search | Working | RRF fusion (vector + keyword) |
| RAG Endpoints | Working | OpenAI integration, SSE streaming |
| Domain Detection | Working | Query domain classification |

## Quick Start

### Docker (Recommended)

```bash
# Start all services
docker compose up -d

# Check health
curl http://localhost:3000/health  # Rails
curl http://localhost:8000/health  # Haystack
curl http://localhost:6333/health  # Qdrant
```

### Manual Setup

```bash
# Prerequisites: Ruby 3.4+, Python 3.11+, PostgreSQL 14+, Redis 7+

# Ruby dependencies
bundle install

# Python dependencies
cd services/haystack && pip install -r requirements.txt && cd ../..

# Database setup
rails db:create db:migrate

# Start Qdrant
docker run -p 6333:6333 -p 6334:6334 qdrant/qdrant:v1.12.4

# Start Haystack
cd services/haystack && uvicorn app.main:app --host 0.0.0.0 --port 8000

# Start Rails
rails server
```

## API Endpoints

### Rails API (Port 3000)
- `POST /api/v1/documents` - Upload document
- `POST /api/v1/search` - Search documents
- `GET /api/v1/organizations/:id/documents` - List documents

### Haystack API (Port 8000)
- `POST /search` - Semantic search
- `POST /hybrid-search` - Hybrid vector + keyword search
- `POST /embeddings/generate` - Generate embeddings
- `POST /rag/answer` - RAG response
- `POST /rag/stream` - Streaming RAG (SSE)
- `GET /rag/providers` - List LLM providers
- `POST /extract/pdf` - Extract text from PDF
- `POST /extract/docx` - Extract text from Word
- `POST /extract/excel` - Extract text from Excel
- `POST /chunk` - Chunk text for embeddings
- `POST /parse-query` - Analyze query
- `POST /domains/detect` - Detect query domain

## Usage Examples

### Search

```ruby
# Semantic search
SearchRouter.route_query("machine learning optimization", org_id, mode: :semantic)

# Hybrid search (recommended)
SearchRouter.route_query("quarterly revenue report", org_id, mode: :hybrid)

# Keyword search
SearchRouter.route_query("contract #12345", org_id, mode: :keyword)
```

### Document Processing

```ruby
client = HaystackClient.new

# PDF with table extraction
result = client.extract_pdf(file_content, filename: "report.pdf")

# Excel (handles large workbooks with 30+ tabs)
result = client.extract_excel(file_content, filename: "data.xlsx")

# DOCX with structure preservation
result = client.extract_docx(file_content, filename: "document.docx")
```

### Embeddings

```ruby
client = HaystackClient.new
result = client.generate_embeddings("your text content")
# => { embedding: [...], dimension: 768, processing_time: 0.05 }
```

## Environment Variables

```bash
# Required
DATABASE_URL=postgresql://postgres:password@localhost:5432/knowverse_development
REDIS_URL=redis://localhost:6379/0
QDRANT_URL=http://localhost:6333
HAYSTACK_SERVICE_URL=http://localhost:8000

# Optional (for RAG)
OPENAI_API_KEY=sk-...

# Optional (for email)
RESEND_API_KEY=re_...
```

## Development

### Running Tests

```bash
# Rails tests
bundle exec rspec

# Python tests
cd services/haystack && pytest
```

### Database Tables

Key tables for the AI/search functionality:
- `documents` - Document metadata and content
- `vector_embeddings` - Stored embeddings with model info
- `conversation_sessions` - RAG conversation tracking
- `conversation_messages` - Message history
- `domain_embedding_models` - Domain-specific models
- `domain_confidence_scores` - Query domain analytics

## Roadmap

- Comprehensive test suite (RSpec + pytest)
- Rust embedding service (ONNX Runtime, 10-50x faster)
- Rust WASM document processor (sandboxed parsing)
- Production hardening and load testing

## License

Proprietary - All rights reserved.
