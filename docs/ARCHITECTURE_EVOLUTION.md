# Knowverse Architecture Evolution Roadmap

## Current State (December 2025)

```
┌─────────────────────────────────────────────────────────────┐
│                     Current Architecture                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────────┐│
│  │                 Rails 8 (Ruby 3.4)                      ││
│  │  • HTTP API, Auth, Multi-tenancy                       ││
│  │  • Background jobs (Sidekiq/SolidQueue)                ││
│  │  • Database ORM, Admin UI                               ││
│  └─────────────────────┬──────────────────────────────────┘│
│                        │                                     │
│  ┌─────────────────────▼──────────────────────────────────┐│
│  │        BOTTLENECK: Ruby Vector Operations               ││
│  │  • hnsw_index_store.rb - 50-100x slower than Rust      ││
│  │  • raft_node.rb - interpreted hot paths                ││
│  │  • distance calculations in loops                       ││
│  └─────────────────────┬──────────────────────────────────┘│
│                        │                                     │
│  ┌─────────────────────▼──────────────────────────────────┐│
│  │              PostgreSQL + pgvector                       ││
│  │  • Works for <1M vectors                                ││
│  │  • Slowdown at scale                                    ││
│  └────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌────────────────────────────────────────────────────────┐│
│  │              Python Haystack Service                     ││
│  │  • Document extraction (working)                        ││
│  │  • Embedding generation (sentence-transformers)         ││
│  └────────────────────────────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Evolution Phases

### Phase 1: Rust FFI for Hot Paths (LOW EFFORT, HIGH IMPACT)

**Status: Scaffolded** - See `lib/knowverse_vector/`

Add Rust extensions via Magnus gem for the critical bottlenecks:

```
┌─────────────────────────────────────────────────────────────┐
│                         Phase 1                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────────┐│
│  │                 Rails 8 (unchanged)                      ││
│  └─────────────────────┬──────────────────────────────────┘│
│                        │ FFI via Magnus gem                  │
│  ┌─────────────────────▼──────────────────────────────────┐│
│  │           NEW: Rust Vector Extension                     ││
│  │  • KnowverseVector::Distance.euclidean()               ││
│  │  • KnowverseVector::Batch.find_nearest()               ││
│  │  • SIMD-accelerated, 50-100x speedup                   ││
│  └────────────────────────────────────────────────────────┘│
│                                                              │
│  Implementation:                                             │
│  • lib/knowverse_vector/Cargo.toml                          │
│  • lib/knowverse_vector/src/lib.rs                          │
│  • lib/knowverse_vector.rb (Ruby bindings + fallback)       │
│                                                              │
│  Build: cd lib/knowverse_vector && cargo build --release    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Expected Impact:**
- Vector distance calculations: 50-100x faster
- HNSW search: 20-50x faster (dominated by distance calc)
- No architectural changes required

**Files to Modify:**
```ruby
# app/services/wasm/hnsw_index_store.rb
# Replace:
def euclidean_distance(a, b)
  squared_diff_sum = a.zip(b).sum { |x, y| (x - y) ** 2 }
  Math.sqrt(squared_diff_sum)
end

# With:
def euclidean_distance(a, b)
  KnowverseVector::Distance.euclidean(a, b)
end
```

---

### Phase 2: Replace pgvector with pgvecto.rs (MEDIUM EFFORT)

Swap PostgreSQL extension for 20x improvement at 90% recall:

```
┌─────────────────────────────────────────────────────────────┐
│                         Phase 2                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────────┐│
│  │           PostgreSQL + pgvecto.rs                        ││
│  │  • Rust-based vector extension                          ││
│  │  • HNSW index: 20x faster than pgvector                 ││
│  │  • Same SQL interface                                    ││
│  └────────────────────────────────────────────────────────┘│
│                                                              │
│  Migration:                                                  │
│  1. Install pgvecto.rs extension                            │
│  2. Create new vector column with pgvecto.rs type           │
│  3. Migrate embeddings (batch copy)                         │
│  4. Swap index configuration                                │
│  5. Drop pgvector column                                    │
│                                                              │
│  Benchmark (from pgvecto.rs):                               │
│  • 471 QPS at 99% recall on 50M vectors                    │
│  • vs pgvector: 11.4x better at same recall                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**SQL Changes:**
```sql
-- Before (pgvector)
CREATE EXTENSION vector;
ALTER TABLE vector_embeddings ADD COLUMN embedding vector(768);
CREATE INDEX ON vector_embeddings USING hnsw (embedding vector_cosine_ops);

