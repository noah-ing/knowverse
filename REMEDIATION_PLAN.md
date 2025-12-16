# Knowverse Enterprise Remediation Plan

## Implementation Status

| Phase | Description | Status | Completion |
|-------|-------------|--------|------------|
| Phase 1 | Document Processing Foundation | ✅ **COMPLETE** | 100% |
| Phase 2 | Complete all 9 Search Providers | ✅ **COMPLETE** | 100% |
| Phase 3 | Real Distributed Raft Consensus | ✅ **COMPLETE** | 100% |
| Phase 4 | Scale to 100M+ Vectors | ✅ **COMPLETE** | 100% |
| Phase 5 | Production Hardening | 🔄 **IN PROGRESS** | 30% |

### Implementation Summary

**Phase 1 - Document Processing** (Completed):
- ✅ PDF extraction with pdfplumber (layout, tables, images)
- ✅ DOCX extraction with python-docx (structure preservation)
- ✅ Excel extraction with fastexcel (10-100x faster than openpyxl)
- ✅ Semantic, sentence, and fixed-size chunking strategies
- ✅ HaystackClient integration for extraction endpoints

**Phase 2 - Search Providers** (Completed):
- ✅ domain_aware provider with DomainConfidenceManager
- ✅ confidence_aware provider with multi-strategy parallel execution
- ✅ CRITICAL FIX: Removed mock embedding fallback that corrupted search

**Phase 3 - Raft Consensus** (Completed):
- ✅ RaftNode: Full state machine (Follower/Candidate/Leader)
- ✅ RaftRPC: HTTP-based transport for RequestVote/AppendEntries
- ✅ RaftStorage: Persistent WAL with checksums
- ✅ RemoteShardClient: Cross-shard queries with circuit breaker
- ✅ ClusterHealthMonitor: Real-time health tracking and alerts

**Phase 4 - Scale to 100M+** (Completed):
- ✅ ScalableIndexManager: Hierarchical partitioning (100K per partition)
- ✅ Tiered storage: Hot (memory) / Warm (SSD) / Cold (compressed)
- ✅ LRU eviction with configurable hot partition limits
- ✅ Automatic compaction at 30% deletion threshold
- ✅ Disk persistence with Oj serialization

---

## Executive Summary

This document outlines the comprehensive plan to transform Knowverse from a marketing prototype into a genuinely production-ready enterprise system capable of:

- Processing **hundreds of millions of vectors** in a distributed architecture
- Ingesting **real documents** (Excel, Word, PDF) with actual text extraction
- Providing **9 functional search providers** (currently 7 work, 2 are stubs)
- Delivering **true distributed consensus** (currently 100% stubbed)

---

## Current State Assessment

### What Actually Works (Keep)

| Component | Status | Notes |
|-----------|--------|-------|
| Rails 8 infrastructure | ✅ Solid | Multi-tenant, auth, API |
| PostgreSQL + pgvector | ✅ Working | Cosine & L2 similarity |
| Redis caching | ✅ Working | Two-tier cache |
| Sidekiq/SolidQueue | ✅ Working | Background jobs |
| Text file processing | ✅ Working | TXT, MD, RTF |
| 7 search providers | ✅ Working | pgvector_cosine, pgvector_l2, hnsw, haystack, hybrid, hybrid_advanced, distributed |
| Embedding generation | ⚠️ Conditional | Works if Haystack running, else mock |
| SSE streaming | ✅ Working | RAG responses |

### What's Broken/Stubbed (Fix)

| Component | Current State | Impact |
|-----------|---------------|--------|
| PDF extraction | Returns placeholder string | Zero real PDF content |
| DOCX extraction | Returns placeholder string | Zero real Word content |
| Excel support | Not implemented | Can't process spreadsheets |
| Document chunking | Does not exist | Poor embeddings for large docs |
| Raft consensus | 100% logging stubs | No distributed coordination |
| Remote shard queries | Returns `[]` | Cross-node search broken |
| HNSW WASM | Mock implementation | Not real HNSW |
| domain_aware provider | Declared, not implemented | Falls to hybrid silently |
| confidence_aware provider | Declared, not implemented | Falls to hybrid silently |
| Domain model training | Fake accuracy scores | No real fine-tuning |

