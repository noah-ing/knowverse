# Knowverse Next-Generation Architecture

## Overview

This document describes the production-grade architecture for Knowverse, designed to handle **billions of vectors** across a **distributed cluster** with **real-time consensus** and **enterprise-grade reliability**.

## Architecture Principles

1. **Native Distributed Consensus** - Raft-based coordination
2. **Hierarchical Sharding** - 10M vectors per shard, 3-way replication
3. **Tiered Storage** - Hot (memory) → Warm (SSD) → Cold (archive)
4. **WASM Sandboxing** - Isolated document processing
5. **Zero-Trust Security** - Capability-based access control

---

## Core Components

### 1. Vector Storage Layer

```
┌─────────────────────────────────────────────────────────────────┐
│                     Vector Storage Architecture                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │   Qdrant    │  │   Qdrant    │  │   Qdrant    │             │
│  │   Node 1    │  │   Node 2    │  │   Node 3    │             │
│  │  (Leader)   │  │ (Follower)  │  │ (Follower)  │             │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘             │
│         │                │                │                      │
│         └────────────────┼────────────────┘                      │
│                          │                                        │
│                    ┌─────▼─────┐                                 │
│                    │   Raft    │                                 │
│                    │ Consensus │                                 │
│                    └───────────┘                                 │
│                                                                   │
│  Sharding Strategy:                                              │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐              │
│  │ Shard 0 │ │ Shard 1 │ │ Shard 2 │ │ Shard N │              │
│  │  10M    │ │  10M    │ │  10M    │ │  10M    │              │
│  │ vectors │ │ vectors │ │ vectors │ │ vectors │              │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘              │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

**Key Features:**
- **Qdrant Cluster** with native Raft consensus (no custom implementation needed)
- **HNSW Indexing** with M=16, ef_construction=200
- **3-Way Replication** for fault tolerance
- **Write Consistency Factor** = majority (n/2 + 1)

### 2. Document Processing Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                   WASM Component Model Pipeline                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    WASM Runtime (Wasmtime)                │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ │   │
│  │  │   PDF    │  │   DOCX   │  │  Excel   │  │   OCR    │ │   │
│  │  │Component │  │Component │  │Component │  │Component │ │   │
│  │  │ (Rust)  │  │ (Rust)  │  │ (Rust)  │  │ (Rust)  │ │   │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘ │   │
│  │       │             │             │             │        │   │
│  │       └─────────────┼─────────────┼─────────────┘        │   │
│  │                     │             │                       │   │
│  │               ┌─────▼─────────────▼─────┐                │   │
│  │               │    Capability Broker     │                │   │
│  │               │  (Read/Write/Network)    │                │   │
│  │               └──────────────────────────┘                │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
│  Security Guarantees:                                            │
│  • Memory isolation per component                                │
│  • No filesystem access (capability denied by default)           │
│  • CPU time limits (30s max)                                     │
│  • Memory limits (512MB per instance)                            │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

**Component Interface (WIT):**
```wit
package knowverse:extraction@1.0.0;

interface extractor {
  record extraction-result {
    content: string,
    metadata: list<tuple<string, string>>,
    chunks: list<text-chunk>,
    tables: list<table-data>,
    success: bool,
    error: option<string>
  }

  extract: func(data: list<u8>, options: extraction-options) -> extraction-result;
}
```

### 3. Distributed Consensus (Raft)

```
┌─────────────────────────────────────────────────────────────────┐
│                      Raft Consensus Flow                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Client Request                                                  │
│       │                                                          │
│       ▼                                                          │
│  ┌─────────┐                                                     │
│  │ Leader  │ ────────────────────────────────────────────────   │
│  │ Node    │                                                  │  │
│  └────┬────┘                                                  │  │
│       │                                                       │  │
│       │ 1. Append to local log                               │  │
│       │ 2. Send AppendEntries RPC                            │  │
│       │                                                       │  │
│       ├──────────────────┬──────────────────┐                │  │
│       │                  │                  │                │  │
│       ▼                  ▼                  ▼                │  │
│  ┌─────────┐       ┌─────────┐       ┌─────────┐            │  │
│  │Follower │       │Follower │       │Follower │            │  │
│  │   1     │       │   2     │       │   3     │            │  │
│  └────┬────┘       └────┬────┘       └────┬────┘            │  │
│       │                  │                  │                │  │
│       │ 3. Acknowledge   │                  │                │  │
│       └──────────────────┴──────────────────┘                │  │
│                          │                                    │  │
│                          ▼                                    │  │
│                 4. Majority ACK received                      │  │
│                 5. Commit entry                               │  │
│                 6. Apply to state machine                     │  │
│                 7. Respond to client                          │  │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

