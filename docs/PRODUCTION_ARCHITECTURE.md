# Knowverse Production Architecture

## Overview

Knowverse uses a Qdrant-centric architecture for production-grade vector search.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PRODUCTION ARCHITECTURE                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         RAILS 8 API LAYER                            │   │
│   │                                                                      │   │
│   │  • Authentication (Magic link, OAuth)                               │   │
│   │  • Multi-tenant organization management                             │   │
│   │  • API routing and rate limiting                                    │   │
│   │  • Background job orchestration (Sidekiq)                           │   │
│   │  • Admin dashboard and analytics                                    │   │
│   │                                                                      │   │
│   │  WHY RAILS: Fast development, excellent for auth/multi-tenancy      │   │
│   └───────────────────────────┬─────────────────────────────────────────┘   │
│                               │                                              │
│           ┌───────────────────┼───────────────────┐                         │
│           │                   │                   │                         │
│           ▼                   ▼                   ▼                         │
│   ┌───────────────┐   ┌───────────────┐   ┌───────────────┐                │
│   │    QDRANT     │   │  POSTGRESQL   │   │   HAYSTACK    │                │
│   │   CLUSTER     │   │               │   │   (PYTHON)    │                │
│   │    (RUST)     │   │               │   │               │                │
│   ├───────────────┤   ├───────────────┤   ├───────────────┤                │
│   │               │   │               │   │               │                │
│   │ • HNSW search │   │ • Users       │   │ • PDF extract │                │
│   │ • Raft        │   │ • Orgs        │   │ • DOCX extract│                │
│   │ • 3-way repl. │   │ • Documents   │   │ • Excel parse │                │
│   │ • Auto shard  │   │ • Settings    │   │ • Embeddings  │                │
│   │ • SIMD accel. │   │ • Audit logs  │   │               │                │
│   │               │   │               │   │               │                │
│   │ Performance:  │   │ Role: Meta-   │   │ Role: Doc     │                │
│   │ <10ms search  │   │ data only     │   │ processing    │                │
│   │               │   │               │   │               │                │
│   └───────────────┘   └───────────────┘   └───────────────┘                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Why Qdrant

| Feature | Previous (Ruby) | Current (Qdrant) |
|---------|-----------------|------------------|
| HNSW Search | Ruby brute-force | Rust + SIMD (< 10ms) |
| Consensus | 671 LOC Ruby, untested | Built-in Raft, battle-tested |
| Sharding | Manual | Automatic |
| Replication | None | 3-way, automatic failover |
| Scale | ~10K vectors tested | Proven at billions |

## Architecture Components

### Rails API Layer
- Authentication and session management
- Multi-tenant organization isolation
- API rate limiting and throttling
- Background job orchestration via Sidekiq
- Admin dashboard

### Qdrant Cluster (Vector Storage)
- 3-node cluster with Raft consensus
- HNSW index with SIMD acceleration
- Sub-10ms search latency
- Automatic sharding and replication

### PostgreSQL (Metadata)
- User and organization data
- Document metadata
- Full-text keyword search
- Audit logs

### Haystack (Python)
- Document extraction (PDF, DOCX, Excel)
- Embedding generation (sentence-transformers)
- all-mpnet-base-v2 model (768 dimensions)

## File Structure

```
knowverse/
├── app/
│   ├── controllers/              # API endpoints
│   ├── models/                   # ActiveRecord models
│   ├── sidekiq/                  # Background workers
│   └── services/
│       ├── search/
│       │   └── unified_search_service.rb   # 400 LOC - Search orchestration
│       ├── vector_store/
│       │   └── qdrant_cluster_adapter.rb   # Qdrant HTTP client
│       ├── vector_search/
│       │   └── component_bridge.rb         # Component lifecycle
│       ├── search_router.rb                # Backwards-compatible API
│       └── haystack_client.rb              # Python service client
├── config/
│   └── qdrant/
│       └── config.yaml           # Qdrant configuration
├── services/
│   └── haystack/                 # Python extraction service
├── docker-compose.production.yml # Full production stack
└── lib/
    └── tasks/
        └── qdrant_migration.rake # Migration utilities
```

## Deployment

### Start Production Stack

```bash
docker-compose -f docker-compose.production.yml up -d
```

This starts:
- 3-node Qdrant cluster (ports 6333-6335)
- Rails API (port 3000)
- Sidekiq workers
- Haystack service (port 8000)
- PostgreSQL
- Redis

### Environment Variables

```bash
QDRANT_CLUSTER_URLS=http://qdrant-node-1:6333,http://qdrant-node-2:6333,http://qdrant-node-3:6333
HAYSTACK_URL=http://haystack:8000
DATABASE_URL=postgres://postgres:postgres@postgres:5432/knowverse_production
REDIS_URL=redis://redis:6379/0
```

## Search Modes

### Semantic Search (`:semantic`)
Uses Qdrant's HNSW index for vector similarity search.
- Latency: < 10ms
- Best for: Finding conceptually similar documents

### Keyword Search (`:keyword`)
Uses PostgreSQL full-text search.
- Latency: ~20-50ms
- Best for: Exact phrase matching

### Hybrid Search (`:hybrid`)
Combines semantic and keyword search with Reciprocal Rank Fusion.
- Latency: ~30-60ms (parallel execution)
- Best for: Production use - balances precision and recall

## Migration from pgvector

```bash
# Check Qdrant cluster health
bundle exec rake qdrant:status

# Migrate all organizations
bundle exec rake qdrant:migrate

# Migrate specific organization
bundle exec rake qdrant:migrate[org_123]

# Verify migration
bundle exec rake qdrant:verify[org_123]

# Benchmark performance
bundle exec rake qdrant:benchmark[org_123]
```

## Performance Expectations

| Metric | Value |
|--------|-------|
| Semantic search | < 10ms (Qdrant) |
| Keyword search | ~20-50ms (PostgreSQL) |
| Hybrid search | ~30-60ms |
| Embedding generation | ~50-100ms (Haystack) |
| Document extraction | 100ms-5s (varies by type) |

## Scale Projections

| Scale | Qdrant Config | Estimated Cost |
|-------|---------------|----------------|
| 1M vectors | 3-node, 4GB each | ~$150/month |
| 10M vectors | 3-node, 16GB each | ~$400/month |
| 100M vectors | 9-node, 32GB each | ~$1,500/month |
| 1B vectors | 27-node cluster | ~$5,000/month |

---

*Architecture Version: 3.0 - Qdrant-Centric*
*Implementation Status: Complete*
*Last Updated: December 2025*