### Scale Limitations

| Metric | Current | Target | Gap |
|--------|---------|--------|-----|
| Max vectors per node | 5M | 100M+ | 20x |
| Active partitions | 5 | Unlimited | Architecture change |
| Memory quota | 4GB | 64GB+ | Config + horizontal |
| Shard rebalancing | Metadata only | Actual data movement | Full implementation |
| Failure recovery | 30s mock | <5s automatic | Real Raft needed |

---

## Phase 1: Document Processing Foundation

**Goal**: Real document ingestion for all claimed file types

### 1.1 PDF Extraction (Priority: Critical)

**Current**: `extract_text_from_pdf()` returns `"Extracted text from PDF document. File: #{filename}"`

**Solution**: Integrate `pypdf` or `pdfplumber` in Python Haystack service

```python
# services/haystack/app/extractors/pdf_extractor.py
from pypdf import PdfReader
import pdfplumber

def extract_text_from_pdf(file_path: str) -> dict:
    """Extract text with layout preservation"""
    text_blocks = []

    with pdfplumber.open(file_path) as pdf:
        for i, page in enumerate(pdf.pages):
            text = page.extract_text(layout=True)
            tables = page.extract_tables()
            text_blocks.append({
                'page': i + 1,
                'text': text,
                'tables': tables
            })

    return {
        'content': '\n\n'.join([b['text'] for b in text_blocks]),
        'pages': len(text_blocks),
        'tables': sum(len(b['tables']) for b in text_blocks),
        'blocks': text_blocks
    }
```

**Dependencies to add**:
```
# services/haystack/requirements.txt
pypdf>=4.0.0
pdfplumber>=0.10.0
```

**Files to modify**:
- `app/sidekiq/document_processing/text_extraction_worker.rb` (lines 138-148)
- `services/haystack/app/main.py` (add `/extract/pdf` endpoint)

### 1.2 Word Document Extraction (Priority: Critical)

**Current**: `extract_text_from_docx()` returns `"Extracted text from Word document. File: #{filename}"`

**Solution**: Integrate `python-docx` in Haystack service

```python
# services/haystack/app/extractors/docx_extractor.py
from docx import Document
from docx.table import Table

def extract_text_from_docx(file_path: str) -> dict:
    """Extract text preserving structure"""
    doc = Document(file_path)

    content_blocks = []

    for element in doc.element.body:
        if element.tag.endswith('p'):
            # Paragraph
            para = doc.paragraphs[len([e for e in content_blocks if e['type'] == 'paragraph'])]
            content_blocks.append({
                'type': 'paragraph',
                'text': para.text,
                'style': para.style.name if para.style else None
            })
        elif element.tag.endswith('tbl'):
            # Table
            table_data = extract_table(element, doc)
            content_blocks.append({
                'type': 'table',
                'data': table_data
            })

    return {
        'content': '\n\n'.join([b['text'] for b in content_blocks if b['type'] == 'paragraph']),
        'blocks': content_blocks,
        'tables': len([b for b in content_blocks if b['type'] == 'table'])
    }
```

**Dependencies to add**:
```
# services/haystack/requirements.txt
python-docx>=1.1.0
```

### 1.3 Excel Processing (Priority: Critical)

**Current**: Not implemented at all

**Solution**: Use `fastexcel` (Rust-based, 10-100x faster than openpyxl)

```python
# services/haystack/app/extractors/excel_extractor.py
import fastexcel
from typing import List, Dict, Any

def extract_text_from_excel(file_path: str) -> dict:
    """
    Extract all sheets from Excel file using fastexcel (Rust/calamine).
    Handles large files with 30+ tabs efficiently.
    """
    reader = fastexcel.read_excel(file_path)
    sheet_names = reader.sheet_names

    all_content = []
    sheet_data = []

    for sheet_name in sheet_names:
        # Load sheet as Arrow table for zero-copy performance
        df = reader.load_sheet(sheet_name).to_polars()

        # Convert to text representation
        text_content = f"## Sheet: {sheet_name}\n\n"
        text_content += df.to_pandas().to_markdown(index=False)

        all_content.append(text_content)
        sheet_data.append({
            'name': sheet_name,
            'rows': len(df),
            'columns': df.columns,
            'preview': df.head(10).to_dicts()
        })

    return {
        'content': '\n\n---\n\n'.join(all_content),
        'sheets': sheet_data,
        'total_sheets': len(sheet_names),
        'total_rows': sum(s['rows'] for s in sheet_data)
    }

def extract_excel_tables(file_path: str) -> List[Dict[str, Any]]:
    """Extract named Excel Tables (not just sheets)"""
    reader = fastexcel.read_excel(file_path)
    tables = []

    for table_name in reader.table_names():
        table_df = reader.load_table(table_name).to_polars()
        tables.append({
            'name': table_name,
            'data': table_df.to_dicts(),
            'columns': table_df.columns
        })

    return tables
```

