# Elite RAG Implementation Plan

**Based on codebase audit - building on existing foundation**

---

## What We Already Have (Reuse)

### Haystack Service (Python)
| Component | Status | Notes |
|-----------|--------|-------|
| `embeddings.py` | ✅ Good | ModelRegistry, OpenAI support, domain models |
| `retrieval.py` | ⚠️ Enhance | Has ContextRetriever, needs RAG-Fusion/HyDE |
| `generation.py` | ✅ Good | OpenAI/Anthropic/Local, streaming |
| `query_parser.py` | ⚠️ Enhance | Basic parsing, needs intent/entity extraction |
| `search.py` | ⚠️ Enhance | Has hybrid, needs cross-encoder reranking |
| `qdrant_client.py` | ✅ Good | Working Qdrant integration |

### Rails Services
| Component | Status | Notes |
|-----------|--------|-------|
| `UnifiedSearchService` | ✅ Good | Main search abstraction |
| `HaystackClient` | ✅ Good | Ruby-Python bridge |
| `EmbeddingCache` | ✅ Good | Two-tier cache (memory + Redis) |
| `DomainConfidenceManager` | ⚠️ Enhance | Basis for domain routing |

### Database Schema
| Table | Status | Notes |
|-------|--------|-------|
| `documents` | ✅ Good | Has status, metadata |
| `vector_embeddings` | ✅ Good | Multi-model support |
| `conversation_sessions` | ⚠️ Enhance | Needs memory fields |
| `conversation_messages` | ✅ Good | Has role, metadata |
| `domain_confidence_scores` | ✅ Good | Domain detection foundation |
| `search_feedbacks` | ✅ Good | Feedback loop exists |

### Ingestion
| Script | Status | Notes |
|--------|--------|-------|
| `enterprise_ingest.py` | ✅ Good | Resume capability, SEC EDGAR |

---

## What We Need to Build

### Phase 1: Advanced Retrieval (Clean Extensions)

**New file: `services/haystack/app/advanced_retrieval.py`**
```
- RAGFusion class (multi-query + RRF)
- HyDE class (hypothetical document embeddings)
- CrossEncoderReranker class
- MultiHopRetriever class
```

**Enhance: `services/haystack/app/retrieval.py`**
```
- Add strategy parameter to ContextRetriever.retrieve_context()
- Wire in advanced retrieval classes
- Keep backward compatibility
```

### Phase 2: Memory System (New Module)

**New file: `services/haystack/app/memory.py`**
```
- WorkingMemory (per-request, already implicit)
- ShortTermMemory (session, Redis-backed)
- LongTermMemory (user/org, PostgreSQL + Qdrant)
- MemoryManager (orchestrates all tiers)
```

**New migration for Rails:**
```ruby
# Add to conversation_sessions
- summary (text)           # Compressed history
- entity_cache (jsonb)     # Tracked entities

# New table: user_memories
- user_id, org_id
- memory_type (episodic/semantic/procedural)
- content, embedding_id
- importance_score, decay_timestamp
```

### Phase 3: Query Understanding (New Module)

**New file: `services/haystack/app/query_understanding.py`**
```
- IntentClassifier (factual/analytical/comparative/procedural)
- EntityExtractor (company/person/date/product/metric)
- DomainRouter (finance/science/technical/general)
- QueryDecomposer (for multi-hop)
```

**Enhance: `services/haystack/app/query_parser.py`**
```
- Add intent detection
- Add entity extraction
- Keep existing keyword/phrase extraction
```

### Phase 4: Multi-Collection (Configuration)

**New file: `services/haystack/config/collections.py`**
```python
COLLECTIONS = {
    "sec_edgar": {
        "embedding_model": "ada-002",
        "dimension": 1536,
        "quantization": "scalar",
        "priority": 1,
    },
    "wikipedia": {
        "embedding_model": "e5-large-v2",
        "dimension": 1024,
        "quantization": "binary",
        "priority": 2,
    },
    # ... etc
}
```

**Enhance: `services/haystack/app/qdrant_client.py`**
```
- Add collection config lookup
- Add cross-collection search
- Add quantization setup
```

### Phase 5: Quality Assurance (New Module)

**New file: `services/haystack/app/quality.py`**
```
- HallucinationDetector (claim extraction + verification)
- CitationVerifier (check quotes against sources)
- ConfidenceScorer (multi-factor scoring)
```

---

## Clean File Structure

