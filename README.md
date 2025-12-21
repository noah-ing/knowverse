# KnowVerse

AI-powered knowledge management platform with semantic search and retrieval-augmented generation (RAG).


## Overview

KnowVerse is a multi-tenant document intelligence platform that enables organizations to:

- **Upload documents** (PDF, Word, Excel) and automatically extract and index content
- **Search semantically** using natural language instead of exact keywords
- **Ask questions** and receive AI-generated answers grounded in your actual documents
- **Track sources** with inline citations linking back to original documents

Built with Rails 8, PostgreSQL, Qdrant vector database, and Python/Haystack for ML operations.

## Features

| Feature | Description |
|---------|-------------|
| **Semantic Search** | Vector similarity search using sentence embeddings (all-mpnet-base-v2) |
| **Hybrid Search** | Combines semantic and keyword search using Reciprocal Rank Fusion |
| **RAG Chat** | Conversational AI with streaming responses, powered by GPT-4o or Claude |
| **Document Processing** | PDF, DOCX, and Excel extraction with table support |
| **Vector Visualization** | Interactive 3D visualization of document embeddings with t-SNE/UMAP projections |
| **Document Clustering** | Group similar documents using K-Means, Hierarchical, or DBSCAN algorithms |
| **Multi-Tenancy** | Organization-based data isolation with role-based access |
| **Cross-Encoder Reranking** | Optional second-stage reranking for improved relevance |

## Architecture

```
Rails 8 (Web/API)  ─────┬───── PostgreSQL (Metadata + pgvector)
      │                 │
      │                 ├───── Qdrant (Vector Search)
      │                 │
      └─── Haystack ────┴───── Embeddings, Extraction, RAG
           (Python)
```

## Quick Start

### Prerequisites

- Ruby 3.2+
- Python 3.11+
- PostgreSQL 14+ with pgvector
- Redis 7+
- Docker (optional)

### Development Setup

```bash
# Clone and install
git clone https://github.com/your-org/knowverse.git
cd knowverse

# Install dependencies
bundle install
pip install -r services/haystack/requirements.txt

# Database setup
bin/rails db:setup

# Start services
docker compose up -d qdrant redis
bin/rails server

# In another terminal
cd services/haystack && uvicorn app.main:app --reload
```

### Docker (Full Stack)

```bash
docker compose up -d
```

## Configuration

Create a `.env` file:

```env
DATABASE_URL=postgres://localhost/knowverse_development
REDIS_URL=redis://localhost:6379
QDRANT_URL=http://localhost:6333
HAYSTACK_SERVICE_URL=http://localhost:8000

# AI providers (at least one required for RAG)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
```

## API Endpoints

### Documents

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/documents` | Upload document |
| GET | `/api/v1/organizations/:id/documents` | List documents |
| DELETE | `/api/v1/documents/:id` | Delete document |

### Search

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/search` | Semantic/hybrid search |
| GET | `/search` | Web search interface |

### RAG

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/rag/query` | Single question/answer |
| POST | `/rag/stream` | Streaming response (SSE) |

## Technology Stack

- **Backend**: Rails 8, Ruby 3.2
- **Database**: PostgreSQL 14+ with pgvector
- **Vector Store**: Qdrant (HNSW indexing)
- **ML Services**: Python 3.11, Haystack, FastAPI
- **Embeddings**: SentenceTransformers (all-mpnet-base-v2)
- **LLMs**: OpenAI GPT-4o, Anthropic Claude
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS
- **Background Jobs**: Solid Queue
- **Caching**: Solid Cache + Redis

## Testing

```bash
# Rails
bundle exec rspec

# Python
cd services/haystack && pytest

# Linting
bundle exec rubocop
```

## License

Proprietary - All rights reserved.