**Dependencies to add**:
```
# services/haystack/requirements.txt
fastexcel>=0.10.0
polars>=0.20.0
```

**Performance characteristics**:
- 30-tab spreadsheet: ~3-5 seconds (vs 30+ seconds with openpyxl)
- Memory: Minimal (Arrow zero-copy)
- Limitation: Read-only (no pivot table evaluation, just data extraction)

**For pivot tables**: Fall back to openpyxl in read-only mode:
```python
def extract_pivot_tables(file_path: str):
    """Fallback for pivot table data (slower but necessary)"""
    from openpyxl import load_workbook
    wb = load_workbook(file_path, read_only=True, data_only=True)
    # data_only=True gives calculated values, not formulas
```

### 1.4 Document Chunking (Priority: High)

**Current**: Zero chunking - entire document embedded as single vector

**Solution**: Implement semantic chunking with overlap

```ruby
# app/services/document_processing/chunker.rb
module DocumentProcessing
  class Chunker
    DEFAULT_CHUNK_SIZE = 512      # tokens
    DEFAULT_OVERLAP = 64          # tokens
    MAX_CHUNK_SIZE = 2048

    def initialize(chunk_size: DEFAULT_CHUNK_SIZE, overlap: DEFAULT_OVERLAP)
      @chunk_size = chunk_size
      @overlap = overlap
    end

    def chunk(document)
      content = document.content
      return [content] if content.length < @chunk_size * 4  # ~4 chars/token

      chunks = []

      # Split by semantic boundaries first
      sections = split_by_sections(content)

      sections.each do |section|
        if estimate_tokens(section) <= @chunk_size
          chunks << section
        else
          # Sliding window for large sections
          chunks.concat(sliding_window_chunk(section))
        end
      end

      chunks
    end

    private

    def split_by_sections(content)
      # Split on headers, double newlines, etc.
      content.split(/(?=^#{1,3}\s)|(?:\n\n)/).reject(&:blank?)
    end

    def sliding_window_chunk(text)
      words = text.split(/\s+/)
      chunks = []

      i = 0
      while i < words.length
        chunk_words = words[i, @chunk_size]
        chunks << chunk_words.join(' ')
        i += (@chunk_size - @overlap)
      end

      chunks
    end

    def estimate_tokens(text)
      text.length / 4  # Rough estimate
    end
  end
end
```

**Database changes needed**:
```ruby
# db/migrate/XXXXXX_create_document_chunks.rb
class CreateDocumentChunks < ActiveRecord::Migration[8.0]
  def change
    create_table :document_chunks do |t|
      t.references :document, null: false, foreign_key: true
      t.text :content, null: false
      t.integer :chunk_index, null: false
      t.integer :start_offset
      t.integer :end_offset
      t.string :section_title
      t.vector :embedding, limit: 1536

      t.timestamps
    end

    add_index :document_chunks, [:document_id, :chunk_index], unique: true
  end
end
```

---

## Phase 2: Search Provider Completion

**Goal**: All 9 providers functional, not just 7

### 2.1 Implement domain_aware Provider

**Current**: Declared in PROVIDERS hash, no case handler, falls to hybrid

**Solution**:

