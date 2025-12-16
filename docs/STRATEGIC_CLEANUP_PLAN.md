# Knowverse Strategic Cleanup Plan

## Philosophy

**Delete more than you keep.** This codebase tried to be everything and became nothing well-tested. The path forward is aggressive simplification.

## What to KEEP (The Good Parts)

These components work and are worth preserving:

### Core Infrastructure (~8,000 LOC)
```
app/controllers/           # Rails API endpoints
app/models/                # ActiveRecord models
app/sidekiq/               # Background job definitions
config/                    # Rails configuration
db/                        # Schema and migrations
```

### Working Features
- **Authentication** - Magic link auth works
- **Multi-tenancy** - Organization isolation works
- **pgvector search** - Simple, proven, works
- **Document upload** - Active Storage integration
- **Background jobs** - Sidekiq/SolidQueue

### Python Service (Haystack)
```
services/haystack/         # Document extraction (keep)
```
This actually does useful work - PDF/DOCX/Excel extraction.

---

## What to DELETE (Over-Engineering)

### Search Providers - Delete 7 of 9

**Keep:**
- `pgvector_cosine` - Simple, works, proven
- `hybrid` - Useful for keyword + semantic

**Delete:**
- `pgvector_l2` - Redundant (cosine is enough)
- `hnsw` - Ruby brute-force pretending to be HNSW
- `haystack` - Just calls Haystack, not needed as separate provider
- `hybrid_advanced` - Over-engineered version of hybrid
- `distributed` - Requires unproven Raft implementation
- `domain_aware` - Nice idea, not tested
- `confidence_aware` - Nice idea, not tested

**Impact:** `search_router.rb` goes from 974 LOC to ~200 LOC

### Distributed Consensus - Delete All

```
DELETE: app/services/distributed/consensus/
├── raft_adapter.rb
├── raft_node.rb          # 671 LOC of unproven consensus
├── raft_rpc.rb
├── raft_storage.rb
├── log_adapter.rb
└── state_adapter.rb
```

**Why:** README says "not battle-tested". If you need distributed, use Qdrant's built-in Raft - it's written in Rust and actually tested.

### WASM Components - Delete All

```
DELETE: app/services/wasm/
├── component_sandbox.rb  # 459 LOC - never compiled
├── hnsw_index_store.rb   # 301 LOC - Ruby brute-force
└── scalable_index_manager.rb  # 813 LOC - premature optimization
```

**Why:** None of this is actually WASM. It's Ruby code pretending to be WASM.

### Benchmark Code in Production - Move or Delete

```
MOVE TO /benchmarks/:
lib/distributed/benchmark/
├── rag_performance_benchmark.rb     # 2,175 LOC
├── hybrid_search_benchmark.rb       # 1,056 LOC
└── performance_benchmark.rb         # 835 LOC
```

**Why:** 4,000+ LOC of benchmark code sitting in `lib/` is not production code.

### Redundant Vector Stores - Delete 4 of 5

**Keep:**
- PostgreSQL + pgvector (simple, works)

**Delete:**
- `qdrant_cluster_adapter.rb` - Adapter for service you don't run
- `scalable_index_manager.rb` - Premature optimization
- `hnsw_index_store.rb` - Ruby brute-force
- Custom distributed sharding - Use Qdrant if you need this

---

## Estimated Impact

| Metric | Before | After | Reduction |
|--------|--------|-------|-----------|
| Ruby LOC | 34,000 | ~15,000 | **56%** |
| Search Providers | 9 | 2 | **78%** |
| Vector Stores | 5 | 1 | **80%** |
| God Classes | 9 | 2-3 | **67%** |
| External Deps | 113 | ~70 | **38%** |

---

## Execution Order

### Phase 1: Delete Dead Code (Day 1)
```bash
# Remove WASM pretenders
rm -rf app/services/wasm/

# Remove unproven distributed consensus
rm -rf app/services/distributed/consensus/
rm -rf app/services/distributed/monitoring/
rm -rf app/services/distributed/search/
rm app/services/distributed/distributed_service.rb

# Move benchmarks out of lib/
mv lib/distributed/benchmark/ benchmarks/distributed/

# Remove Rust extension (not compiled anyway)
rm -rf lib/knowverse_vector/
```

