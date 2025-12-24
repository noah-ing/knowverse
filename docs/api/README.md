# KnowVerse API Documentation

KnowVerse provides a RESTful API for document management, semantic search, and AI-powered question answering.

## Authentication

### API Key Authentication

For programmatic access, use an API key in the `Authorization` header:

```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
     https://knowverse.app/api/v1/documents
```

### Session Authentication

For browser-based access, users authenticate via:
- Magic link email
- SSO (SAML 2.0 or OpenID Connect)

---

## Base URL

All API endpoints are relative to your KnowVerse instance:

```
https://knowverse.app
```

---

## Endpoints

### Documents

#### List Documents

```http
GET /organizations/:org_slug/documents
```

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `page` | integer | Page number (default: 1) |
| `per_page` | integer | Items per page (default: 20, max: 100) |
| `status` | string | Filter by status: `pending`, `processing`, `ready`, `error` |

**Response:**
```json
{
  "documents": [
    {
      "id": 1,
      "title": "Q4 2024 Report.pdf",
      "status": "ready",
      "file_type": "application/pdf",
      "file_size": 1048576,
      "chunk_count": 42,
      "created_at": "2024-12-20T10:00:00Z"
    }
  ],
  "meta": {
    "current_page": 1,
    "total_pages": 5,
    "total_count": 100
  }
}
```

#### Upload Document

```http
POST /organizations/:org_slug/documents/upload
Content-Type: multipart/form-data
```

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `files[]` | file | One or more files to upload |

**Supported formats:** PDF, DOCX, DOC, TXT, MD, RTF, XLSX, XLS, CSV

**Response:**
```json
{
  "documents": [
    {
      "id": 2,
      "title": "New Document.pdf",
      "status": "pending"
    }
  ],
  "message": "1 document(s) uploaded successfully"
}
```

#### Get Document

```http
GET /organizations/:org_slug/documents/:id
```

**Response:**
```json
{
  "id": 1,
  "title": "Q4 2024 Report.pdf",
  "status": "ready",
  "file_type": "application/pdf",
  "file_size": 1048576,
  "chunk_count": 42,
  "embedding_status": "completed",
  "metadata": {
    "pages": 15,
    "author": "Finance Team"
  },
  "created_at": "2024-12-20T10:00:00Z",
  "updated_at": "2024-12-20T10:05:00Z"
}
```

#### Delete Document

```http
DELETE /organizations/:org_slug/documents/:id
```

#### Bulk Delete Documents

```http
DELETE /organizations/:org_slug/documents/bulk_destroy
Content-Type: application/json
```

**Body:**
```json
{
  "document_ids": [1, 2, 3]
}
```

---

### Search

#### Semantic Search

```http
POST /search/query
Content-Type: application/json
```

**Body:**
```json
{
  "query": "What were the Q4 revenue figures?",
  "organization_id": 1,
  "provider": "hybrid",
  "limit": 10
}
```

**Search Providers:**
| Provider | Description |
|----------|-------------|
| `pgvector_cosine` | PostgreSQL cosine similarity |
| `pgvector_l2` | PostgreSQL L2 distance |
| `haystack` | Haystack semantic search |
| `hybrid` | Combined keyword + semantic |
| `hybrid_advanced` | Advanced hybrid with reranking |

**Response:**
```json
{
  "results": [
    {
      "document_id": 1,
      "title": "Q4 2024 Report.pdf",
      "content": "Q4 revenue reached $150M, a 25% increase...",
      "score": 0.92,
      "chunk_index": 5
    }
  ],
  "query_id": "abc123",
  "latency_ms": 45
}
```

---

### RAG (Retrieval-Augmented Generation)

#### Ask Question

```http
POST /organizations/:org_slug/rag/answer
Content-Type: application/json
```

**Body:**
```json
{
  "query": "What were the key achievements in Q4?",
  "mode": "standard"
}
```

**Modes:**
| Mode | Description |
|------|-------------|
| `standard` | Direct RAG response |
| `agent` | Agentic RAG with tool use |
| `deep_research` | Multi-source deep research |
| `plan_execute` | Planned multi-step execution |

**Response:**
```json
{
  "answer": "Based on the Q4 2024 report, the key achievements were...",
  "sources": [
    {
      "document_id": 1,
      "title": "Q4 2024 Report.pdf",
      "chunk_index": 5,
      "content_preview": "Revenue reached $150M...",
      "score": 0.92
    }
  ],
  "citations": [
    {
      "sentence_index": 0,
      "source_indices": [1],
      "confidence": 0.89
    }
  ]
}
```

#### Streaming RAG

```http
GET /organizations/:org_slug/rag/stream?query=YOUR_QUERY
Accept: text/event-stream
```

Returns Server-Sent Events (SSE):

```
event: context
data: {"documents": [...]}

event: token
data: {"token": "Based"}

event: token
data: {"token": " on"}

event: sources
data: {"sources": [...], "citations": [...]}

event: done
data: {}
```

---

### MCP (Model Context Protocol)

For Claude Desktop integration.

#### List Tools

```http
GET /mcp/tools
X-MCP-Key: YOUR_ORG_MCP_KEY
```

**Response:**
```json
{
  "tools": [
    {
      "name": "search_documents",
      "description": "Search organization documents",
      "input_schema": {...}
    },
    {
      "name": "get_document",
      "description": "Get document content",
      "input_schema": {...}
    },
    {
      "name": "ask_question",
      "description": "Ask a question using RAG",
      "input_schema": {...}
    }
  ]
}
```

#### Execute Tool

```http
POST /mcp/execute
X-MCP-Key: YOUR_ORG_MCP_KEY
Content-Type: application/json
```

**Body:**
```json
{
  "tool": "search_documents",
  "arguments": {
    "query": "revenue reports"
  }
}
```

---

## Error Responses

All errors follow this format:

```json
{
  "error": "Not Found",
  "message": "Document not found",
  "status": 404
}
```

**Common Status Codes:**
| Code | Description |
|------|-------------|
| 400 | Bad Request - Invalid parameters |
| 401 | Unauthorized - Invalid or missing authentication |
| 403 | Forbidden - Insufficient permissions |
| 404 | Not Found - Resource doesn't exist |
| 422 | Unprocessable Entity - Validation failed |
| 429 | Too Many Requests - Rate limit exceeded |
| 500 | Internal Server Error |

---

## Rate Limits

| Plan | Requests/minute | Requests/day |
|------|-----------------|--------------|
| Free | 60 | 1,000 |
| Pro | 300 | 10,000 |
| Enterprise | Custom | Custom |

Rate limit headers are included in all responses:
```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1703520000
```

---

## Webhooks

Configure webhooks to receive real-time notifications:

| Event | Description |
|-------|-------------|
| `document.uploaded` | Document upload completed |
| `document.processed` | Document processing finished |
| `document.error` | Document processing failed |

Webhook payload:
```json
{
  "event": "document.processed",
  "timestamp": "2024-12-20T10:05:00Z",
  "data": {
    "document_id": 1,
    "organization_id": 1,
    "status": "ready"
  }
}
```