```ruby
# app/services/search_router.rb - Add case handler (around line 108)

when :domain_aware
  search_domain_aware(query, organization_id, options)

# Add implementation method
def search_domain_aware(query, organization_id, options)
  # Detect query domain
  domain_info = DomainConfidenceManager.determine_domains(query)
  primary_domain = domain_info[:primary_domain]
  confidence = domain_info[:confidence]

  # Get domain-specific embeddings if available
  domain_model = "#{primary_domain}_tuned"

  # Use domain-specific index if confidence > threshold
  if confidence > 0.7 && domain_index_exists?(organization_id, primary_domain)
    search_with_domain_index(query, organization_id, primary_domain, options)
  else
    # Fall back to hybrid with domain weighting
    options[:domain_boost] = primary_domain
    options[:domain_confidence] = confidence
    search_hybrid_new(query, organization_id, options)
  end
end

def search_with_domain_index(query, organization_id, domain, options)
  embedding = generate_embedding_cached(query, organization_id, domain: domain)

  results = VectorEmbedding
    .joins(:document)
    .where(documents: { organization_id: organization_id })
    .where(domain: domain)
    .where(status: 'active')
    .order(Arel.sql("embedding <=> '#{embedding}'"))
    .limit(options[:limit] || 10)

  format_results(results)
end
```

### 2.2 Implement confidence_aware Provider

**Current**: Declared, no implementation

**Solution**:

```ruby
# app/services/search_router.rb - Add case handler

when :confidence_aware
  search_confidence_aware(query, organization_id, options)

# Add implementation
def search_confidence_aware(query, organization_id, options)
  # Run multiple search strategies in parallel
  strategies = [:pgvector_cosine, :hybrid, :haystack]

  results_by_strategy = Concurrent::Hash.new

  threads = strategies.map do |strategy|
    Thread.new do
      results_by_strategy[strategy] = send("search_#{strategy}", query, organization_id, options.merge(limit: 20))
    end
  end
  threads.each(&:join)

  # Score and merge results using ConfidenceScorer
  scorer = ConfidenceScorer.new(query, organization_id)

  merged_results = {}
  results_by_strategy.each do |strategy, results|
    results.each do |result|
      doc_id = result[:document_id]

      if merged_results[doc_id]
        merged_results[doc_id][:sources] << strategy
        merged_results[doc_id][:scores] << result[:score]
      else
        merged_results[doc_id] = {
          document_id: doc_id,
          sources: [strategy],
          scores: [result[:score]],
          metadata: result[:metadata]
        }
      end
    end
  end

  # Calculate multi-factor confidence
  final_results = merged_results.values.map do |r|
    confidence = scorer.calculate_confidence(
      semantic_scores: r[:scores],
      source_agreement: r[:sources].length.to_f / strategies.length,
      query: query,
      document_id: r[:document_id]
    )

    r.merge(confidence: confidence, final_score: confidence * r[:scores].max)
  end

  final_results.sort_by { |r| -r[:final_score] }.first(options[:limit] || 10)
end
```

### 2.3 Add Provider Tests

**Current**: Zero tests for any search provider

**Solution**: Create comprehensive test suite

```ruby
# spec/services/search_router_spec.rb
RSpec.describe SearchRouter do
  let(:organization) { create(:organization) }
  let(:documents) { create_list(:document, 10, :with_embeddings, organization: organization) }
  let(:router) { described_class.new }

  describe '#route_query' do
    SearchRouter::PROVIDERS.keys.each do |provider|
      context "with #{provider} provider" do
        it 'returns results without error' do
          results = router.route_query(
            'test query',
            organization.id,
            provider: provider,
            limit: 5
          )

          expect(results).to be_an(Array)
          expect(results.length).to be <= 5
        end

        it 'returns results with required fields' do
          results = router.route_query('test', organization.id, provider: provider)

          results.each do |result|
            expect(result).to have_key(:document_id)
            expect(result).to have_key(:score)
          end
        end
      end
    end
  end

  describe '#determine_provider' do
    it 'selects distributed for large collections' do
      allow(router).to receive(:estimate_organization_size).and_return(600_000)

      provider = router.send(:determine_provider, organization.id, {})
      expect(provider).to eq(:distributed)
    end

    it 'selects hybrid_advanced for complex queries' do
      complex_query = 'find documents about machine learning AND neural networks OR deep learning'

      provider = router.send(:determine_provider, organization.id, query: complex_query)
      expect(provider).to eq(:hybrid_advanced)
    end
  end
end
```

---

## Phase 3: Distributed Architecture (100M+ Vectors)