```
services/haystack/
├── app/
│   ├── __init__.py
│   ├── main.py                    # FastAPI app (existing)
│   │
│   ├── # RETRIEVAL (existing + new)
│   ├── retrieval.py               # Enhanced ContextRetriever
│   ├── advanced_retrieval.py      # NEW: RAG-Fusion, HyDE, reranking
│   ├── search.py                  # Existing search pipelines
│   ├── qdrant_client.py           # Enhanced with multi-collection
│   │
│   ├── # GENERATION (existing)
│   ├── generation.py              # LLM providers
│   │
│   ├── # EMBEDDINGS (existing)
│   ├── embeddings.py              # ModelRegistry, OpenAI, local
│   │
│   ├── # QUERY UNDERSTANDING (new)
│   ├── query_parser.py            # Enhanced with intent/entity
│   ├── query_understanding.py     # NEW: IntentClassifier, EntityExtractor
│   │
│   ├── # MEMORY (new)
│   ├── memory.py                  # NEW: 3-tier memory system
│   │
│   ├── # QUALITY (new)
│   ├── quality.py                 # NEW: Hallucination, citations
│   │
│   ├── # DOCUMENT PROCESSING (existing)
│   ├── document_store.py
│   └── extractors/
│       ├── pdf_extractor.py
│       ├── docx_extractor.py
│       └── excel_extractor.py
│
├── config/
│   ├── settings.py                # Existing settings
│   └── collections.py             # NEW: Collection configs
│
└── requirements.txt               # Add: sentence-transformers, cross-encoder
```

---

## Implementation Order

### Week 1-2: Foundation + Ingestion

**Day 1-2: Clean up and standardize**
- [ ] Audit all existing code for consistency
- [ ] Add type hints where missing
- [ ] Standardize error handling
- [ ] Create collection config system

**Day 3-4: Multi-collection setup**
- [ ] Create `config/collections.py`
- [ ] Enhance `qdrant_client.py` for multi-collection
- [ ] Set up Wikipedia collection (binary quantization)
- [ ] Set up arXiv collection (scalar quantization)

**Day 5-7: Dataset ingestion**
- [ ] Ingest Wikipedia (6M vectors) - use local e5-large
- [ ] Ingest StackOverflow subset (1M vectors) - test scale
- [ ] Verify cross-collection search works

### Week 3-4: Advanced Retrieval

**Day 1-2: RAG-Fusion**
- [ ] Create `advanced_retrieval.py`
- [ ] Implement RAGFusion class
- [ ] Add reciprocal rank fusion
- [ ] Wire into retrieval.py

**Day 3-4: HyDE + Reranking**
- [ ] Implement HyDE class
- [ ] Add cross-encoder reranking (ms-marco model)
- [ ] Benchmark retrieval quality

**Day 5-7: Multi-hop**
- [ ] Implement MultiHopRetriever
- [ ] Add query decomposition
- [ ] Test on complex queries

### Week 5-6: Query Understanding

**Day 1-3: Intent + Entities**
- [ ] Create `query_understanding.py`
- [ ] Implement IntentClassifier
- [ ] Implement EntityExtractor
- [ ] Train/fine-tune on sample data

**Day 4-5: Domain Routing**
- [ ] Implement DomainRouter
- [ ] Wire into main retrieval flow
- [ ] Test multi-domain queries

**Day 6-7: Integration**
- [ ] Connect all query understanding
- [ ] End-to-end testing
- [ ] Performance optimization

### Week 7-8: Memory System

**Day 1-2: Database migrations**
- [ ] Add memory tables to Rails
- [ ] Create memory indexes
- [ ] Set up episodic memory collection in Qdrant

**Day 3-5: Memory implementation**
- [ ] Create `memory.py`
- [ ] Implement ShortTermMemory (Redis)
- [ ] Implement LongTermMemory (PostgreSQL + Qdrant)
- [ ] Add forgetting curves

**Day 6-7: Integration**
- [ ] Wire memory into RAG pipeline
- [ ] Test conversation continuity
- [ ] Test personalization

### Week 9-10: Quality + Scale

**Day 1-3: Quality assurance**
- [ ] Create `quality.py`
- [ ] Implement HallucinationDetector
- [ ] Implement CitationVerifier
- [ ] Add confidence scoring

**Day 4-5: Scale optimization**
- [ ] Configure quantization per collection
- [ ] Set up tiered storage
- [ ] Implement caching for embeddings/results

**Day 6-7: Final integration**
- [ ] End-to-end testing
- [ ] Performance benchmarks
- [ ] Documentation

---

## Security Notes (For Frontend Phase)

When we get to frontend (JS):
- [ ] Implement Content Security Policy (CSP)
- [ ] Sanitize all user inputs (XSS prevention)
- [ ] Use Rails CSRF protection
- [ ] Escape HTML in all dynamic content
- [ ] Validate/sanitize query parameters
- [ ] Implement rate limiting on API
- [ ] Use SRI (Subresource Integrity) for external scripts
- [ ] Audit npm dependencies for vulnerabilities

---

## Success Criteria

| Metric | Current | Target | How to Measure |
|--------|---------|--------|----------------|
| Collections | 1 | 5+ | Qdrant collection count |
| Vector count | 35K | 10M+ | Qdrant point count |
| Retrieval recall@10 | ~70% | 90%+ | MS MARCO eval |
| Answer accuracy | ~75% | 90%+ | Human eval + auto |
| P95 latency | 2-3s | <1s | Prometheus metrics |
| Memory context | None | 3 tiers | Feature complete |

---

## Getting Started

```bash
# 1. Verify current state
curl http://localhost:8000/health
curl http://localhost:6333/collections

# 2. Check external drive
ls /Volumes/monster/knowverse/

# 3. Start with collection config
# Create services/haystack/config/collections.py

# 4. Begin Wikipedia ingestion
python scripts/ingest_elite.py --dataset wikipedia --limit 100000
```
