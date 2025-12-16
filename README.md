# Knowverse

Enterprise AI knowledge management platform with vector search and RAG capabilities.

## Current Architecture

Knowverse uses a polyglot architecture optimized for each task:

- **Rails 8** - API, auth, multi-tenancy, background jobs
- **Qdrant (Rust)** - Vector search with HNSW, built-in Raft consensus
- **Haystack (Python)** - Document extraction and embedding generation
- **PostgreSQL** - Metadata storage, full-text keyword search

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| Rails 8 API | ✅ Working | Multi-tenant, auth, background jobs |
| PostgreSQL | ✅ Working | Metadata + keyword search |
| Redis caching | ✅ Working | Two-tier cache (memory + Redis) |
| Sidekiq/SolidQueue | ✅ Working | Background job processing |
| Text file processing | ✅ Working | TXT, MD, RTF |
| PDF Extraction | ✅ Working | Via Haystack service (pdfplumber) |
| DOCX Extraction | ✅ Working | Via Haystack service (python-docx) |
| Excel Extraction | ✅ Working | Via Haystack service (fastexcel) |
| Qdrant Integration | ⚠️ Requires Setup | External Qdrant cluster needed |
| Embedding Generation | ⚠️ Requires Setup | Haystack service must be running |

## Search Modes

```ruby
# Semantic search (Qdrant - fastest)
SearchRouter.route_query("your query", organization_id, mode: :semantic)

# Keyword search (PostgreSQL full-text)
SearchRouter.route_query("your query", organization_id, mode: :keyword)

# Hybrid search (semantic + keyword fusion)
SearchRouter.route_query("your query", organization_id, mode: :hybrid)
```

## Document Processing

```ruby
# Requires Haystack Python service running on port 8000
client = HaystackClient.new

# PDF extraction
result = client.extract_pdf(file_content, filename: "doc.pdf")

# Excel extraction (handles 30+ tabs)
result = client.extract_excel(file_content, filename: "budget.xlsx")

# DOCX extraction with structure preservation
result = client.extract_docx(file_content, filename: "report.docx")
```

## Embeddings

```ruby
# CRITICAL: Requires Haystack service
# If unavailable, embedding generation will FAIL (no mock fallback)
client = HaystackClient.new
result = client.generate_embeddings("your text", model: "all-mpnet-base-v2")
```

## Required Services

| Feature | Required Service | Port |
|---------|------------------|------|
| Document extraction | Haystack (Python) | 8000 |
| Embedding generation | Haystack (Python) | 8000 |
| Vector search | Qdrant cluster | 6333 |
| API | Rails | 3000 |

## Quick Start

### Prerequisites
- Ruby 3.4+
- Python 3.13+
- PostgreSQL 15+
- Redis 7+
- Docker (for Qdrant)

### Setup

```bash
# Clone
git clone https://github.com/your-org/knowverse.git
cd knowverse

# Install Ruby dependencies
bundle install

# Install Python dependencies
cd services/haystack && pip install -r requirements.txt && cd ../..

# Setup database
./bin/setup
rails db:create db:migrate

# Configure environment
cp .env.example .env
# Edit .env with your settings
```

### Start Production Stack

```bash
# Full stack with Qdrant cluster
docker-compose -f docker-compose.production.yml up -d

# Check Qdrant health
curl http://localhost:6333/readiness

# Check Haystack health
curl http://localhost:8000/health
```

### Migrate Existing Data to Qdrant

```bash
# Check Qdrant status
bundle exec rake qdrant:status

# Migrate all documents
bundle exec rake qdrant:migrate

# Verify migration for an organization
bundle exec rake qdrant:verify[org_id]

# Run performance benchmark
bundle exec rake qdrant:benchmark[org_id]
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Client Layer                         │
│  Web App │ Admin Dashboard │ API Clients                │
└─────────────────────┬───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│                  Rails 8 Application                     │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐   │
│  │UnifiedSearch│ │ Documents   │ │ Organizations   │   │
│  │  Service    │ │ Controller  │ │ (Multi-tenant)  │   │
│  └──────┬──────┘ └──────┬──────┘ └─────────────────┘   │
└─────────┼───────────────┼───────────────────────────────┘
          │               │
    ┌─────┴─────┐   ┌─────┴─────┐
    │           │   │           │
    ▼           ▼   ▼           │
┌───────────┐ ┌───────────┐ ┌───────────────────────────┐
│  QDRANT   │ │PostgreSQL │ │  Haystack Python Service  │
│  CLUSTER  │ │           │ ├───────────────────────────┤
│  (Rust)   │ │ Metadata  │ │ • PDF/DOCX/Excel extract │
├───────────┤ │ + Keyword │ │ • Embedding generation    │
│ • HNSW    │ │ search    │ │ • sentence-transformers   │
│ • <10ms   │ │           │ └───────────────────────────┘
│ • Raft    │ └───────────┘
│ • 3-way   │
│   repl.   │
└───────────┘
```

## Key Files

| File | Purpose |
|------|---------|
| `app/services/search/unified_search_service.rb` | Search orchestration |
| `app/services/vector_store/qdrant_cluster_adapter.rb` | Qdrant HTTP client |
| `app/services/search_router.rb` | Backwards-compatible search API |
| `app/services/haystack_client.rb` | Python service communication |
| `services/haystack/app/extractors/*.py` | PDF/DOCX/Excel extraction |
| `docker-compose.production.yml` | Full production stack |
| `lib/tasks/qdrant_migration.rake` | Migration utilities |

## Performance

| Metric | Value |
|--------|-------|
| Semantic search latency | < 10ms (Qdrant HNSW) |
| Keyword search latency | ~20-50ms (PostgreSQL) |
| Hybrid search latency | ~30-60ms (parallel) |
| Scale tested | 100K vectors (production TBD) |

## Testing

```bash
# Run tests
bundle exec rspec

# Integration tests (requires Haystack + Qdrant)
bundle exec rspec spec/integration/
```

## License

See LICENSE.md

---

*Architecture: Qdrant-Centric v3.0*
*Last updated: December 2025*