**Goal**: Real distributed system capable of hundreds of millions of vectors

### 3.1 Replace Raft Stubs with Real Implementation

**Current**: All Raft methods are logging-only stubs

**Option A**: Use existing Raft library (Recommended for speed)

```ruby
# Gemfile
gem 'raft-rb', '~> 0.2'  # Or similar

# Alternative: Use etcd for distributed consensus
gem 'etcdv3', '~> 0.11'
```

**Option B**: Implement Raft properly (More control, more work)

```ruby
# app/services/distributed/consensus/raft_node.rb
module Distributed
  module Consensus
    class RaftNode
      FOLLOWER = 0
      CANDIDATE = 1
      LEADER = 2

      ELECTION_TIMEOUT_MIN = 150  # ms
      ELECTION_TIMEOUT_MAX = 300  # ms
      HEARTBEAT_INTERVAL = 50     # ms

      attr_reader :state, :current_term, :voted_for, :log, :commit_index

      def initialize(node_id:, peers:, storage:)
        @node_id = node_id
        @peers = peers
        @storage = storage  # RocksDB or similar
        @state = FOLLOWER
        @current_term = 0
        @voted_for = nil
        @log = []
        @commit_index = 0
        @last_applied = 0
        @next_index = {}
        @match_index = {}

        load_persistent_state
        start_election_timer
      end

      # AppendEntries RPC (leader → followers)
      def append_entries(term:, leader_id:, prev_log_index:, prev_log_term:, entries:, leader_commit:)
        return { term: @current_term, success: false } if term < @current_term

        reset_election_timer

        if term > @current_term
          @current_term = term
          @state = FOLLOWER
          @voted_for = nil
        end

        # Check log consistency
        if prev_log_index > 0
          return { term: @current_term, success: false } unless log_matches?(prev_log_index, prev_log_term)
        end

        # Append new entries
        entries.each_with_index do |entry, i|
          index = prev_log_index + 1 + i
          if @log[index] && @log[index][:term] != entry[:term]
            @log = @log[0...index]  # Delete conflicting entries
          end
          @log[index] = entry
        end

        # Update commit index
        if leader_commit > @commit_index
          @commit_index = [leader_commit, @log.length - 1].min
          apply_committed_entries
        end

        persist_state
        { term: @current_term, success: true }
      end

      # RequestVote RPC (candidate → all)
      def request_vote(term:, candidate_id:, last_log_index:, last_log_term:)
        return { term: @current_term, vote_granted: false } if term < @current_term

        if term > @current_term
          @current_term = term
          @state = FOLLOWER
          @voted_for = nil
        end

        vote_granted = false
        if (@voted_for.nil? || @voted_for == candidate_id) && log_up_to_date?(last_log_index, last_log_term)
          @voted_for = candidate_id
          vote_granted = true
          reset_election_timer
        end

        persist_state
        { term: @current_term, vote_granted: vote_granted }
      end

      # Client request handling
      def submit(command)
        return forward_to_leader(command) unless @state == LEADER

        entry = { term: @current_term, command: command }
        @log << entry

        replicate_to_followers

        # Wait for majority
        wait_for_commit(@log.length - 1)
      end

      private

      def start_election_timer
        @election_timer&.cancel
        timeout = rand(ELECTION_TIMEOUT_MIN..ELECTION_TIMEOUT_MAX)
        @election_timer = Concurrent::ScheduledTask.execute(timeout / 1000.0) { start_election }
      end

      def start_election
        @state = CANDIDATE
        @current_term += 1
        @voted_for = @node_id
        votes = 1

        @peers.each do |peer|
          response = peer.request_vote(
            term: @current_term,
            candidate_id: @node_id,
            last_log_index: @log.length - 1,
            last_log_term: @log.last&.dig(:term) || 0
          )

          if response[:term] > @current_term
            @current_term = response[:term]
            @state = FOLLOWER
            return
          end

          votes += 1 if response[:vote_granted]
        end

        become_leader if votes > (@peers.length + 1) / 2
      end

      def become_leader
        @state = LEADER
        @peers.each { |p| @next_index[p.id] = @log.length }
        @peers.each { |p| @match_index[p.id] = 0 }
        start_heartbeat
      end

      def persist_state
        @storage.put('current_term', @current_term)
        @storage.put('voted_for', @voted_for)
        @storage.put('log', @log.to_json)
      end

      def load_persistent_state
        @current_term = @storage.get('current_term')&.to_i || 0
        @voted_for = @storage.get('voted_for')
        @log = JSON.parse(@storage.get('log') || '[]', symbolize_names: true)
      end
    end
  end
end
```