**Implementation Files:**
- `app/services/distributed/consensus/raft_node.rb` - State machine
- `app/services/distributed/consensus/raft_rpc.rb` - HTTP transport
- `app/services/distributed/consensus/raft_storage.rb` - WAL persistence

### 4. Tiered Storage Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Tiered Storage System                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ HOT TIER (Memory)                                            ││
│  │ • 50 active partitions                                       ││
│  │ • LRU eviction                                               ││
│  │ • < 1ms latency                                              ││
│  │ • 100K vectors per partition                                 ││
│  └─────────────────────────────────────────────────────────────┘│
│                          │                                        │
│                          │ 5 min inactivity                       │
│                          ▼                                        │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ WARM TIER (SSD)                                              ││
│  │ • Unlimited partitions                                       ││
│  │ • On-demand loading                                          ││
│  │ • < 10ms latency                                             ││
│  │ • JSON serialization (Oj)                                    ││
│  └─────────────────────────────────────────────────────────────┘│
│                          │                                        │
│                          │ 1 hour inactivity                      │
│                          ▼                                        │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ COLD TIER (Archive)                                          ││
│  │ • Gzip compressed                                            ││
│  │ • S3/GCS compatible                                          ││
│  │ • 100ms+ latency                                             ││
│  │ • Long-term retention                                        ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 5. Rate Limiting & Backpressure

```
┌─────────────────────────────────────────────────────────────────┐
│                  Rate Limiting Architecture                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Incoming Request                                                │
│       │                                                          │
│       ▼                                                          │
│  ┌─────────────────┐                                             │
│  │ Backpressure    │ ──► 503 Service Overloaded                 │
│  │ Check           │     (if queue > 500 or CPU > 90%)          │
│  └────────┬────────┘                                             │
│           │                                                      │
│           ▼                                                      │
│  ┌─────────────────┐                                             │
│  │ Token Bucket    │ ──► 429 Rate Limited                       │
│  │ Rate Limiter    │     (Retry-After: 60s)                     │
│  └────────┬────────┘                                             │
│           │                                                      │
│           ▼                                                      │
│  ┌─────────────────┐                                             │
│  │ Concurrency     │ ──► 503 Too Many Concurrent                │
│  │ Limiter (50)    │     (Retry-After: 5s)                      │
│  └────────┬────────┘                                             │
│           │                                                      │
│           ▼                                                      │
│  ┌─────────────────┐                                             │
│  │ Circuit Breaker │ ──► Failover / Shed Load                   │
│  │ (per service)   │                                             │
│  └────────┬────────┘                                             │
│           │                                                      │
│           ▼                                                      │
│     Process Request                                              │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Scale Targets

| Metric | Target | Architecture Support |
|--------|--------|---------------------|
| Total Vectors | 1 billion+ | Hierarchical sharding (10K partitions × 100K) |
| Queries/Second | 10,000+ | Parallel shard queries, connection pooling |
| Insert Throughput | 50,000/sec | Batch upserts (128 per batch) |
| P99 Latency | < 100ms | Hot tier + HNSW + SSD indices |
| Availability | 99.99% | 3-way replication, automatic failover |
| Recovery Time | < 5 seconds | Raft leader election timeout |

---

## Production Deployment

### Recommended Cluster Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                     Production Cluster                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Load Balancer (HAProxy / ALB)                                ││
│  │ • Health check: /health                                      ││
│  │ • Sticky sessions: organization_id                          ││
│  └─────────────────────────────────────────────────────────────┘│
│                          │                                        │
│         ┌────────────────┼────────────────┐                      │
│         ▼                ▼                ▼                      │
│  ┌───────────┐    ┌───────────┐    ┌───────────┐               │
│  │ App Node  │    │ App Node  │    │ App Node  │               │
│  │ + Sidekiq │    │ + Sidekiq │    │ + Sidekiq │               │
│  └─────┬─────┘    └─────┬─────┘    └─────┬─────┘               │
│        │                │                │                       │
│        └────────────────┼────────────────┘                       │
│                         │                                         │
│  ┌──────────────────────┼──────────────────────┐                │
│  │                      ▼                       │                │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐     │                │
│  │  │ Qdrant  │  │ Qdrant  │  │ Qdrant  │     │  Vector        │
│  │  │ Node 1  │  │ Node 2  │  │ Node 3  │     │  Cluster       │
│  │  └─────────┘  └─────────┘  └─────────┘     │                │
│  └─────────────────────────────────────────────┘                │
│                                                                   │
│  ┌─────────────────────────────────────────────┐                │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐     │                │
│  │  │Postgres │  │Postgres │  │Postgres │     │  Metadata      │
│  │  │ Primary │  │ Standby │  │ Standby │     │  Cluster       │
│  │  └─────────┘  └─────────┘  └─────────┘     │                │
│  └─────────────────────────────────────────────┘                │
│                                                                   │
│  ┌─────────────────────────────────────────────┐                │
│  │  Redis Cluster (6 nodes)                    │  Cache/Queue   │
│  └─────────────────────────────────────────────┘                │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Environment Variables

```bash
# Qdrant Cluster
QDRANT_CLUSTER_URLS=http://qdrant-1:6333,http://qdrant-2:6333,http://qdrant-3:6333
QDRANT_API_KEY=your-secure-api-key

