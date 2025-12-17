# KnowVerse Haystack Service

This is a FastAPI-based microservice that provides document processing, embedding generation, and semantic search capabilities for the KnowVerse application using the Haystack framework.

## Features

- Document indexing with vector embeddings
- Text embedding generation using sentence-transformers
- Semantic search with cosine similarity
- Question answering using extractive QA
- PostgreSQL integration with pgvector extension

## Requirements

- Python 3.10+
- PostgreSQL 14+ with pgvector extension
- Dependencies listed in requirements.txt

## Setup

1. Create and activate a virtual environment:

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Configure environment variables in .env file:

```
# Copy the example .env file
cp .env.example .env

# Edit .env file with your specific configuration
```

4. Ensure PostgreSQL is running with pgvector extension enabled

## Running the Service

Start the service using Uvicorn:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Or using the built-in script:

```bash
python -m app.main
```

## API Endpoints

- `GET /health` - Health check endpoint
- `POST /embeddings/generate` - Generate embeddings for text
- `POST /documents/index` - Index a document
- `POST /search` - Perform semantic search
- `POST /question-answering` - Answer questions based on indexed documents

## Development

The service is organized into several modules:

- `app/main.py` - FastAPI application and routes
- `app/document_store.py` - Document store configuration
- `app/embeddings.py` - Embedding models and utilities
- `app/search.py` - Search and QA pipelines

## Integration with Rails

This microservice is designed to be used with the KnowVerse Rails application. The Rails app communicates with this service via HTTP requests through the `HaystackClient` service.

## Environment Variables

- `API_HOST` - Host to bind server (default: 0.0.0.0)
- `API_PORT` - Port to bind server (default: 8000)
- `DEBUG` - Enable debug mode (default: False)
- `DB_HOST` - PostgreSQL host (default: localhost)
- `DB_PORT` - PostgreSQL port (default: 5432)
- `DB_NAME` - PostgreSQL database name
- `DB_USER` - PostgreSQL username
- `DB_PASSWORD` - PostgreSQL password
- `EMBEDDING_MODEL_NAME` - Name of the sentence-transformers model to use
