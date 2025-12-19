"""
Qdrant vector database client for KnowVerse Haystack service.
Connects to the same Qdrant instance used by Rails for document retrieval.
"""

import os
import logging
import httpx
import numpy as np
from typing import Dict, List, Optional, Any, Union

logger = logging.getLogger(__name__)

QDRANT_URL = os.getenv('QDRANT_URL', 'http://localhost:6333')


class QdrantClient:
    """Simple Qdrant client for vector search."""

    def __init__(self, url: str = None):
        self.url = url or QDRANT_URL
        self.client = httpx.Client(timeout=30.0)
        logger.info(f"Qdrant client initialized with URL: {self.url}")

    def get_collection_name(self, org_id: int) -> str:
        """Get the collection name for an organization (matches Rails naming)."""
        return f"knowverse_org_{org_id}_embeddings"

    def search(
        self,
        org_id: int,
        query_vector: Union[List[float], np.ndarray],
        limit: int = 10,
        score_threshold: float = 0.0,
        filters: Optional[Dict[str, Any]] = None
    ) -> List[Dict[str, Any]]:
        """
        Search for similar documents in Qdrant.

        Args:
            org_id: Organization ID
            query_vector: Query embedding vector (list or numpy array)
            limit: Maximum number of results
            score_threshold: Minimum similarity score
            filters: Optional Qdrant filters

        Returns:
            List of search results with id, score, and payload
        """
        collection_name = self.get_collection_name(org_id)

        # Convert numpy array to list if needed
        if isinstance(query_vector, np.ndarray):
            query_vector = query_vector.tolist()

        # Build search request
        search_request = {
            "vector": query_vector,
            "limit": limit,
            "score_threshold": score_threshold,
            "with_payload": True,
            "with_vector": False
        }

        if filters:
            search_request["filter"] = filters

        try:
            response = self.client.post(
                f"{self.url}/collections/{collection_name}/points/search",
                json=search_request
            )
            response.raise_for_status()

            data = response.json()
            results = []

            for point in data.get("result", []):
                payload = point.get("payload", {})
                results.append({
                    "id": point.get("id"),
                    "score": point.get("score", 0.0),
                    "document_id": payload.get("document_id"),
                    "title": payload.get("title", ""),
                    "content": payload.get("content", payload.get("text", "")),
                    "source": payload.get("source", payload.get("filename", "")),
                    "chunk_index": payload.get("chunk_index"),
                    "metadata": payload
                })

            logger.info(f"Qdrant search returned {len(results)} results for org {org_id}")
            return results

        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                logger.warning(f"Collection {collection_name} not found")
                return []
            logger.error(f"Qdrant search failed: {e}")
            raise
        except Exception as e:
            logger.error(f"Qdrant search error: {e}")
            raise

    def health_check(self) -> bool:
        """Check if Qdrant is healthy."""
        try:
            response = self.client.get(f"{self.url}/readyz")
            return response.status_code == 200
        except Exception:
            return False


# Singleton instance
_qdrant_client = None


def get_qdrant_client() -> QdrantClient:
    """Get or create the singleton Qdrant client."""
    global _qdrant_client
    if _qdrant_client is None:
        _qdrant_client = QdrantClient()
    return _qdrant_client