### 3.2 Implement Real Remote Shard Queries

**Current**: Returns `[]` for any remote shard

**Solution**:

```ruby
# app/services/distributed/search/distributed_search_service.rb

def search_remote_shard(shard_id, query_vector, options)
  node = @cluster.node_for_shard(shard_id)

  # Use HTTP for cross-node communication
  response = Faraday.post("#{node.endpoint}/internal/search") do |req|
    req.headers['Content-Type'] = 'application/json'
    req.headers['X-Internal-Token'] = internal_auth_token
    req.body = {
      query_vector: query_vector,
      organization_id: options[:organization_id],
      limit: options[:limit],
      dimension: options[:dimension]
    }.to_json
    req.options.timeout = 5  # 5 second timeout
  end

  return [] unless response.success?

  JSON.parse(response.body, symbolize_names: true)[:results]
rescue Faraday::Error => e
  Rails.logger.error("Remote shard query failed: #{e.message}")
  # Try replica if available
  try_replica_shard(shard_id, query_vector, options)
end

def search_all_shards(query_vector, organization_id, options)
  shards = @sharding_manager.shards_for_organization(organization_id)

  # Fan-out: query all shards in parallel
  results = Concurrent::Array.new

  futures = shards.map do |shard_id|
    Concurrent::Future.execute do
      if shard_id == @node_id
        search_local_index(query_vector, options)
      else
        search_remote_shard(shard_id, query_vector, options)
      end
    end
  end

  # Collect and merge results
  futures.each do |future|
    shard_results = future.value(timeout: 10)
    results.concat(shard_results) if shard_results
  end

  # Sort by score and return top-k
  results.sort_by { |r| -r[:score] }.first(options[:limit] || 10)
end
```

### 3.3 Scale Architecture for 100M+ Vectors

**Sharding Strategy**:

```
100M vectors distribution:
├── Time-based sharding (monthly indexes)
│   ├── 2024-01/ (10M vectors)
│   ├── 2024-02/ (12M vectors)
│   └── ...
├── Organization sharding (large orgs get dedicated nodes)
│   ├── org_123 → node_1, node_2 (replicas)
│   ├── org_456 → node_3, node_4
│   └── ...
└── Hash-based sub-sharding within organization
    ├── hash(doc_id) % 10 → partition_0..9
    └── Each partition: ~1M vectors max
```

**Configuration for scale**:

```ruby
# config/distributed.yml
production:
  cluster:
    min_nodes: 3
    max_nodes: 100
    replication_factor: 3

  sharding:
    strategy: hybrid  # time + hash
    max_vectors_per_shard: 10_000_000
    auto_rebalance: true
    rebalance_threshold: 0.2  # 20% imbalance triggers rebalance

  vector_index:
    type: hnsw
    m: 16                    # Connections per layer
    ef_construction: 200     # Build-time accuracy
    ef_search: 50            # Query-time accuracy
    max_elements: 10_000_000

  memory:
    quota_per_node_gb: 64
    cache_size_gb: 16

  persistence:
    engine: rocksdb
    wal_enabled: true
    snapshot_interval: 3600  # hourly snapshots
```

### 3.4 Replace Mock HNSW with Real Implementation

**Option A**: Use pgvector's built-in HNSW (Simplest)

```sql
-- Create HNSW index on existing table
CREATE INDEX ON vector_embeddings
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Query uses index automatically
SELECT * FROM vector_embeddings
ORDER BY embedding <=> '[...]'
LIMIT 10;
```

**Option B**: Use hnswlib via Python (More control)

