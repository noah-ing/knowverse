import logging
from functools import lru_cache
from haystack.document_stores.in_memory import InMemoryDocumentStore
# Note: Using InMemoryDocumentStore for development and testing
# Enterprise production would use PostgreSQL or other persistent stores
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
    Uses Haystack 2.x InMemoryDocumentStore for development.
    Enterprise deployments should configure persistent document stores.
    """
    logger.info("Using Haystack 2.x InMemoryDocumentStore for development")
    # Haystack 2.x InMemoryDocumentStore has a simpler API
    return InMemoryDocumentStore()