### Phase 2: Simplify Search Router (Day 2)
```ruby
# app/services/search_router.rb - New version (~200 LOC)

class SearchRouter
  PROVIDERS = {
    pgvector_cosine: 'Cosine Similarity',
    hybrid: 'Hybrid Search'
  }.freeze

  def route_query(query, organization_id, options = {})
    provider = options[:provider] || :pgvector_cosine

    case provider
    when :pgvector_cosine
      search_pgvector_cosine(query, organization_id, options)
    when :hybrid
      search_hybrid(query, organization_id, options)
    else
      raise ArgumentError, "Unknown provider: #{provider}"
    end
  end

  private

  def search_pgvector_cosine(query, organization_id, options)
    # Simple pgvector search - the only thing that's actually tested
    embedding = generate_embedding(query, organization_id)

    VectorEmbedding
      .joins(:document)
      .where(documents: { organization_id: organization_id })
      .order(Arel.sql("embedding <=> '#{embedding}'"))
      .limit(options[:limit] || 10)
      .map { |ve| format_result(ve) }
  end

  def search_hybrid(query, organization_id, options)
    # Combine vector + keyword search
    vector_results = search_pgvector_cosine(query, organization_id, options)
    keyword_results = search_keyword(query, organization_id, options)
    merge_results(vector_results, keyword_results, options)
  end
end
```

### Phase 3: Fix Tests (Week 1)
```ruby
# Delete tests that skip
# Replace with tests that actually run

# spec/services/search_router_spec.rb
RSpec.describe SearchRouter do
  # Don't skip - use fixtures or mocks
  let(:organization) { create(:organization) }
  let(:documents) { create_list(:document, 5, :with_embeddings, organization: organization) }

  describe '#route_query' do
    it 'returns results for pgvector_cosine' do
      results = SearchRouter.new.route_query('test', organization.id, provider: :pgvector_cosine)
      expect(results).to be_an(Array)
    end

    it 'returns results for hybrid' do
      results = SearchRouter.new.route_query('test', organization.id, provider: :hybrid)
      expect(results).to be_an(Array)
    end
  end
end
```

### Phase 4: Document What Remains (Week 2)

After cleanup, document what the system actually does:

```markdown
# Knowverse - Simplified

## What It Does
- Document upload and storage
- Text extraction (PDF, DOCX, Excel via Haystack)
- Vector similarity search (pgvector)
- Hybrid search (vector + keyword)
- Multi-tenant organization isolation

## What It Doesn't Do
- Distributed consensus (use Qdrant if you need this)
- WASM-accelerated search (not implemented)
- 100M+ vector scale (not tested)
- 9 different search strategies (simplified to 2)

## Architecture
Rails API → PostgreSQL + pgvector → Haystack (Python)

That's it. Simple. Testable. Maintainable.
```

---

## Decision Framework

### Stay with Current Codebase If:
- You need multi-tenant Rails infrastructure
- pgvector search is sufficient for your scale (<1M vectors)
- You're willing to delete the over-engineering
- You have Rails developers

### Start Fresh If:
- You need true distributed scale (100M+ vectors)
- You want to use Qdrant/Pinecone/Weaviate natively
- The Rails infrastructure doesn't match your needs
- You prefer a different language/framework

### The Honest Answer

**This codebase is salvageable but only if you're willing to delete 50%+ of it.**

The core Rails infrastructure is valuable. The search over-engineering is not. The unproven distributed consensus is dangerous. The WASM code is fiction.

Delete aggressively. Keep what works. Test what remains.

---

## Alternative: Minimal Viable Fresh Start

If you decide to start fresh, here's what you actually need:

```
fresh-knowverse/
├── app/
│   ├── controllers/
│   │   ├── documents_controller.rb
│   │   ├── search_controller.rb
│   │   └── organizations_controller.rb
│   ├── models/
│   │   ├── document.rb
│   │   ├── organization.rb
│   │   └── vector_embedding.rb
│   └── services/
│       ├── search_service.rb        # ONE search implementation
│       └── embedding_service.rb     # Calls Haystack
├── config/
├── db/
│   └── migrate/
│       ├── create_organizations.rb
│       ├── create_documents.rb
│       └── create_vector_embeddings.rb  # With pgvector
└── spec/
    └── services/
        └── search_service_spec.rb   # Tests that actually run
```

**~3,000 LOC instead of 34,000 LOC.**
**1 search implementation instead of 9.**
**Tests that run instead of skip.**

That's what "the best" version of this project looks like.
