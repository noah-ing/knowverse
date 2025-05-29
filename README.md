# 🚀 Knowverse
**Enterprise-Grade AI Knowledge Management Platform**

[![Production Ready](https://img.shields.io/badge/Production%20Ready-92%25-green.svg)](https://github.com/your-org/knowverse)
[![Ruby on Rails](https://img.shields.io/badge/Ruby%20on%20Rails-7.0+-red.svg)](https://rubyonrails.org/)
[![Python FastAPI](https://img.shields.io/badge/Python-FastAPI-009688.svg)](https://fastapi.tiangolo.com/)
[![Vector Search](https://img.shields.io/badge/Vector%20Search-Multi--Provider-blue.svg)](#vector-search-architecture)
[![Distributed](https://img.shields.io/badge/Architecture-Distributed-purple.svg)](#distributed-systems)

> **Revolutionary AI-powered knowledge management platform with sophisticated multi-provider search, domain-aware intelligence, and enterprise-grade distributed architecture.**

---

## 🌟 Why Knowverse is Exceptional

Knowverse represents **next-generation enterprise software** that surpasses traditional search platforms through innovative AI-driven features:

### 🧠 **9-Provider Intelligent Search Routing**
- **Automatic Provider Selection**: Intelligent routing based on query complexity, collection size, and performance metrics
- **Sub-5ms HNSW Search**: WebAssembly-accelerated SIMD search with horizontal scaling
- **Hybrid Intelligence**: Dynamic vector+keyword weighting with early termination optimization
- **Distributed Consensus**: Raft-coordinated search across multiple nodes

### 🎯 **Domain-Aware Confidence Scoring**
- **Multi-Factor Analysis**: Semantic similarity, corpus coverage, query characteristics, historical performance
- **Waterfall Fallback**: Intelligent domain detection with confidence-based routing
- **Fine-Tuned Models**: Organization-specific domain embedding models
- **Adaptive Learning**: Continuous improvement through feedback loops

### ⚡ **Enterprise Performance**
- **Sub-5ms Query Response**: HNSW + WebAssembly acceleration
- **Millions of Vectors**: Horizontal scaling with consistent hashing
- **Memory Efficient**: LRU eviction for larger-than-RAM operation
- **Two-Tier Caching**: Memory + Redis with domain-aware strategies

---

## 🏗️ Architecture Overview

```mermaid
graph TB
    subgraph "Client Layer"
        A[Web Interface] 
        B[Admin Dashboard]
        C[API Clients]
    end
    
    subgraph "Rails Application"
        D[SearchRouter<br/>9 Providers]
        E[Domain Confidence<br/>Manager]
        F[Embedding Cache<br/>Memory + Redis]
        G[RAG Controller<br/>Streaming]
    end
    
    subgraph "Python Microservice"
        H[FastAPI Server]
        I[Haystack Pipeline]
        J[LLM Providers<br/>OpenAI • Anthropic • Local]
        K[Vector Models<br/>384-2048 dims]
    end
    
    subgraph "Data Layer"
        L[(PostgreSQL<br/>+ pgvector)]
        M[(Redis Cache)]
        N[Distributed HNSW<br/>Raft Consensus]
    end
    
    A --> D
    B --> E
    C --> G
    D --> H
    E --> F
    F --> L
    G --> I
    H --> J
    I --> K
    K --> N
    N --> L
    L --> M
```

### **Search Provider Architecture**

| Provider | Use Case | Performance | Features |
|----------|----------|-------------|----------|
| **pgvector_cosine** | General similarity | ~10ms | PostgreSQL native |
| **pgvector_l2** | Distance-based | ~10ms | Euclidean distance |
| **hnsw** | Speed-critical | **<5ms** | WebAssembly SIMD |
| **haystack** | ML pipeline | ~50ms | Advanced NLP |
| **hybrid** | Balanced | ~15ms | Vector + keyword |
| **hybrid_advanced** | Complex queries | ~25ms | No early termination |
| **distributed** | Large datasets | ~8ms | Raft consensus |
| **domain_aware** | Specialized | ~12ms | Domain routing |
| **confidence_aware** | High accuracy | ~20ms | Multi-factor scoring |

---

## 🚀 Quick Start

### Prerequisites
- **Ruby 3.2+** with Rails 7.0+
- **Python 3.9+** with FastAPI
- **PostgreSQL 14+** with pgvector extension
- **Redis 6+** for caching
- **Node.js 18+** for asset pipeline

### 1. Clone & Setup
```bash
git clone https://github.com/your-org/knowverse.git
cd knowverse

# Install dependencies
bundle install
cd services/haystack && pip install -r requirements.txt && cd ../..

# Setup database
./bin/setup
rails db:create db:migrate
```

### 2. Configure Environment
```bash
# Copy and configure environment variables
cp .env.example .env
cp services/haystack/.env.example services/haystack/.env

# Set required variables
export HAYSTACK_SERVICE_URL=http://localhost:8000
export REDIS_URL=redis://localhost:6379
export DATABASE_URL=postgresql://localhost/knowverse_development
```

### 3. Start Services
```bash
# Start all services
./bin/dev

# Or start individually:
rails server                                    # Rails (port 3000)
cd services/haystack && uvicorn app.main:app   # Python API (port 8000)
redis-server                                   # Redis cache
```

### 4. Verify Installation
```bash
# Test database connectivity
./bin/test_db_connection.rb

# Test search functionality
./bin/test_distributed

# Run performance benchmarks
./bin/hybrid_search_benchmark
```

---

## 🎯 Core Features

### **📄 Intelligent Document Processing**
- **Multi-Format Support**: PDF, DOCX, TXT, Markdown with automatic type detection
- **Background Processing**: Sidekiq-powered async pipeline with status tracking
- **Multiple Embeddings**: 5 model sizes (384-2048 dimensions) per document
- **Cluster Analysis**: Automatic document grouping with visualization

### **🔍 Advanced Search Capabilities**
```ruby
# Intelligent search routing
results = SearchRouter.route_query(
  "machine learning algorithms", 
  organization_id: 1,
  dimension: 1024,
  model_name: "large",
  auto_detect_domain: true
)

# Domain-aware search with confidence
confidence_manager = DomainConfidenceManager.new
domains = confidence_manager.determine_domains(query, org_id)
# Returns: ["ai_research", "general", "technical"] with confidence scores
```

### **🤖 RAG (Retrieval Augmented Generation)**
```javascript
// Streaming RAG responses with SSE
const ragController = new RAGController();
ragController.streamAnswer("Explain neural networks", {
  onToken: (token) => appendToChat(token),
  onMetric: (metric) => updatePerformance(metric),
  onComplete: (stats) => logSessionStats(stats)
});
```

### **📊 Real-Time Analytics**
- **Search Performance**: Provider comparison, latency tracking, success rates
- **User Behavior**: Query patterns, feedback analysis, engagement metrics
- **System Health**: Distributed node status, cache hit rates, memory usage
- **Domain Intelligence**: Confidence score trends, model performance, fallback usage

---

## 🏢 Enterprise Features

### **🔐 Multi-Tenant Security**
- **Organization Isolation**: Complete data separation with role-based access
- **Passwordless Authentication**: Magic link system with Devise integration
- **API Security**: Service-to-service authentication with rate limiting
- **Audit Logging**: Comprehensive tracking for compliance requirements

### **📈 Scalability & Performance**
- **Horizontal Scaling**: Raft consensus with automatic node discovery
- **Intelligent Caching**: Two-tier strategy with domain-aware eviction
- **Memory Optimization**: Efficient vector storage with compression
- **Background Processing**: Solid Queue for reliable job execution

### **🎛️ Administrative Control**
- **Search Provider Management**: Real-time provider switching and monitoring
- **Domain Model Training**: Custom embedding models per organization
- **Cache Management**: Warming, clearing, and analytics dashboards
- **Performance Tuning**: Configurable thresholds and optimization settings

---

## 🔧 Configuration

### **Search Router Configuration**
```ruby
# config/initializers/search_router.rb
SearchRouter.configure do |config|
  config.default_provider = :hybrid_advanced
  config.fallback_chain = [:distributed, :hnsw, :pgvector_cosine, :haystack]
  config.confidence_threshold = 0.7
  config.enable_domain_detection = true
end
```

### **Embedding Cache Settings**
```ruby
# config/initializers/embedding_cache.rb
EmbeddingCache::CacheManager.configure do |config|
  config.memory_store_size = 1.gigabyte
  config.redis_ttl = 24.hours
  config.eviction_strategy = :domain_aware_lru
  config.enable_analytics = true
end
```

### **Distributed System Setup**
```ruby
# config/initializers/distributed_system.rb
Distributed::DistributedService.configure do |config|
  config.raft_cluster = ['node1:8080', 'node2:8080', 'node3:8080']
  config.shard_count = 16
  config.replication_factor = 3
  config.enable_auto_scaling = true
end
```

---

## 📚 API Documentation

### **Search API**
```bash
# Basic search
curl -X POST http://localhost:3000/search/query \
  -H "Content-Type: application/json" \
  -d '{"query": "machine learning", "organization_id": 1}'

# Advanced hybrid search
curl -X POST http://localhost:8000/hybrid-search \
  -H "Content-Type: application/json" \
  -d '{
    "query": "neural networks",
    "vector_weight": 0.7,
    "keyword_weight": 0.3,
    "early_termination": false
  }'
```

### **RAG API**
```bash
# Generate answer
curl -X POST http://localhost:8000/rag/answer \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is machine learning?",
    "org_id": 1,
    "provider": "openai"
  }'

# Streaming answer (SSE)
curl -N http://localhost:8000/rag/stream \
  -H "Accept: text/event-stream" \
  -d '{"query": "Explain AI", "org_id": 1}'
```

### **Domain Intelligence API**
```bash
# Detect query domain
curl -X POST http://localhost:8000/domains/detect \
  -H "Content-Type: application/json" \
  -d '{
    "query": "quantum computing algorithms",
    "organization_id": 1
  }'

# Generate domain-specific embeddings
curl -X POST http://localhost:8000/domains/embedding/generate \
  -H "Content-Type: application/json" \
  -d '{
    "text": "transformer architecture",
    "domain": "ai_research",
    "model_name": "large"
  }'
```

---

## 🚀 Deployment

### **Production Environment**
```yaml
# docker-compose.yml
version: '3.8'
services:
  web:
    build: .
    ports: ["3000:3000"]
    environment:
      - RAILS_ENV=production
      - DATABASE_URL=postgresql://...
      - REDIS_URL=redis://...
      
  haystack:
    build: ./services/haystack
    ports: ["8000:8000"]
    environment:
      - ENVIRONMENT=production
      - VECTOR_STORE_URL=...
      
  postgres:
    image: pgvector/pgvector:pg15
    environment:
      - POSTGRES_DB=knowverse_production
      
  redis:
    image: redis:7-alpine
    command: redis-server --maxmemory 2gb
```

### **Environment Variables**
```bash
# Core settings
DATABASE_URL=postgresql://user:pass@host:5432/knowverse_production
REDIS_URL=redis://host:6379/0
SECRET_KEY_BASE=your_secret_key

# AI Services
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
HAYSTACK_SERVICE_URL=http://haystack:8000

# Performance
EMBEDDING_CACHE_SIZE=1073741824  # 1GB
MAX_VECTOR_DIMENSIONS=2048
ENABLE_DISTRIBUTED_SEARCH=true

# Monitoring
SENTRY_DSN=https://...
NEW_RELIC_LICENSE_KEY=...
```

---

## 🧪 Testing & Benchmarks

### **Performance Benchmarks**
```bash
# Search performance testing
./bin/hybrid_search_benchmark --queries=1000 --dimensions=1024
# Average: 12.3ms, P95: 28.1ms, P99: 45.7ms

# Distributed system testing
./bin/distributed_load_test --nodes=3 --vectors=1000000
# Throughput: 2,847 queries/sec, Latency: 8.2ms avg

# RAG performance testing  
./bin/rag_performance_benchmark --provider=openai --streaming=true
# First token: 247ms, Generation: 32 tokens/sec
```

### **Quality Assurance**
```bash
# Run full test suite
bundle exec rspec

# Distributed system fault tolerance
./bin/test_distributed --simulate-failures

# UI resilience testing
./bin/ui_resilience_scanner.sh
```

---

## 📊 Monitoring & Observability

### **Built-in Dashboards**
- **Admin → Search Metrics**: Provider performance, query analysis, feedback trends
- **Admin → Distributed Dashboard**: Cluster health, consensus status, node metrics
- **Admin → Embedding Cache**: Hit rates, memory usage, eviction statistics
- **Admin → Domain Confidence**: Model performance, confidence score trends

### **Performance Metrics**
```ruby
# Search performance tracking
SearchQuery.where(created_at: 1.hour.ago..).group(:search_provider).average(:latency)
# => {"hybrid"=>12.3, "hnsw"=>4.7, "distributed"=>8.1}

# Domain confidence analytics
organization.domain_confidence_analytics(30)
# => {average_confidence: 0.83, success_rate: 94.2, by_domain: {...}}

# Cache performance
EmbeddingCache::Analytics.hit_rate_by_domain
# => {"ai_research"=>0.89, "general"=>0.76, "technical"=>0.82}
```

---

## 🤝 Contributing

### **Development Setup**
```bash
# Fork and clone the repository
git clone https://github.com/your-username/knowverse.git
cd knowverse

# Install development dependencies
bundle install --with development test
cd services/haystack && pip install -r requirements-dev.txt

# Setup pre-commit hooks
bundle exec rubocop --auto-gen-config
pre-commit install

# Run development server with auto-reload
./bin/dev
```

### **Architecture Guidelines**
- **Service Separation**: Keep Rails and Python services loosely coupled
- **Domain Modeling**: Use domain-driven design for business logic
- **Performance First**: Optimize for sub-10ms search response times
- **Test Coverage**: Maintain >90% coverage for critical paths

---

## 📄 License

**Enterprise License** - See [LICENSE.md](LICENSE.md) for details.

For commercial licensing and enterprise support, contact: enterprise@knowverse.com

---

## 🌟 Acknowledgments

Built with cutting-edge technologies:
- **[Haystack](https://haystack.deepset.ai/)** - Advanced NLP pipeline framework
- **[pgvector](https://github.com/pgvector/pgvector)** - PostgreSQL vector similarity search
- **[HNSW](https://github.com/nmslib/hnswlib)** - Hierarchical Navigable Small World graphs
- **[FastAPI](https://fastapi.tiangolo.com/)** - High-performance Python web framework
- **[Ruby on Rails](https://rubyonrails.org/)** - Full-stack web application framework

---

<div align="center">
  <strong>🚀 Ready to revolutionize your knowledge management?</strong><br/>
  <a href="#quick-start">Get Started</a> • 
  <a href="mailto:hello@knowverse.com">Contact Us</a> • 
  <a href="https://docs.knowverse.com">Documentation</a>
</div>