```python
# services/haystack/app/indexes/hnsw_index.py
import hnswlib
import numpy as np
from pathlib import Path

class HNSWIndex:
    def __init__(self, dim: int, max_elements: int = 10_000_000):
        self.dim = dim
        self.index = hnswlib.Index(space='cosine', dim=dim)
        self.index.init_index(
            max_elements=max_elements,
            ef_construction=200,
            M=16
        )
        self.index.set_ef(50)  # Query-time parameter
        self.id_map = {}  # Internal ID → Document ID

    def add(self, vectors: np.ndarray, ids: list[str]):
        internal_ids = np.arange(len(self.id_map), len(self.id_map) + len(ids))
        for internal_id, doc_id in zip(internal_ids, ids):
            self.id_map[internal_id] = doc_id
        self.index.add_items(vectors, internal_ids)

    def search(self, query_vector: np.ndarray, k: int = 10):
        internal_ids, distances = self.index.knn_query(query_vector, k=k)
        return [
            {'document_id': self.id_map[iid], 'distance': dist}
            for iid, dist in zip(internal_ids[0], distances[0])
        ]

    def save(self, path: str):
        self.index.save_index(path)
        # Save id_map separately

    def load(self, path: str):
        self.index.load_index(path)
        # Load id_map
```

---

## Phase 4: Production Hardening

### 4.1 Fix Mock Embedding Fallback

**Current**: Falls back to random vectors if Haystack unavailable

**Solution**: Fail fast, don't corrupt data

```ruby
# app/sidekiq/document_processing/embedding_generation_worker.rb

def generate_embedding(document, model, dim)
  embedding_vector = HaystackClient.generate_embeddings(
    document.content,
    model_name: model,
    dimension: dim
  )

  if embedding_vector.nil? || embedding_vector.empty?
    # DON'T fall back to random - that corrupts the index
    raise EmbeddingGenerationError, "Haystack service unavailable"
  end

  embedding_vector
rescue EmbeddingGenerationError => e
  # Retry with backoff, then fail the job
  document.update!(embedding_status: 'failed', embedding_error: e.message)
  raise  # Let Sidekiq retry
end
```

### 4.2 Add Circuit Breaker for External Services

```ruby
# app/services/circuit_breaker.rb
class CircuitBreaker
  FAILURE_THRESHOLD = 5
  RESET_TIMEOUT = 30  # seconds

  def initialize(name)
    @name = name
    @failures = 0
    @state = :closed
    @last_failure = nil
  end

  def call
    check_state

    raise CircuitOpenError, "Circuit #{@name} is open" if @state == :open

    begin
      result = yield
      reset
      result
    rescue => e
      record_failure
      raise
    end
  end

  private

  def record_failure
    @failures += 1
    @last_failure = Time.current
    @state = :open if @failures >= FAILURE_THRESHOLD
  end

  def check_state
    return unless @state == :open
    @state = :half_open if Time.current - @last_failure > RESET_TIMEOUT
  end

  def reset
    @failures = 0
    @state = :closed
  end
end
```

### 4.3 Implement Health Checks

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def check
    checks = {
      database: check_database,
      redis: check_redis,
      haystack: check_haystack,
      sidekiq: check_sidekiq,
      vector_index: check_vector_index
    }

    status = checks.values.all? { |c| c[:status] == 'ok' } ? :ok : :service_unavailable

    render json: { status: status, checks: checks }, status: status
  end

  private

  def check_database
    ActiveRecord::Base.connection.execute('SELECT 1')
    { status: 'ok', latency_ms: measure { ActiveRecord::Base.connection.execute('SELECT 1') } }
  rescue => e
    { status: 'error', error: e.message }
  end

  def check_haystack
    response = HaystackClient.health_check
    { status: response[:healthy] ? 'ok' : 'degraded', details: response }
  rescue => e
    { status: 'error', error: e.message }
  end
