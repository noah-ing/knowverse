# Knowverse Production Architecture

## The Answer: Qdrant IS the Rust Solution

After deep analysis, the optimal architecture doesn't require custom Rust FFI or a complete rewrite. Instead, it leverages **Qdrant** - a production-grade Rust vector database with built-in Raft consensus.

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
│   │ • Raft consensus│ │ • Orgs        │   │ • DOCX extract│                │
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

## Why This Architecture

### Qdrant Provides What We Need

| Feature | Custom Ruby | Qdrant (Rust) |
|---------|-------------|---------------|
| HNSW Search | Ruby brute-force (slow) | Rust + SIMD (< 10ms) |
| Raft Consensus | 671 LOC, untested | Built-in, battle-tested |
| Sharding | Manual, error-prone | Automatic |
| Replication | Not implemented | 3-way, automatic failover |
| Scale | Untested beyond 10K | Proven at billions |

### What We Delete

```
REMOVE (~15,000 LOC):
├── app/services/distributed/consensus/     # 1,500+ LOC - Qdrant has Raft
│   ├── raft_node.rb
│   ├── raft_rpc.rb
│   ├── raft_storage.rb
│   └── *.rb
├── app/services/wasm/                      # 1,500+ LOC - Never compiled
│   ├── hnsw_index_store.rb
│   ├── scalable_index_manager.rb
│   └── component_sandbox.rb
├── app/services/distributed/search/        # Remote shard code
├── app/services/distributed/monitoring/    # Custom monitoring
├── lib/distributed/benchmark/              # 4,000+ LOC benchmarks
└── 7 of 9 search providers in search_router.rb
```

### What We Keep

```
KEEP (~15,000 LOC):
├── app/controllers/                        # Rails API
├── app/models/                             # ActiveRecord
├── app/sidekiq/                            # Background jobs
├── app/services/
│   ├── search/
│   │   └── unified_search_service.rb       # NEW: Clean Qdrant integration
│   ├── vector_store/
│   │   └── qdrant_cluster_adapter.rb       # EXISTS: Already well-written
│   └── haystack_client.rb                  # Document processing
├── services/haystack/                      # Python extraction
└── config/, db/, spec/                     # Rails infrastructure
```

## Performance Comparison

| Metric | Current (Ruby) | After (Qdrant) | Improvement |
|--------|---------------|----------------|-------------|
| Vector search | ~100-500ms | < 10ms | **50-100x** |
| Consensus latency | N/A (stub) | < 50ms | Now works |
| Scale limit | ~10K vectors | 1B+ vectors | **100,000x** |
| Replication | None | 3-way automatic | ∞ |
| Failover | None | < 5 seconds | ∞ |

## File Structure After Cleanup

```
knowverse/
├── app/
│   ├── controllers/              # Keep - API endpoints
│   ├── models/                   # Keep - ActiveRecord
│   ├── sidekiq/                  # Keep - Background jobs
│   └── services/
│       ├── search/
│       │   └── unified_search_service.rb   # NEW - 300 LOC
│       ├── vector_store/
│       │   └── qdrant_cluster_adapter.rb   # KEEP - 453 LOC
│       └── haystack_client.rb              # KEEP - HTTP client
├── config/
│   └── qdrant/
│       └── config.yaml           # NEW - Qdrant configuration
├── services/
│   └── haystack/                 # KEEP - Python service
├── docker-compose.production.yml # NEW - Full stack with Qdrant cluster
└── lib/
    └── tasks/
        └── qdrant_migration.rake # NEW - Migration utilities
```

## Implementation Steps

### Step 1: Deploy Qdrant Cluster (Day 1)

```bash
# Start the production stack
docker-compose -f docker-compose.production.yml up -d

# Verify cluster health
docker exec knowverse-qdrant-1 curl localhost:6333/cluster

# Should show:
# {
#   "result": {
#     "status": "enabled",
#     "peer_id": 12345,
#     "peers": { ... }
#   }
# }
```

