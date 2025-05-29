import logging
from functools import lru_cache
from haystack.document_stores import PostgreSQLDocumentStore, InMemoryDocumentStore
from config.settings import (
    DB_CONNECTION_STRING,
    DB_NAME,
    DB_USER,
    DB_PASSWORD,
    DB_HOST,
    DB_PORT,
    DB_SCHEMA,
    DOCUMENT_STORE_TYPE
)

logger = logging.getLogger(__name__)

@lru_cache(maxsize=1)
def get_document_store():
    """
    Get a document store instance (cached for efficiency).
    Uses PostgreSQL with pgvector extension by default.
    Falls back to InMemory store if configured or if PostgreSQL fails.
    """
    if DOCUMENT_STORE_TYPE.lower() == 'pgvector':
        try:
            logger.info(f"Initializing PostgreSQLDocumentStore with schema: {DB_SCHEMA}")
            document_store = PostgreSQLDocumentStore(
                connection_string=DB_CONNECTION_STRING,
                embedding_dim=768,  # Default for DPR embedding
                index="haystack_document_vector_index",
                embedding_field="embedding",
                similarity="cosine",
                scheme=DB_SCHEMA,
                recreate_index=False,
                isolation_level="AUTOCOMMIT",
                return_embedding=True,
                use_gpu=False,
                duplicate_documents="skip"
            )
            logger.info("PostgreSQLDocumentStore successfully initialized")
            return document_store
            
        except Exception as e:
            logger.error(f"Failed to initialize PostgreSQLDocumentStore: {str(e)}")
            logger.warning("Falling back to InMemoryDocumentStore")
            
            # Fall back to in-memory document store
            return InMemoryDocumentStore(
                embedding_dim=768,
                embedding_field="embedding",
                similarity="cosine",
                return_embedding=True
            )
    else:
        logger.info("Using InMemoryDocumentStore as configured")
        return InMemoryDocumentStore(
            embedding_dim=768,
            embedding_field="embedding",
            similarity="cosine",
            return_embedding=True
        )
