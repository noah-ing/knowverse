"""
Qdrant vector database client for KnowVerse Haystack service.

Enhanced for multi-collection RAG with:
- Collection management with config-based creation
- Cross-collection search with fusion
- Batch operations for ingestion
- Quantization support
"""

import os
import logging
import httpx
import numpy as np
from typing import Dict, List, Optional, Any, Union, Tuple
from collections import defaultdict
from dataclasses import dataclass

logger = logging.getLogger(__name__)

QDRANT_URL = os.getenv('QDRANT_URL', 'http://localhost:6333')
QDRANT_TIMEOUT = float(os.getenv('QDRANT_TIMEOUT', '60.0'))


@dataclass
class SearchResult:
    """Structured search result."""
    id: str
    score: float
    content: str
    title: str
    source: str
    collection: str
    metadata: Dict[str, Any]
    chunk_index: Optional[int] = None

    # For cross-collection fusion
    fused_score: Optional[float] = None
    rerank_score: Optional[float] = None


class QdrantClient:
    """
    Enhanced Qdrant client for multi-collection RAG.

    Supports:
    - Single and multi-collection search
    - Cross-collection fusion (RRF)
    - Collection management with config
    - Batch upsert for ingestion
    - Health monitoring
    """

    def __init__(self, url: str = None, timeout: float = None):
        self.url = url or QDRANT_URL
        self.timeout = timeout or QDRANT_TIMEOUT
        self.client = httpx.Client(timeout=self.timeout)
        self._collection_cache: Dict[str, Dict] = {}
        logger.info(f"Qdrant client initialized: {self.url}")

    # =========================================================================
    # COLLECTION MANAGEMENT
    # =========================================================================

    def list_collections(self) -> List[str]:
        """List all available collections."""
        try:
            response = self.client.get(f"{self.url}/collections")
            response.raise_for_status()
            data = response.json()
            collections = [c['name'] for c in data.get('result', {}).get('collections', [])]
            logger.debug(f"Found {len(collections)} collections")
            return collections
        except Exception as e:
            logger.error(f"Error listing collections: {e}")
            return []

    def collection_exists(self, name: str) -> bool:
        """Check if a collection exists."""
        return name in self.list_collections()

    def get_collection_info(self, name: str) -> Optional[Dict[str, Any]]:
        """Get detailed information about a collection."""
        try:
            response = self.client.get(f"{self.url}/collections/{name}")
            response.raise_for_status()
            data = response.json()
            return data.get('result', {})
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                return None
            raise
        except Exception as e:
            logger.error(f"Error getting collection info: {e}")
            return None

    def create_collection(
        self,
        name: str,
        dimension: int,
        distance: str = "Cosine",
        hnsw_config: Optional[Dict] = None,
        quantization_config: Optional[Dict] = None,
        on_disk_payload: bool = True,
    ) -> bool:
        """
        Create a new collection with specified configuration.

        Args:
            name: Collection name
            dimension: Vector dimension
            distance: Distance metric (Cosine, Euclid, Dot)
            hnsw_config: HNSW index configuration
            quantization_config: Quantization configuration
            on_disk_payload: Store payload on disk

        Returns:
            True if created successfully
        """
        if self.collection_exists(name):
            logger.info(f"Collection {name} already exists")
            return True

        config = {
            "vectors": {
                "size": dimension,
                "distance": distance,
            },
            "on_disk_payload": on_disk_payload,
        }

        if hnsw_config:
            config["hnsw_config"] = hnsw_config

        if quantization_config:
            config["quantization_config"] = quantization_config

        try:
            response = self.client.put(
                f"{self.url}/collections/{name}",
                json=config
            )
            response.raise_for_status()
            logger.info(f"Created collection: {name} (dim={dimension})")
            return True
        except Exception as e:
            logger.error(f"Failed to create collection {name}: {e}")
            return False

    def create_collection_from_config(self, config) -> bool:
        """
        Create a collection from a CollectionConfig object.

        Args:
            config: CollectionConfig from collections.py
        """
        from config.collections import get_qdrant_create_params

        params = get_qdrant_create_params(config)

        return self.create_collection(
            name=config.name,
            dimension=params["vectors_config"]["size"],
            distance=params["vectors_config"]["distance"],
            hnsw_config=params.get("hnsw_config"),
            quantization_config=params.get("quantization_config"),
            on_disk_payload=params.get("on_disk_payload", True),
        )

    def delete_collection(self, name: str) -> bool:
        """Delete a collection."""
        try:
            response = self.client.delete(f"{self.url}/collections/{name}")
            response.raise_for_status()
            logger.info(f"Deleted collection: {name}")
            return True
        except Exception as e:
            logger.error(f"Failed to delete collection {name}: {e}")
            return False

    # =========================================================================
    # SINGLE COLLECTION SEARCH
    # =========================================================================

    def search(
        self,
        collection: str,
        query_vector: Union[List[float], np.ndarray],
        limit: int = 10,
        score_threshold: float = 0.0,
        filters: Optional[Dict[str, Any]] = None,
        with_payload: bool = True,
        with_vector: bool = False,

        # Legacy support
        org_id: Optional[int] = None,
    ) -> List[SearchResult]:
        """
        Search for similar documents in a single collection.

        Args:
            collection: Collection name or type (for legacy support)
            query_vector: Query embedding vector
            limit: Maximum results
            score_threshold: Minimum similarity
            filters: Qdrant filter conditions
            with_payload: Include payload in results
            with_vector: Include vectors in results
            org_id: Organization ID (legacy support)

        Returns:
            List of SearchResult objects
        """
        # Legacy support: map collection types to names
        collection_name = self._resolve_collection_name(collection, org_id)

        # Convert numpy array to list
        if isinstance(query_vector, np.ndarray):
            query_vector = query_vector.tolist()

        search_request = {
            "vector": query_vector,
            "limit": limit,
            "score_threshold": score_threshold,
            "with_payload": with_payload,
            "with_vector": with_vector,
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
                results.append(SearchResult(
                    id=str(point.get("id")),
                    score=point.get("score", 0.0),
                    content=payload.get("content", payload.get("text", "")),
                    title=payload.get("title", ""),
                    source=payload.get("source", payload.get("filename", "")),
                    collection=collection_name,
                    metadata=payload,
                    chunk_index=payload.get("chunk_index"),
                ))

            logger.debug(f"Search in {collection_name}: {len(results)} results")
            return results

        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                logger.warning(f"Collection not found: {collection_name}")
                return []
            logger.error(f"Search failed in {collection_name}: {e}")
            raise
        except Exception as e:
            logger.error(f"Search error in {collection_name}: {e}")
            raise

    # =========================================================================
    # MULTI-COLLECTION SEARCH
    # =========================================================================

    def search_multiple(
        self,
        collections: List[str],
        query_vectors: Dict[str, Union[List[float], np.ndarray]],
        limit_per_collection: int = 20,
        final_limit: int = 10,
        score_threshold: float = 0.0,
        fusion_method: str = "rrf",
        collection_weights: Optional[Dict[str, float]] = None,
    ) -> List[SearchResult]:
        """
        Search across multiple collections and fuse results.

        Args:
            collections: List of collection names
            query_vectors: Dict mapping collection name to query vector
                          (different collections may need different embeddings)
            limit_per_collection: Results per collection before fusion
            final_limit: Final number of results after fusion
            score_threshold: Minimum score threshold
            fusion_method: "rrf" (reciprocal rank fusion) or "weighted"
            collection_weights: Optional weights per collection

        Returns:
            Fused and sorted list of SearchResult objects
        """
        all_results: List[Tuple[str, List[SearchResult]]] = []

        for collection in collections:
            # Get the appropriate query vector for this collection
            if collection in query_vectors:
                query_vector = query_vectors[collection]
            elif "default" in query_vectors:
                query_vector = query_vectors["default"]
            else:
                logger.warning(f"No query vector for collection {collection}, skipping")
                continue

            try:
                results = self.search(
                    collection=collection,
                    query_vector=query_vector,
                    limit=limit_per_collection,
                    score_threshold=score_threshold,
                )
                all_results.append((collection, results))
            except Exception as e:
                logger.warning(f"Search failed for {collection}: {e}")
                continue

        if not all_results:
            return []

        # Fuse results
        if fusion_method == "rrf":
            fused = self._reciprocal_rank_fusion(all_results, collection_weights)
        else:
            fused = self._weighted_fusion(all_results, collection_weights)

        # Sort by fused score and limit
        fused.sort(key=lambda r: r.fused_score or 0, reverse=True)
        return fused[:final_limit]

    def _reciprocal_rank_fusion(
        self,
        result_lists: List[Tuple[str, List[SearchResult]]],
        weights: Optional[Dict[str, float]] = None,
        k: int = 60,
    ) -> List[SearchResult]:
        """
        Fuse results using Reciprocal Rank Fusion (RRF).

        RRF score = sum(weight / (k + rank)) across all lists
        """
        scores: Dict[str, float] = defaultdict(float)
        result_map: Dict[str, SearchResult] = {}

        for collection, results in result_lists:
            weight = weights.get(collection, 1.0) if weights else 1.0

            for rank, result in enumerate(results):
                # Create unique key based on content hash
                key = f"{result.collection}:{result.id}"

                # RRF formula
                scores[key] += weight / (k + rank + 1)

                # Store result (keep highest scoring version)
                if key not in result_map or result.score > result_map[key].score:
                    result_map[key] = result

        # Apply fused scores
        for key, result in result_map.items():
            result.fused_score = scores[key]

        return list(result_map.values())

    def _weighted_fusion(
        self,
        result_lists: List[Tuple[str, List[SearchResult]]],
        weights: Optional[Dict[str, float]] = None,
    ) -> List[SearchResult]:
        """
        Fuse results using weighted score combination.
        """
        scores: Dict[str, float] = defaultdict(float)
        result_map: Dict[str, SearchResult] = {}

        for collection, results in result_lists:
            weight = weights.get(collection, 1.0) if weights else 1.0

            for result in results:
                key = f"{result.collection}:{result.id}"
                scores[key] = max(scores[key], result.score * weight)

                if key not in result_map or result.score > result_map[key].score:
                    result_map[key] = result

        for key, result in result_map.items():
            result.fused_score = scores[key]

        return list(result_map.values())

    # =========================================================================
    # BATCH OPERATIONS (For Ingestion)
    # =========================================================================

    def upsert_batch(
        self,
        collection: str,
        points: List[Dict[str, Any]],
        wait: bool = True,
    ) -> bool:
        """
        Upsert a batch of points to a collection.

        Args:
            collection: Collection name
            points: List of point dicts with 'id', 'vector', 'payload'
            wait: Wait for operation to complete

        Returns:
            True if successful
        """
        if not points:
            return True

        try:
            response = self.client.put(
                f"{self.url}/collections/{collection}/points",
                json={
                    "points": points,
                },
                params={"wait": str(wait).lower()}
            )
            response.raise_for_status()
            logger.debug(f"Upserted {len(points)} points to {collection}")
            return True
        except Exception as e:
            logger.error(f"Batch upsert failed for {collection}: {e}")
            return False

    def count_points(self, collection: str) -> int:
        """Get the number of points in a collection."""
        info = self.get_collection_info(collection)
        if info:
            return info.get("points_count", 0)
        return 0

    # =========================================================================
    # UTILITY METHODS
    # =========================================================================

    def _resolve_collection_name(
        self,
        collection: str,
        org_id: Optional[int] = None
    ) -> str:
        """
        Resolve collection type to actual collection name.

        Supports legacy naming patterns and new config-based names.
        """
        # Legacy patterns
        if collection == "sec_edgar" and org_id:
            return f"org_{org_id}_v1_ada002"
        elif collection == "default" and org_id:
            return f"org_{org_id}_documents"
        elif "{org_id}" in collection and org_id:
            return collection.format(org_id=org_id)

        # Direct collection name
        return collection

    def health_check(self) -> Dict[str, Any]:
        """
        Comprehensive health check.

        Returns:
            Dict with health status and details
        """
        try:
            # Check readiness
            ready_response = self.client.get(f"{self.url}/readyz")
            is_ready = ready_response.status_code == 200

            # Get cluster info
            collections = self.list_collections()

            # Get storage info for each collection
            collection_stats = {}
            for coll in collections[:10]:  # Limit to avoid timeout
                info = self.get_collection_info(coll)
                if info:
                    collection_stats[coll] = {
                        "points": info.get("points_count", 0),
                        "status": info.get("status", "unknown"),
                    }

            return {
                "status": "healthy" if is_ready else "unhealthy",
                "url": self.url,
                "collections": len(collections),
                "collection_stats": collection_stats,
            }
        except Exception as e:
            return {
                "status": "unhealthy",
                "error": str(e),
                "url": self.url,
            }

    def close(self):
        """Close the HTTP client."""
        self.client.close()


# =============================================================================
# SINGLETON MANAGEMENT
# =============================================================================

_qdrant_client: Optional[QdrantClient] = None


def get_qdrant_client() -> QdrantClient:
    """Get or create the singleton Qdrant client."""
    global _qdrant_client
    if _qdrant_client is None:
        _qdrant_client = QdrantClient()
    return _qdrant_client


def reset_qdrant_client():
    """Reset the singleton client (for testing)."""
    global _qdrant_client
    if _qdrant_client:
        _qdrant_client.close()
    _qdrant_client = None