### Step 2: Migrate Data (Day 2)

```bash
# Check status
bundle exec rake qdrant:status

# Run migration for all organizations
bundle exec rake qdrant:migrate

# Verify migration
bundle exec rake qdrant:verify[your_org_id]

# Benchmark performance
bundle exec rake qdrant:benchmark[your_org_id]
```

### Step 3: Switch Search Router (Day 3)

```ruby
# config/initializers/search.rb

Rails.application.config.to_prepare do
  # Use new unified search service
  Rails.configuration.search_service = Search::UnifiedSearchService.new
end
```

### Step 4: Delete Dead Code (Day 4)

```bash
# Remove Ruby Raft implementation
rm -rf app/services/distributed/consensus/

# Remove WASM pretenders
rm -rf app/services/wasm/

# Remove custom monitoring (use Qdrant's built-in)
rm -rf app/services/distributed/monitoring/

# Remove remote shard client (Qdrant handles this)
rm -rf app/services/distributed/search/

# Move benchmarks out of lib/
mv lib/distributed/benchmark/ benchmarks/

# Update search_router.rb to delegate to UnifiedSearchService
# Or delete entirely if not needed for backwards compatibility
```

### Step 5: Verify Everything Works (Day 5)

```bash
# Run tests
bundle exec rspec

# Run integration tests
bundle exec rspec spec/integration/

# Load test
bundle exec rake qdrant:benchmark[org_id]
```

## Cost Analysis

### Before (Current Infrastructure)
- PostgreSQL with pgvector: ~$50-200/month
- Redis: ~$20-50/month
- Custom Ruby code: Maintenance burden
- **Total: ~$100-300/month + high maintenance**

### After (Qdrant Architecture)
- Qdrant (3-node cluster): Self-hosted ~$150/month or Qdrant Cloud
- PostgreSQL (metadata only): ~$30/month
- Redis: ~$20/month
- Haystack: ~$50/month
- **Total: ~$250/month, minimal maintenance**

### Performance ROI
- Search latency: 100x improvement
- Developer time: 50% reduction (less code to maintain)
- Reliability: From "untested" to "battle-tested"

## FAQ

### Q: Why not write our own Rust extensions?

We created a Rust FFI prototype (`lib/knowverse_vector/`), but:
1. Qdrant already exists, is Rust, and is battle-tested
2. Custom FFI requires ongoing maintenance
3. Qdrant includes distributed consensus - we'd need that anyway
4. Time to production: Days with Qdrant vs months with custom

### Q: What about the 9 search providers?

Most were solving problems Qdrant solves natively:
- `distributed`: Qdrant has built-in sharding
- `hnsw`: Qdrant's HNSW is faster
- `domain_aware`, `confidence_aware`: Can be implemented in UnifiedSearchService

Keep 3 modes: `:semantic` (Qdrant), `:keyword` (PostgreSQL), `:hybrid` (both).

### Q: What about pgvector?

Keep PostgreSQL for metadata. Qdrant for vectors.
- Simpler than running pgvecto.rs migration
- Qdrant is purpose-built for vectors
- PostgreSQL remains the source of truth for documents

### Q: Scale projections?

| Scale | Qdrant Config | Estimated Cost |
|-------|---------------|----------------|
| 1M vectors | 3-node, 4GB each | ~$150/month |
| 10M vectors | 3-node, 16GB each | ~$400/month |
| 100M vectors | 9-node, 32GB each | ~$1,500/month |
| 1B vectors | 27-node cluster | ~$5,000/month |

## Summary

**The best solution is not custom Rust FFI or a complete rewrite.**

It's using **Qdrant** - which IS Rust, IS battle-tested, and IS designed for exactly this use case.

```
Before: 34,000 LOC with untested Ruby Raft and fake WASM
After:  15,000 LOC with production-grade Rust (via Qdrant)

Result: 50-100x faster, actually works at scale
```

---

*Architecture Version: 3.0 - Qdrant-Centric*
*Last Updated: December 2025*