end
```

---

## Phase 5: Testing & Validation

### 5.1 Integration Test Suite

```ruby
# spec/integration/document_pipeline_spec.rb
RSpec.describe 'Document Processing Pipeline', type: :integration do
  let(:organization) { create(:organization) }

  describe 'PDF processing' do
    it 'extracts real text from PDF' do
      pdf_path = Rails.root.join('spec/fixtures/sample.pdf')
      document = create(:document, organization: organization)
      document.file.attach(io: File.open(pdf_path), filename: 'sample.pdf')

      DocumentProcessing::TextExtractionWorker.new.perform(document.id)
      document.reload

      expect(document.content).not_to include('Extracted text from PDF document')
      expect(document.content).to include('actual content from PDF')
    end
  end

  describe 'Excel processing' do
    it 'extracts all sheets from multi-tab Excel file' do
      xlsx_path = Rails.root.join('spec/fixtures/30_tabs.xlsx')
      document = create(:document, organization: organization)
      document.file.attach(io: File.open(xlsx_path), filename: '30_tabs.xlsx')

      DocumentProcessing::TextExtractionWorker.new.perform(document.id)
      document.reload

      expect(document.content).to include('Sheet: Tab1')
      expect(document.content).to include('Sheet: Tab30')
    end
  end
end
```

### 5.2 Load Testing for Scale

```ruby
# spec/load/vector_scale_spec.rb
RSpec.describe 'Vector Scale', type: :load do
  it 'handles 1M vectors per node' do
    # Generate test vectors
    vectors = Array.new(1_000_000) { Array.new(768) { rand } }

    start_time = Time.current

    vectors.each_slice(10_000) do |batch|
      # Bulk insert
      VectorEmbedding.insert_all(batch.map { |v| { embedding: v, ... } })
    end

    insert_time = Time.current - start_time
    expect(insert_time).to be < 300  # Under 5 minutes

    # Test query performance
    query_times = Array.new(100) do
      measure { SearchRouter.new.route_query('test', org.id, limit: 10) }
    end

    expect(query_times.sum / 100).to be < 0.05  # Under 50ms average
  end
end
```

---

## Implementation Priority Order

### Week 1-2: Document Processing
1. [ ] Add PDF extraction with pdfplumber
2. [ ] Add DOCX extraction with python-docx
3. [ ] Add Excel extraction with fastexcel
4. [ ] Implement document chunking
5. [ ] Update TextExtractionWorker to call new extractors

### Week 3-4: Search Providers
1. [ ] Implement domain_aware provider
2. [ ] Implement confidence_aware provider
3. [ ] Add comprehensive provider tests
4. [ ] Fix mock embedding fallback (fail instead of random)

### Week 5-8: Distributed Foundation
1. [ ] Implement real Raft consensus (or integrate etcd)
2. [ ] Implement remote shard queries
3. [ ] Add cross-node communication layer
4. [ ] Test 3-node cluster scenarios

### Week 9-12: Scale & Hardening
1. [ ] Replace mock HNSW with hnswlib or pgvector HNSW
2. [ ] Implement time-based + hash-based sharding
3. [ ] Add circuit breakers and health checks
4. [ ] Load test to 10M, 50M, 100M vectors

---

## Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Document types supported | 3 (txt, md, rtf) | 6 (+ pdf, docx, xlsx) |
| Search providers working | 7/9 | 9/9 |
| Max vectors | 5M | 100M+ |
| Query latency (p99) | Unknown | <100ms |
| Embedding reliability | ~70% (falls to mock) | 99.9% |
| Test coverage | ~5% | >80% |
| Distributed consensus | 0% | 100% |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Haystack service downtime | Circuit breaker + retry queue + health checks |
| Large file memory issues | Streaming extraction + chunking |
| Raft implementation complexity | Consider etcd as managed alternative |
| Excel pivot tables | Fallback to openpyxl read-only mode |
| Migration of existing data | Backfill workers with progress tracking |

---

## Appendix: File Locations for Key Changes

```
Document Processing:
├── app/sidekiq/document_processing/text_extraction_worker.rb (lines 138-159)
├── services/haystack/app/extractors/ (NEW)
│   ├── pdf_extractor.py
│   ├── docx_extractor.py
│   └── excel_extractor.py
└── services/haystack/requirements.txt (add dependencies)

Search Providers:
├── app/services/search_router.rb (lines 95-112, add cases)
└── spec/services/search_router_spec.rb (NEW)

Distributed:
├── app/services/distributed/consensus/raft_adapter.rb (REWRITE)
├── app/services/distributed/search/distributed_search_service.rb (lines 170-173)
└── app/services/distributed/sharding/sharding_manager.rb

Vector Index:
├── app/services/wasm/hnsw_index_store.rb (REWRITE)
└── services/haystack/app/indexes/hnsw_index.py (NEW)
```
