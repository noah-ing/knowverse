# Knowverse

Enterprise AI knowledge management platform with vector search and RAG capabilities.

## Honest Status Assessment

| Component | Status | Notes |
|-----------|--------|-------|
| Rails 8 API | ✅ Working | Multi-tenant, auth, background jobs |
| PostgreSQL + pgvector | ✅ Working | Cosine & L2 similarity search |
| Redis caching | ✅ Working | Two-tier cache (memory + Redis) |
| Sidekiq/SolidQueue | ✅ Working | Background job processing |
| Text file processing | ✅ Working | TXT, MD, RTF |
| 9 Search Providers | ✅ Working | All providers functional after remediation |
| PDF Extraction | ✅ Working | Via Haystack service (pdfplumber) |
| DOCX Extraction | ✅ Working | Via Haystack service (python-docx) |
| Excel Extraction | ✅ Working | Via Haystack service (fastexcel) |
| Raft Consensus | ⚠️ Implemented | Ruby implementation, not battle-tested |
| WASM Components | ⚠️ Simulated | Orchestration ready, needs real WASM compilation |
| Qdrant Integration | ⚠️ Adapter Only | Requires external Qdrant cluster |
| Embedding Generation | ⚠️ Conditional | Requires Haystack service running |
| Scale Testing | ❌ Not Done | 100M+ vectors untested |

## What Actually Works

### Search Providers

```ruby
# All 9 providers are now functional:
SearchRouter.route_query("your query", organization_id: 1)

# Available providers:
# - :pgvector_cosine  - PostgreSQL native (reliable)
# - :pgvector_l2      - PostgreSQL Euclidean distance
# - :hnsw             - Ruby HNSW (NOT WASM - slower than claimed)
# - :haystack         - Python service required
# - :hybrid           - Vector + keyword fusion
# - :hybrid_advanced  - No early termination
# - :distributed      - Cross-shard queries
# - :domain_aware     - Domain-specific routing
# - :confidence_aware - Multi-strategy parallel
```

### Document Processing

```ruby
# Requires Haystack Python service running on port 8000

# PDF extraction (real, not placeholder)
client = HaystackClient.new
result = client.extract_pdf(file_content, filename: "doc.pdf")

# Excel extraction (handles 30+ tabs efficiently)
result = client.extract_excel(file_content, filename: "budget.xlsx")

# DOCX extraction with structure preservation
result = client.extract_docx(file_content, filename: "report.docx")
```

### Embeddings

```ruby
# CRITICAL: Requires Haystack service
# If Haystack unavailable, embedding generation will FAIL (not fall back to mock)

result = client.generate_embeddings("your text", model: "sentence-transformers/all-MiniLM-L6-v2")
```

## What Requires External Services

| Feature | Required Service | Notes |
|---------|------------------|-------|
| Document extraction | Haystack (Python) | Port 8000 |
| Embedding generation | Haystack (Python) | Must be running |
| Distributed vectors | Qdrant cluster | 3+ nodes recommended |
| WASM document sandbox | Wasmtime runtime | Components not compiled |
| Metrics endpoint | Prometheus | Optional |

## Known Limitations

1. **HNSW Search** - Uses Ruby brute-force, not WASM SIMD. Performance claims in old docs are false.

2. **Scale** - The "100M+ vectors" architecture is designed but untested. Current testing limited to ~10K vectors.

3. **Raft Consensus** - Implemented in Ruby. Not battle-tested. For production, use Qdrant's native Raft instead.

4. **WASM Sandbox** - The component_sandbox.rb provides orchestration layer only. Actual WASM components (Rust) need to be compiled.

5. **Fine-tuned models** - "Organization-specific domain embedding models" don't exist. Uses standard sentence-transformers.

## Quick Start

### Prerequisites
- Ruby 3.4+
- Python 3.13+
- PostgreSQL 15+ with pgvector
- Redis 7+
- Node.js 18+

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

### Start Services

```bash
# All services (requires foreman/overmind)
./bin/dev

# Or individually:
rails server                                      # Rails (port 3000)
cd services/haystack && uvicorn app.main:app     # Python (port 8000)
redis-server                                      # Redis
```

### Verify

```bash
# Check database
rails db:migrate:status

# Check Haystack connection
curl http://localhost:8000/health

# Test search
curl -X POST http://localhost:3000/api/v1/search \
  -H "Content-Type: application/json" \
  -d '{"query": "test", "organization_id": 1}'
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
│  │SearchRouter │ │ Documents   │ │ Organizations   │   │
│  │(9 providers)│ │ Controller  │ │ (Multi-tenant)  │   │
│  └──────┬──────┘ └──────┬──────┘ └─────────────────┘   │
└─────────┼───────────────┼───────────────────────────────┘
          │               │
┌─────────▼───────────────▼───────────────────────────────┐
│                 Haystack Python Service                  │
│  ┌───────────┐ ┌───────────┐ ┌───────────────────────┐ │
│  │ Extractors│ │ Embeddings│ │ RAG Pipeline          │ │
│  │PDF/DOCX/XL│ │ Generation│ │ (OpenAI/Anthropic)    │ │
│  └───────────┘ └───────────┘ └───────────────────────┘ │
└─────────────────────────────────────────────────────────┘
          │
┌─────────▼───────────────────────────────────────────────┐
│                    Data Layer                            │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐   │
│  │ PostgreSQL  │ │   Redis     │ │ Qdrant (opt)    │   │
│  │ + pgvector  │ │   Cache     │ │ Vector cluster  │   │
│  └─────────────┘ └─────────────┘ └─────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## File Reference

### Implemented (Working)

| File | Purpose |
|------|---------|
| `app/services/search_router.rb` | 9-provider search routing |
| `app/services/haystack_client.rb` | Python service communication |
| `services/haystack/app/extractors/*.py` | PDF/DOCX/Excel extraction |
| `app/sidekiq/document_processing/*.rb` | Background processing |

### Implemented (Requires External Services)

| File | Requires |
|------|----------|
| `app/services/vector_store/qdrant_cluster_adapter.rb` | Qdrant cluster |
| `app/services/distributed/consensus/raft_node.rb` | Multi-node deployment |
| `app/services/infrastructure/metrics_exporter.rb` | Prometheus |

### Scaffolded (Needs Work)

| File | Status |
|------|--------|
| `app/services/wasm/component_sandbox.rb` | Orchestration only, needs WASM binaries |
| `app/services/wasm/scalable_index_manager.rb` | Untested at scale |

## Testing

```bash
# Run tests
bundle exec rspec

# Note: Many tests may require Haystack service running
```

## License

See LICENSE.md

---

*Last updated: December 2025*
*Honest assessment following comprehensive code audit*
