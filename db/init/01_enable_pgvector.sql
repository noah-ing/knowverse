-- PostgreSQL initialization script for pgvector extension
-- Automatically enables pgvector for Knowverse vector search capabilities

-- Enable pgvector extension (required for vector operations)
CREATE EXTENSION IF NOT EXISTS vector;

-- Verify extension is enabled
SELECT * FROM pg_extension WHERE extname = 'vector';

-- Set up index methods for better vector search performance
-- (These will be used by Rails migrations)

-- Display current configuration
\echo 'pgvector extension enabled successfully for Knowverse development environment'
\echo 'Vector operators and functions are now available'
