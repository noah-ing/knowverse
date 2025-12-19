# Knowverse

Enterprise AI knowledge management platform with vector search and RAG capabilities.

## Overview

Knowverse is a multi-tenant document intelligence platform that combines semantic search with retrieval-augmented generation (RAG). Users can upload documents, search across their organization's knowledge base using natural language, and get AI-powered answers grounded in their actual data.

The platform supports OpenAI GPT-4o and Anthropic Claude for generation, with streaming responses for real-time interaction.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                Rails 8 (Web UI, Auth, Admin, API)               │
│                          Port 3000                              │
└──────────────────────────────┬──────────────────────────────────┘
                               │
       ┌───────────────────────┼───────────────────────┐
       │                       │                       │
       ▼                       ▼                       ▼
┌─────────────┐  ┌───────────────────────┐  ┌─────────────────┐
│ PostgreSQL  │  │        Qdrant         │  │    Haystack     │
│ (Metadata)  │  │   (Vector Search)     │  │    (Python)     │
│ Port 5432   │  │     Port 6333         │  │   Port 8000     │
└─────────────┘  └───────────────────────┘  └─────────────────┘
                                                     │
                          ┌──────────────────────────┤
                          │                          │
                          ▼                          ▼
               ┌─────────────────────┐   ┌─────────────────────┐
               │   Rust Embedding    │   │   Rust DocProc      │
               │   (ONNX Runtime)    │   │   (WASM Sandbox)    │
               │   Port 8001         │   │   Port 8002         │
               └─────────────────────┘   └─────────────────────┘
```

### Components

| Component | Purpose |
|-----------|---------|
| **Rails 8** | Web application, REST API, authentication (Devise), multi-tenancy, background jobs (SolidQueue) |
| **PostgreSQL** | Primary database with pgvector extension for hybrid search |
| **Qdrant** | High-performance vector database with HNSW indexing |
| **Haystack** | Python/FastAPI service handling embeddings, document extraction, and RAG orchestration |
| **Rust Services** | Optional high-performance ONNX embedding (10-50x faster) and WASM-sandboxed document parsing |
| **Redis** | Two-tier caching (memory + Redis) and session storage |

## Current Status

| Feature | Status | Details |
|---------|--------|---------|
| Core API | ✅ Complete | Multi-tenant REST API with Devise authentication |
| Vector Search | ✅ Complete | Qdrant integration with 768-dimensional embeddings |
| Hybrid Search | ✅ Complete | Combines semantic and keyword search using RRF fusion |
| **RAG Pipeline** | ✅ **Working** | Full pipeline with OpenAI GPT-4o and Anthropic Claude |
| Document Processing | ✅ Complete | PDF, DOCX, and Excel extraction with table support |
| Embeddings | ✅ Complete | SentenceTransformers (all-mpnet-base-v2) with optional Rust acceleration |
| Test Suite | ✅ Complete | RSpec, pytest, and Rust tests with CI/CD |
| Frontend | ⚠️ Stale | Needs review and updates |
| Production Hardening | 🔲 Not Started | Load testing, monitoring, alerting |

## Getting Started

### Prerequisites

- Ruby 3.2.2+
- Python 3.11+
- PostgreSQL 14+ with pgvector
- Redis 7+
- Docker (recommended)

### Quick Start with Docker

Start all services with a single command:

```bash
docker compose up -d
```

For the optional high-performance Rust services:

```bash
docker compose --profile rust up -d
```

### Local Development (macOS)

Install Ruby via rbenv, set up the database, and start the Rails server. The Haystack Python service runs separately via uvicorn, and Qdrant runs in Docker.

See the architecture diagram above for the full service topology.

### Environment Configuration

Create a `.env` file with:

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `REDIS_URL` | Yes | Redis connection string |
| `QDRANT_URL` | Yes | Qdrant vector database URL |
| `HAYSTACK_SERVICE_URL` | Yes | Haystack Python service URL |
| `OPENAI_API_KEY` | For RAG | OpenAI API key for GPT-4o |
| `ANTHROPIC_API_KEY` | For RAG | Anthropic API key for Claude |

## API Reference

### Rails API (Port 3000)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/documents` | POST | Upload a document |
| `/api/v1/search` | POST | Search documents |
| `/api/v1/organizations/:id/documents` | GET | List organization documents |
| `/health` | GET | Service health check |

### Haystack API (Port 8000)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/search` | POST | Semantic vector search |
| `/hybrid-search` | POST | Combined vector + keyword search |
| `/rag/answer` | POST | Get AI-generated answer with sources |
| `/rag/stream` | POST | Streaming RAG response (SSE) |
| `/embeddings/generate` | POST | Generate text embeddings |
| `/extract/pdf` | POST | Extract text from PDF |
| `/extract/docx` | POST | Extract text from Word documents |
| `/extract/excel` | POST | Extract text from Excel files |

## Data Ingestion

### Supported Datasets

The platform includes scripts for ingesting public datasets:

| Dataset | Size | Use Case |
|---------|------|----------|
| SEC EDGAR 10-K Filings | 35K+ vectors | Financial document analysis |
| Wikipedia | 6.4M articles | General knowledge |
| MS MARCO | 8.8M passages | Search quality benchmarks |
| SQuAD | 87K passages | Question answering |
| arXiv | 203K papers | Scientific research |

### Completed Ingestions

| Dataset | Vectors | Model | Collection |
|---------|---------|-------|------------|
| SEC 10-K (2024) | 35,080 | OpenAI text-embedding-3-small | `sec_10k_v2_openai-3-small` |

## Development

### Running Tests

Tests run automatically via GitHub Actions on every push. For local testing:

```bash
# Rails
docker compose run --rm rails bundle exec rspec

# Python
docker compose run --rm haystack pytest tests/ -v

# Rust
docker compose run --rm rust-embedding cargo test
```

### CI/CD Pipeline

The GitHub Actions workflow includes:

- Security scanning (Brakeman)
- Linting (RuboCop, Clippy)
- Unit and integration tests for Rails, Python, and Rust
- Docker build verification

## Database Schema

Key tables for AI functionality:

| Table | Purpose |
|-------|---------|
| `documents` | Document metadata and extracted content |
| `vector_embeddings` | Stored embeddings with model information |
| `conversation_sessions` | RAG conversation tracking |
| `conversation_messages` | Message history for context |

## Roadmap

### Completed
- Full RAG pipeline with OpenAI and Anthropic
- Semantic, keyword, and hybrid search
- SEC EDGAR financial document ingestion
- Multi-language test suite with CI/CD
- Optional Rust high-performance services

### In Progress
- Large-scale dataset testing
- Frontend modernization

### Planned
- Production monitoring and alerting
- Kubernetes deployment
- Multi-node Qdrant cluster
- Auto-scaling policies

## License

Proprietary - All rights reserved.