# Distributed Consensus
DISTRIBUTED_NODE_ID=node-1:10.0.0.1:7100
DISTRIBUTED_CLUSTER_NODES=node-2:10.0.0.2:7100,node-3:10.0.0.3:7100

# Rate Limiting
RATE_LIMIT_API_PER_MINUTE=1000
RATE_LIMIT_MAX_CONCURRENT=50

# Monitoring
PROMETHEUS_PUSH_GATEWAY=http://prometheus-push:9091
JAEGER_AGENT_HOST=jaeger-agent
```

---

## Observability

### Prometheus Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `knowverse_http_requests_total` | Counter | Total HTTP requests |
| `knowverse_search_duration_seconds` | Histogram | Search latency |
| `knowverse_vectors_total` | Gauge | Total vectors in index |
| `knowverse_raft_term` | Gauge | Current Raft term |
| `knowverse_backpressure_active` | Gauge | Backpressure mode |

### Grafana Dashboard

```json
{
  "title": "Knowverse Operations",
  "panels": [
    {"title": "QPS", "expr": "rate(knowverse_http_requests_total[5m])"},
    {"title": "P99 Latency", "expr": "histogram_quantile(0.99, knowverse_search_duration_seconds_bucket)"},
    {"title": "Vector Count", "expr": "sum(knowverse_vectors_total)"},
    {"title": "Raft Health", "expr": "knowverse_raft_state == 2"}
  ]
}
```

### Alerting Rules

```yaml
groups:
  - name: knowverse
    rules:
      - alert: HighLatency
        expr: histogram_quantile(0.99, knowverse_search_duration_seconds_bucket) > 0.5
        for: 5m
        labels:
          severity: warning

      - alert: RaftLeaderLost
        expr: sum(knowverse_raft_state == 2) == 0
        for: 30s
        labels:
          severity: critical

      - alert: BackpressureActive
        expr: knowverse_backpressure_active == 1
        for: 1m
        labels:
          severity: warning
```

---

## Migration Path

### From Current State to Production

1. **Phase 1: Qdrant Migration** (Week 1-2)
   - Deploy Qdrant cluster alongside existing pgvector
   - Dual-write to both systems
   - Verify consistency

2. **Phase 2: Traffic Migration** (Week 3-4)
   - Shadow reads from Qdrant
   - Compare results with pgvector
   - Gradually shift read traffic

3. **Phase 3: Cutover** (Week 5)
   - Full traffic to Qdrant
   - Deprecate custom Raft (use Qdrant's native)
   - Enable full tiered storage

---

## Files Reference

| Component | File |
|-----------|------|
| Qdrant Adapter | `app/services/vector_store/qdrant_cluster_adapter.rb` |
| WASM Sandbox | `app/services/wasm/component_sandbox.rb` |
| Scalable Index | `app/services/wasm/scalable_index_manager.rb` |
| Rate Limiter | `app/services/infrastructure/rate_limiter.rb` |
| Metrics | `app/services/infrastructure/metrics_exporter.rb` |
| Raft Node | `app/services/distributed/consensus/raft_node.rb` |
| Raft RPC | `app/services/distributed/consensus/raft_rpc.rb` |
| Raft Storage | `app/services/distributed/consensus/raft_storage.rb` |
| Health Monitor | `app/services/distributed/monitoring/cluster_health_monitor.rb` |
| Remote Shard | `app/services/distributed/search/remote_shard_client.rb` |

---

*Architecture Version: 2.0*
*Last Updated: December 2025*
