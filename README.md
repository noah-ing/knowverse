# Knowverse

Enterprise AI knowledge management platform with vector search and RAG capabilities.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                Rails 8 (Web UI, Auth, Admin, API)               │
│                          Port 3000                              │
└──────────────────────────────┬──────────────────────────────────┘
                               │
       ┌───────────────────────┼───────────────────────┐
       │                       │                       │
       ▼                       ▼                       ▼
┌─────────────┐  ┌───────────────────────┐  ┌─────────────────┐
│ PostgreSQL  │  │        Qdrant         │  │    Haystack     │
│ (Metadata)  │  │   (Vector Search)     │  │    (Python)     │
│ Port 5432   │  │     Port 6333         │  │   Port 8000     │
└─────────────┘  └───────────────────────┘  └─────────────────┘
                                                     │
                          ┌──────────────────────────┤
                          │                          │
                          ▼                          ▼
               ┌─────────────────────┐   ┌─────────────────────┐
               │   Rust Embedding    │   │   Rust DocProc      │
               │   (ONNX Runtime)    │   │   (WASM Sandbox)    │
               │   Port 8001         │   │   Port 8002         │
               │   10-50x faster     │   │   5-10x faster      │
               └─────────────────────┘   └─────────────────────┘
```

**Tech Stack:**
- **Rails 8** - API, auth, multi-tenancy, background jobs (SolidQueue)
- **Qdrant** - Vector search with HNSW indexes, native Raft consensus
- **Haystack (Python/FastAPI)** - Document extraction, embeddings, RAG
- **Rust Embedding Service** - ONNX Runtime inference (10-50x faster)
- **Rust Document Processor** - WASM-sandboxed parsing (5-10x faster)
- **PostgreSQL 14+** - Metadata storage, pgvector, full-text search
- **Redis 7+** - Caching, session storage

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| Rails 8 API | Working | Multi-tenant, Devise auth, SolidQueue |
| PostgreSQL | Working | pgvector enabled, full-text search |
| Redis | Working | Two-tier cache (memory + Redis) |
| Qdrant | Working | Docker container, HNSW indexes |
| PDF Extraction | Working | pdfplumber + Rust lopdf |
| DOCX Extraction | Working | python-docx + Rust docx-rs |
| Excel Extraction | Working | fastexcel + Rust calamine |
| Embedding Generation | Working | sentence-transformers + Rust ONNX |
| Semantic Search | Working | Qdrant vector search |
| Hybrid Search | Working | RRF fusion (vector + keyword) |
| RAG Endpoints | Working | OpenAI integration, SSE streaming |
| Domain Detection | Working | Query domain classification |
| Rust Embedding | Ready | ONNX Runtime, LRU cache |
| Rust DocProc | Ready | Sandboxed PDF/Excel/DOCX |
| CI/CD Pipeline | Working | GitHub Actions, multi-language |
| Test Suite | Working | RSpec, pytest, Rust tests |

## Quick Start

### Docker (Recommended)

```bash
# Start core services
docker compose up -d

# Start with Rust high-performance services (optional)
docker compose --profile rust up -d

# Check health
curl http://localhost:3000/health  # Rails
curl http://localhost:8000/health  # Haystack
curl http://localhost:6333/health  # Qdrant
curl http://localhost:8001/health  # Rust Embedding (if enabled)
curl http://localhost:8002/health  # Rust DocProc (if enabled)
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

Tests are designed to run in Docker containers or via CI/CD. The GitHub Actions workflow runs all tests automatically on push.

```bash
# Run all tests via Docker Compose
docker compose run --rm -e RAILS_ENV=test rails bundle exec rspec
docker compose run --rm haystack pytest tests/ -v
docker compose run --rm --build rust-embedding cargo test
docker compose run --rm --build rust-docproc cargo test

# Or trigger CI/CD by pushing to GitHub
git push origin knowverse-integration
```

**Test Coverage:**
- Rails RSpec: Models, services, integration tests
- Python pytest: Haystack endpoints, extraction, search, RAG
- Rust: Unit tests for embedding and document processor services

### ONNX Model Download

Download embedding models for the Rust embedding service:

```bash
# Install dependencies
pip install transformers onnx onnxruntime sentence-transformers optimum

# List available models
python scripts/download_models.py --list

# Download all models (recommended)
python scripts/download_models.py --output-dir ./models

# Download specific models
python scripts/download_models.py --models all-MiniLM-L6-v2,bge-base-en-v1.5
```

**Supported Models:**
- `all-MiniLM-L6-v2` (384d, fast) - General purpose
- `all-mpnet-base-v2` (768d, balanced) - High quality
- `bge-small-en-v1.5` (384d) - Best quality/speed ratio
- `bge-base-en-v1.5` (768d) - Production quality
- `bge-large-en-v1.5` (1024d) - Best quality

### Dataset Ingestion

Ingest high-quality datasets for RAG applications:

```bash
# Install dependencies
pip install datasets sentence-transformers qdrant-client tqdm

# List available datasets
python scripts/ingest_datasets.py --list

# Ingest Wikipedia (first 10,000 docs)
python scripts/ingest_datasets.py --dataset wikipedia --limit 10000 --org-id 1

# Ingest MS MARCO passages
python scripts/ingest_datasets.py --dataset msmarco --org-id 1

# Export to JSONL for later ingestion
python scripts/ingest_datasets.py --dataset squad --export squad.jsonl --limit 5000
```

**Available Datasets:**
| Dataset | Documents | Size | Description |
|---------|-----------|------|-------------|
| wikipedia | 6.4M | ~20GB | English Wikipedia articles |
| wikipedia-simple | 205K | ~200MB | Simple English Wikipedia |
| msmarco | 8.8M | ~3GB | Microsoft MARCO passages |
| natural-questions | 307K | ~42GB | Google's QA dataset |
| squad | 87K | ~35MB | Stanford QA Dataset |
| hotpotqa | 90K | ~600MB | Multi-hop reasoning |
| pubmed | 1K | ~50MB | Biomedical QA |
| eli5 | 272K | ~1.5GB | Explain Like I'm 5 |
| arxiv | 203K | ~5GB | Scientific papers |
| stackexchange | 15M+ | ~8GB | Technical Q&A |

### Database Tables

Key tables for the AI/search functionality:
- `documents` - Document metadata and content
- `vector_embeddings` - Stored embeddings with model info
- `conversation_sessions` - RAG conversation tracking
- `conversation_messages` - Message history
- `domain_embedding_models` - Domain-specific models
- `domain_confidence_scores` - Query domain analytics

## CI/CD

GitHub Actions workflow runs on every push and pull request:

```yaml
# .github/workflows/ci.yml
Jobs:
- Security Scan (Brakeman)
- Ruby Lint (RuboCop)
- Rails Tests (RSpec + PostgreSQL + Redis)
- Python Tests (pytest + Haystack)
- Rust Embedding Tests (cargo test + clippy)
- Rust DocProc Tests (cargo test + clippy)
- Docker Build Verification
```

View workflow runs at: `https://github.com/<owner>/knowverse/actions`

## Roadmap

- [x] Rust embedding service (ONNX Runtime, 10-50x faster)
- [x] Rust WASM document processor (sandboxed parsing)
- [x] Comprehensive test suite (RSpec + pytest + Rust)
- [x] CI/CD pipeline (GitHub Actions)
- [x] ONNX model download script
- [x] High-quality dataset ingestion pipeline
- [x] Production security hardening
- [ ] Kubernetes deployment manifests
- [ ] Multi-node Qdrant cluster configuration
- [ ] Auto-scaling policies

## License

Proprietary - All rights reserved.