-- After (pgvecto.rs)
CREATE EXTENSION vectors;
ALTER TABLE vector_embeddings ADD COLUMN embedding_v2 vector(768);
CREATE INDEX ON vector_embeddings USING vectors (embedding_v2 vector_cos_ops);
```

---

### Phase 3: Qdrant for Large Scale (HIGH EFFORT, HIGHEST SCALE)

Replace custom Raft + pgvector with Qdrant cluster:

```
┌─────────────────────────────────────────────────────────────┐
│                         Phase 3                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────────┐│
│  │                 Rails 8 (API layer)                      ││
│  └─────────────────────┬──────────────────────────────────┘│
│                        │ HTTP/gRPC                           │
│  ┌─────────────────────▼──────────────────────────────────┐│
│  │            Qdrant Cluster (Rust)                         ││
│  │  • Built-in Raft consensus (battle-tested)              ││
│  │  • HNSW indexes (native Rust, SIMD)                     ││
│  │  • Horizontal sharding                                  ││
│  │  • 3-way replication                                    ││
│  └────────────────────────────────────────────────────────┘│
│                                                              │
│  Benefits:                                                   │
│  • Delete: raft_node.rb, raft_rpc.rb, raft_storage.rb      │
│  • Delete: hnsw_index_store.rb                              │
│  • Delete: distributed_search_service.rb (shard logic)     │
│  • Proven at billions of vectors                           │
│                                                              │
│  Architecture adapter already exists:                        │
│  • app/services/vector_store/qdrant_cluster_adapter.rb     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Migration Path:**
1. Deploy Qdrant cluster alongside existing system
2. Dual-write vectors to both pgvector and Qdrant
3. Shadow-read from Qdrant to validate consistency
4. Gradually shift read traffic
5. Cutover and deprecate custom distributed code

---

### Phase 4: WASM Document Processing (OPTIONAL)

Replace Python Haystack with WASM sandboxed extractors:

```
┌─────────────────────────────────────────────────────────────┐
│                         Phase 4                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────────┐│
│  │              WASM Runtime (Wasmtime)                     ││
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐             ││
│  │  │   PDF    │  │   DOCX   │  │  Excel   │             ││
│  │  │ (lopdf)  │  │(docx-rs) │  │(calamine)│             ││
│  │  │  Rust    │  │  Rust    │  │  Rust    │             ││
│  │  └──────────┘  └──────────┘  └──────────┘             ││
│  └────────────────────────────────────────────────────────┘│
│                                                              │
│  Benefits:                                                   │
│  • Sandboxed execution (memory isolation)                   │
│  • No Python dependency                                      │
│  • Portable (runs in browser too)                           │
│                                                              │
│  Current Status:                                             │
│  • Orchestration layer exists (component_sandbox.rb)        │
│  • WASM binaries need to be compiled                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Recommended Implementation Order

| Phase | Effort | Impact | Dependencies | Timeline |
|-------|--------|--------|--------------|----------|
| 1. Rust FFI | Low | High | None | Days |
| 2. pgvecto.rs | Medium | Medium | PostgreSQL rebuild | Weeks |
| 3. Qdrant | High | Highest | Infrastructure | Months |
| 4. WASM | High | Medium | Rust toolchain | Optional |

## Decision Framework

### When to Stay with Current Architecture
- < 1M vectors
- Query latency < 100ms acceptable
- Limited Rust expertise on team
- Rapid feature iteration priority

### When to Evolve to Phase 1 (Rust FFI)
- Seeing CPU bottleneck in vector operations
- Need < 50ms query latency
- Have Ruby + Rust developers
- **Recommended as first step**

### When to Evolve to Phase 2 (pgvecto.rs)
- 1M - 50M vectors
- Want to stay PostgreSQL-native
- pgvector index builds taking too long
- Need better recall at same latency

### When to Evolve to Phase 3 (Qdrant)
- > 50M vectors
- Need horizontal scaling
- Want managed distributed consensus
- Production reliability critical

---

## Benchmarking Guidelines

Before/after each phase, measure:

```bash
# Run vector operation benchmarks
bundle exec ruby benchmarks/vector_operations_benchmark.rb

# Key metrics to track:
# - p99 query latency (target: < 50ms)
# - Queries per second (target: > 1000 QPS)
# - Index build time
# - Memory usage per vector
# - Recall @ k=10
```

## Files Reference

| Component | Current | Phase 1 | Phase 3 |
|-----------|---------|---------|---------|
| Vector Distance | `hnsw_index_store.rb:279` | `lib/knowverse_vector/src/lib.rs` | Qdrant native |
| HNSW Index | `hnsw_index_store.rb` | Same + Rust distance | Qdrant native |
| Consensus | `raft_node.rb` | Same | Qdrant native Raft |
| Sharding | `sharding_manager.rb` | Same | Qdrant native |
| Postgres | pgvector | pgvecto.rs | Metadata only |

---

*Last Updated: December 2025*
