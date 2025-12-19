#!/usr/bin/env python3
"""
Elite Multi-Collection Ingestion Pipeline for KnowVerse.

Designed for scale: 100M+ vectors across multiple knowledge domains.

Architecture:
- Collection-config driven (uses config/collections.py)
- Local embeddings (e5-large-v2) for cost-effective scale
- OpenAI embeddings for high-precision domains
- Binary/scalar quantization per collection
- Resume capability with progress tracking
- Batch processing with memory management

Supported datasets:
- Wikipedia (6M+ articles) - General knowledge
- arXiv (2M+ papers) - Scientific research
- StackOverflow (23M+ Q&A) - Technical knowledge
- MS MARCO (8.8M passages) - Benchmark/diverse

Usage:
    python scripts/ingest_elite.py --dataset wikipedia --limit 100000
    python scripts/ingest_elite.py --dataset arxiv --categories cs.AI cs.LG
    python scripts/ingest_elite.py --dataset stackoverflow --limit 1000000
    python scripts/ingest_elite.py --list
    python scripts/ingest_elite.py --status
"""

import argparse
import json
import os
import sys
import hashlib
import time
import gc
from datetime import datetime, timezone
from pathlib import Path
from typing import Generator, Dict, Any, List, Optional, Tuple
from dataclasses import dataclass, field
import logging

# Load environment
from dotenv import load_dotenv
load_dotenv()

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
STORAGE_PATH = os.getenv("STORAGE_PATH", "/Volumes/monster/knowverse")
PROGRESS_DIR = Path(STORAGE_PATH) / "ingestion_progress"
HF_CACHE_DIR = Path(STORAGE_PATH) / "hf_cache"
QDRANT_URL = os.getenv("QDRANT_URL", "http://localhost:6333")

# Ensure directories exist
PROGRESS_DIR.mkdir(parents=True, exist_ok=True)
HF_CACHE_DIR.mkdir(parents=True, exist_ok=True)

# Set HF cache
os.environ["HF_HOME"] = str(HF_CACHE_DIR)
os.environ["TRANSFORMERS_CACHE"] = str(HF_CACHE_DIR / "transformers")


# =============================================================================
# DATASET CONFIGURATIONS
# =============================================================================

DATASETS = {
    "wikipedia": {
        "hf_id": "wikimedia/wikipedia",
        "hf_config": "20231101.en",
        "description": "English Wikipedia - 6.7M articles for general knowledge",
        "collection": "wikipedia",
        "text_field": "text",
        "title_field": "title",
        "id_field": "id",
        "estimated_vectors": "6,700,000",
        "metadata_fields": ["title", "url"],
    },
    "arxiv": {
        "hf_id": "arxiv-community/arxiv-abstracts",
        "description": "arXiv paper abstracts - 2M+ scientific papers",
        "collection": "arxiv",
        "text_field": "abstract",
        "title_field": "title",
        "id_field": "arxiv_id",
        "estimated_vectors": "2,300,000",
        "metadata_fields": ["title", "authors", "categories", "arxiv_id"],
    },
    "stackoverflow": {
        "hf_id": "pacovaldez/stackoverflow-questions",
        "description": "Stack Overflow questions - programming Q&A",
        "collection": "stackoverflow",
        "text_field": "Body",
        "title_field": "Title",
        "id_field": "Id",
        "estimated_vectors": "23,000,000",
        "metadata_fields": ["Title", "Tags", "Score"],
    },
    "msmarco": {
        "hf_id": "ms_marco",
        "hf_config": "v2.1",
        "description": "MS MARCO passages - diverse web content for benchmarking",
        "collection": "msmarco",
        "text_field": "passages",
        "estimated_vectors": "8,800,000",
        "metadata_fields": [],
    },
}


# =============================================================================
# DATA CLASSES
# =============================================================================

@dataclass
class Chunk:
    """Document chunk with position metadata."""
    text: str
    chunk_index: int
    total_chunks: int
    start_char: int
    end_char: int
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class EmbeddingBatch:
    """Batch of embeddings with metadata."""
    vectors: List[List[float]]
    texts: List[str]
    model: str
    dimension: int


# =============================================================================
# PROGRESS TRACKER
# =============================================================================

class ProgressTracker:
    """Track ingestion progress for resume capability."""

    def __init__(self, dataset: str, collection: str):
        self.dataset = dataset
        self.collection = collection
        self.progress_file = PROGRESS_DIR / f"{dataset}_{collection}.json"

        self.processed_ids: set = set()
        self.stats = {
            "started_at": None,
            "last_updated": None,
            "total_docs": 0,
            "total_chunks": 0,
            "total_vectors": 0,
            "last_offset": 0,
        }
        self._load()

    def _load(self):
        """Load existing progress."""
        if self.progress_file.exists():
            try:
                with open(self.progress_file, 'r') as f:
                    data = json.load(f)
                    self.processed_ids = set(data.get("processed_ids", []))
                    self.stats = data.get("stats", self.stats)
                    logger.info(f"Resuming: {len(self.processed_ids)} docs already processed")
            except Exception as e:
                logger.warning(f"Could not load progress: {e}")

    def _save(self):
        """Save progress atomically."""
        self.stats["last_updated"] = datetime.now(timezone.utc).isoformat()

        # Only save last 100K IDs to keep file manageable
        ids_to_save = list(self.processed_ids)[-100000:]

        data = {
            "dataset": self.dataset,
            "collection": self.collection,
            "stats": self.stats,
            "processed_ids": ids_to_save,
        }

        temp_file = self.progress_file.with_suffix('.tmp')
        with open(temp_file, 'w') as f:
            json.dump(data, f)
        temp_file.rename(self.progress_file)

    def is_processed(self, doc_id: str) -> bool:
        return doc_id in self.processed_ids

    def mark_processed(self, doc_id: str, chunks: int):
        """Mark document as processed."""
        self.processed_ids.add(doc_id)

        if self.stats["started_at"] is None:
            self.stats["started_at"] = datetime.now(timezone.utc).isoformat()

        self.stats["total_docs"] += 1
        self.stats["total_chunks"] += chunks
        self.stats["total_vectors"] += chunks

        # Save every 100 documents
        if self.stats["total_docs"] % 100 == 0:
            self._save()

    def set_offset(self, offset: int):
        """Track dataset offset for streaming."""
        self.stats["last_offset"] = offset

    def finalize(self):
        """Save final progress."""
        self._save()

    def get_summary(self) -> str:
        return (
            f"Docs: {self.stats['total_docs']:,} | "
            f"Chunks: {self.stats['total_chunks']:,} | "
            f"Vectors: {self.stats['total_vectors']:,}"
        )


# =============================================================================
# CHUNKER
# =============================================================================

class SemanticChunker:
    """Semantic-aware text chunker."""

    def __init__(self, chunk_size: int = 500, chunk_overlap: int = 50):
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap
        self.chars_per_token = 4

        self.separators = [
            "\n\n\n", "\n\n", "\n",
            ". ", "! ", "? ", "; ",
            ", ", " ", ""
        ]

    def chunk(self, text: str, metadata: Dict = None) -> List[Chunk]:
        """Split text into semantic chunks."""
        if not text or len(text.strip()) < 50:
            return []

        metadata = metadata or {}
        char_size = self.chunk_size * self.chars_per_token
        char_overlap = self.chunk_overlap * self.chars_per_token

        raw_chunks = self._split_recursive(text, char_size, char_overlap)

        chunks = []
        for i, chunk_text in enumerate(raw_chunks):
            if len(chunk_text.strip()) < 20:
                continue
            chunks.append(Chunk(
                text=chunk_text.strip(),
                chunk_index=i,
                total_chunks=len(raw_chunks),
                start_char=0,
                end_char=len(chunk_text),
                metadata=metadata.copy()
            ))

        return chunks

    def _split_recursive(self, text: str, chunk_size: int, overlap: int) -> List[str]:
        """Recursively split using separator hierarchy."""
        if not text:
            return []

        if len(text) <= chunk_size:
            return [text] if text.strip() else []

        # Find best separator
        separator = ""
        for sep in self.separators:
            if sep in text:
                separator = sep
                break

        if separator:
            parts = text.split(separator)
        else:
            # Character split as last resort
            return [text[i:i+chunk_size] for i in range(0, len(text), chunk_size - overlap)]

        # Merge parts into chunks
        chunks = []
        current = []
        current_len = 0

        for part in parts:
            part_len = len(part) + len(separator)

            if current_len + part_len <= chunk_size:
                current.append(part)
                current_len += part_len
            else:
                if current:
                    chunks.append(separator.join(current))

                if part_len > chunk_size:
                    # Recursively split oversized parts
                    sub_chunks = self._split_recursive(part, chunk_size, overlap)
                    chunks.extend(sub_chunks)
                    current = []
                    current_len = 0
                else:
                    current = [part]
                    current_len = part_len

        if current:
            chunks.append(separator.join(current))

        return chunks


# =============================================================================
# LOCAL EMBEDDER (e5-large-v2)
# =============================================================================

class LocalEmbedder:
    """
    Local embedding model using sentence-transformers.

    Uses e5-large-v2 by default - excellent quality, 1024 dimensions.
    Free and runs on CPU (slower but no API costs).
    """

    def __init__(self, model_name: str = "intfloat/e5-large-v2"):
        self.model_name = model_name
        self.model = None
        self.dimension = None

    def _load_model(self):
        """Lazy load the model."""
        if self.model is None:
            from sentence_transformers import SentenceTransformer
            logger.info(f"Loading embedding model: {self.model_name}")
            self.model = SentenceTransformer(
                self.model_name,
                cache_folder=str(HF_CACHE_DIR / "models")
            )
            self.dimension = self.model.get_sentence_embedding_dimension()
            logger.info(f"Model loaded: {self.dimension}d embeddings")

    def embed_batch(self, texts: List[str], batch_size: int = 32) -> List[List[float]]:
        """Generate embeddings for a batch of texts."""
        self._load_model()

        if not texts:
            return []

        # For e5 models, prepend "passage: " for documents
        prefixed_texts = [f"passage: {t}" for t in texts]

        all_embeddings = []
        for i in range(0, len(prefixed_texts), batch_size):
            batch = prefixed_texts[i:i + batch_size]
            embeddings = self.model.encode(
                batch,
                show_progress_bar=False,
                convert_to_numpy=True
            )
            all_embeddings.extend(embeddings.tolist())

        return all_embeddings

    def get_dimension(self) -> int:
        """Get embedding dimension."""
        self._load_model()
        return self.dimension


# =============================================================================
# OPENAI EMBEDDER
# =============================================================================

class OpenAIEmbedder:
    """OpenAI embedding client for high-precision domains."""

    def __init__(self, model: str = "text-embedding-ada-002"):
        self.model = model
        self.dimension = 1536 if "ada" in model or "3-small" in model else 3072
        self.api_key = os.getenv("OPENAI_API_KEY")

        if not self.api_key:
            raise ValueError("OPENAI_API_KEY required for OpenAI embeddings")

    def embed_batch(self, texts: List[str], batch_size: int = 100) -> List[List[float]]:
        """Generate embeddings using OpenAI API."""
        import openai
        client = openai.OpenAI(api_key=self.api_key)

        all_embeddings = []
        for i in range(0, len(texts), batch_size):
            batch = texts[i:i + batch_size]

            # Rate limiting
            time.sleep(0.1)

            try:
                response = client.embeddings.create(
                    model=self.model,
                    input=batch
                )
                embeddings = [item.embedding for item in response.data]
                all_embeddings.extend(embeddings)
            except Exception as e:
                logger.error(f"OpenAI embedding error: {e}")
                # Return zero vectors for failed batch
                all_embeddings.extend([[0.0] * self.dimension] * len(batch))

        return all_embeddings

    def get_dimension(self) -> int:
        return self.dimension


# =============================================================================
# QDRANT STORE
# =============================================================================

class QdrantStore:
    """Qdrant vector store with quantization support."""

    def __init__(self, url: str = QDRANT_URL):
        import httpx
        self.url = url
        self.client = httpx.Client(timeout=60.0)

    def ensure_collection(
        self,
        name: str,
        dimension: int,
        quantization: str = "none",
        hnsw_m: int = 16,
        hnsw_ef: int = 100
    ):
        """Create collection with quantization config."""

        # Check if exists
        try:
            response = self.client.get(f"{self.url}/collections/{name}")
            if response.status_code == 200:
                logger.info(f"Collection {name} exists")
                return
        except:
            pass

        # Build config
        config = {
            "vectors": {
                "size": dimension,
                "distance": "Cosine"
            },
            "hnsw_config": {
                "m": hnsw_m,
                "ef_construct": hnsw_ef
            },
            "on_disk_payload": True
        }

        # Add quantization
        if quantization == "scalar":
            config["quantization_config"] = {
                "scalar": {
                    "type": "int8",
                    "quantile": 0.99,
                    "always_ram": True
                }
            }
        elif quantization == "binary":
            config["quantization_config"] = {
                "binary": {
                    "always_ram": True
                }
            }

        try:
            response = self.client.put(
                f"{self.url}/collections/{name}",
                json=config
            )
            response.raise_for_status()
            logger.info(f"Created collection: {name} (dim={dimension}, quant={quantization})")
        except Exception as e:
            logger.error(f"Failed to create collection: {e}")
            raise

    def upsert_batch(self, collection: str, points: List[Dict]) -> int:
        """Upsert a batch of points."""
        if not points:
            return 0

        try:
            response = self.client.put(
                f"{self.url}/collections/{collection}/points",
                json={"points": points},
                params={"wait": "true"}
            )
            response.raise_for_status()
            return len(points)
        except Exception as e:
            logger.error(f"Upsert failed: {e}")
            return 0

    def get_count(self, collection: str) -> int:
        """Get point count."""
        try:
            response = self.client.get(f"{self.url}/collections/{collection}")
            if response.status_code == 200:
                data = response.json()
                return data.get("result", {}).get("points_count", 0)
        except:
            pass
        return 0

    def close(self):
        self.client.close()


# =============================================================================
# DATASET LOADERS
# =============================================================================

def load_wikipedia(limit: Optional[int] = None, offset: int = 0) -> Generator[Dict, None, None]:
    """Stream Wikipedia articles from HuggingFace."""
    from datasets import load_dataset

    logger.info("Loading Wikipedia dataset (streaming)...")
    dataset = load_dataset(
        "wikimedia/wikipedia",
        "20231101.en",
        split="train",
        streaming=True,
        cache_dir=str(HF_CACHE_DIR)
    )

    count = 0
    skipped = 0

    for item in dataset:
        if skipped < offset:
            skipped += 1
            continue

        if limit and count >= limit:
            return

        text = item.get("text", "")
        if len(text) < 100:
            continue

        yield {
            "id": str(item.get("id", count)),
            "title": item.get("title", ""),
            "text": text,
            "url": item.get("url", ""),
        }
        count += 1

        if count % 10000 == 0:
            logger.info(f"Loaded {count:,} Wikipedia articles...")


def load_arxiv(limit: Optional[int] = None, categories: List[str] = None) -> Generator[Dict, None, None]:
    """Stream arXiv abstracts."""
    from datasets import load_dataset

    logger.info("Loading arXiv dataset (streaming)...")
    dataset = load_dataset(
        "arxiv-community/arxiv-abstracts",
        split="train",
        streaming=True,
        cache_dir=str(HF_CACHE_DIR)
    )

    count = 0

    for item in dataset:
        if limit and count >= limit:
            return

        # Filter by categories if specified
        if categories:
            item_cats = item.get("categories", "").split()
            if not any(c in categories for c in item_cats):
                continue

        abstract = item.get("abstract", "")
        if len(abstract) < 50:
            continue

        yield {
            "id": item.get("arxiv_id", str(count)),
            "title": item.get("title", "").replace("\n", " "),
            "text": abstract.replace("\n", " "),
            "authors": item.get("authors", ""),
            "categories": item.get("categories", ""),
            "arxiv_id": item.get("arxiv_id", ""),
        }
        count += 1

        if count % 10000 == 0:
            logger.info(f"Loaded {count:,} arXiv papers...")


def load_stackoverflow(limit: Optional[int] = None) -> Generator[Dict, None, None]:
    """Stream StackOverflow questions."""
    from datasets import load_dataset

    logger.info("Loading StackOverflow dataset (streaming)...")

    try:
        dataset = load_dataset(
            "pacovaldez/stackoverflow-questions",
            split="train",
            streaming=True,
            cache_dir=str(HF_CACHE_DIR)
        )
    except Exception as e:
        logger.warning(f"Primary SO dataset unavailable: {e}")
        logger.info("Trying alternative dataset...")
        dataset = load_dataset(
            "koutch/stackoverflow_python",
            split="train",
            streaming=True,
            cache_dir=str(HF_CACHE_DIR)
        )

    count = 0

    for item in dataset:
        if limit and count >= limit:
            return

        # Handle different field names
        body = item.get("Body") or item.get("body") or item.get("question", "")
        title = item.get("Title") or item.get("title", "")

        if len(body) < 50:
            continue

        # Combine title and body
        text = f"{title}\n\n{body}" if title else body

        yield {
            "id": str(item.get("Id") or item.get("id") or count),
            "title": title,
            "text": text,
            "tags": item.get("Tags") or item.get("tags", ""),
            "score": item.get("Score") or item.get("score", 0),
        }
        count += 1

        if count % 10000 == 0:
            logger.info(f"Loaded {count:,} StackOverflow questions...")


# =============================================================================
# MAIN INGESTION FUNCTION
# =============================================================================

def ingest_dataset(
    dataset_name: str,
    limit: Optional[int] = None,
    batch_size: int = 100,
    embedding_batch_size: int = 32,
    use_openai: bool = False,
    categories: List[str] = None,
    fresh: bool = False
):
    """
    Ingest a dataset into its configured collection.
    """
    if dataset_name not in DATASETS:
        logger.error(f"Unknown dataset: {dataset_name}")
        logger.info(f"Available: {list(DATASETS.keys())}")
        return

    config = DATASETS[dataset_name]
    collection = config["collection"]

    print("\n" + "=" * 70)
    print(f"ELITE INGESTION: {dataset_name.upper()}")
    print("=" * 70)
    print(f"Collection: {collection}")
    print(f"Description: {config['description']}")
    print(f"Estimated vectors: {config['estimated_vectors']}")
    print(f"Limit: {limit or 'None'}")
    print(f"Embeddings: {'OpenAI' if use_openai else 'Local (e5-large-v2)'}")
    print("=" * 70 + "\n")

    # Initialize components
    chunker = SemanticChunker(chunk_size=500, chunk_overlap=50)

    if use_openai:
        embedder = OpenAIEmbedder()
        quantization = "scalar"  # Higher precision for OpenAI
    else:
        embedder = LocalEmbedder("intfloat/e5-large-v2")
        quantization = "binary"  # Good compression for local

    store = QdrantStore()
    progress = ProgressTracker(dataset_name, collection)

    if fresh and progress.progress_file.exists():
        logger.info("Fresh start - clearing progress")
        progress.progress_file.unlink()
        progress = ProgressTracker(dataset_name, collection)

    # Create collection
    dimension = embedder.get_dimension()
    store.ensure_collection(
        name=collection,
        dimension=dimension,
        quantization=quantization,
        hnsw_m=8 if quantization == "binary" else 16,
        hnsw_ef=64 if quantization == "binary" else 100
    )

    # Select data loader
    if dataset_name == "wikipedia":
        data_loader = load_wikipedia(limit=limit, offset=progress.stats["last_offset"])
    elif dataset_name == "arxiv":
        data_loader = load_arxiv(limit=limit, categories=categories)
    elif dataset_name == "stackoverflow":
        data_loader = load_stackoverflow(limit=limit)
    else:
        logger.error(f"No loader for {dataset_name}")
        return

    # Process documents
    batch_chunks = []
    batch_texts = []
    batch_metas = []
    session_docs = 0
    session_chunks = 0
    skipped = 0

    try:
        for doc in data_loader:
            doc_id = doc["id"]

            # Skip if already processed
            if progress.is_processed(doc_id):
                skipped += 1
                continue

            # Chunk the document
            metadata = {
                "doc_id": doc_id,
                "title": doc.get("title", ""),
                "source": dataset_name,
            }

            # Add dataset-specific metadata
            for field in config.get("metadata_fields", []):
                if field in doc:
                    metadata[field.lower()] = doc[field]

            chunks = chunker.chunk(doc["text"], metadata)

            if not chunks:
                continue

            # Add to batch
            for chunk in chunks:
                chunk_id = hashlib.md5(f"{doc_id}_{chunk.chunk_index}".encode()).hexdigest()

                batch_chunks.append({
                    "id": chunk_id,
                    "chunk": chunk
                })
                batch_texts.append(chunk.text)
                batch_metas.append({
                    **chunk.metadata,
                    "chunk_index": chunk.chunk_index,
                    "total_chunks": chunk.total_chunks,
                })

            session_docs += 1
            session_chunks += len(chunks)

            # Process batch
            if len(batch_texts) >= batch_size:
                # Generate embeddings
                embeddings = embedder.embed_batch(batch_texts, batch_size=embedding_batch_size)

                # Build points
                points = []
                for i, (chunk_data, embedding, meta) in enumerate(zip(batch_chunks, embeddings, batch_metas)):
                    points.append({
                        "id": chunk_data["id"],
                        "vector": embedding,
                        "payload": {
                            "content": batch_texts[i],
                            **meta,
                            "ingested_at": datetime.now(timezone.utc).isoformat(),
                        }
                    })

                # Upsert
                store.upsert_batch(collection, points)

                # Mark documents as processed
                processed_docs = set()
                for meta in batch_metas:
                    if meta["doc_id"] not in processed_docs:
                        progress.mark_processed(
                            meta["doc_id"],
                            chunks=meta["total_chunks"]
                        )
                        processed_docs.add(meta["doc_id"])

                # Clear batch
                batch_chunks = []
                batch_texts = []
                batch_metas = []

                # Progress update
                if session_docs % 100 == 0:
                    print(f"  {progress.get_summary()} | Skipped: {skipped}")

                # Memory management
                if session_docs % 1000 == 0:
                    gc.collect()

    except KeyboardInterrupt:
        print("\n\nInterrupted - saving progress...")
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # Process remaining batch
        if batch_texts:
            embeddings = embedder.embed_batch(batch_texts, batch_size=embedding_batch_size)
            points = []
            for i, (chunk_data, embedding, meta) in enumerate(zip(batch_chunks, embeddings, batch_metas)):
                points.append({
                    "id": chunk_data["id"],
                    "vector": embedding,
                    "payload": {
                        "content": batch_texts[i],
                        **meta,
                        "ingested_at": datetime.now(timezone.utc).isoformat(),
                    }
                })
            store.upsert_batch(collection, points)

        progress.finalize()
        store.close()

    # Summary
    print("\n" + "=" * 70)
    print("INGESTION COMPLETE")
    print("=" * 70)
    print(f"Session documents: {session_docs:,}")
    print(f"Session chunks: {session_chunks:,}")
    print(f"Skipped (already done): {skipped:,}")
    print(f"\nTotal progress:")
    print(f"  {progress.get_summary()}")
    print(f"\nCollection: {collection}")
    print(f"Total vectors: {store.get_count(collection):,}")
    print(f"Progress file: {progress.progress_file}")
    print("=" * 70)


def show_status():
    """Show status of all collections and progress."""
    import httpx

    print("\n" + "=" * 70)
    print("ELITE RAG STATUS")
    print("=" * 70)

    # Check Qdrant
    try:
        client = httpx.Client(timeout=10.0)
        response = client.get(f"{QDRANT_URL}/collections")
        if response.status_code == 200:
            data = response.json()
            collections = data.get("result", {}).get("collections", [])

            print(f"\nQdrant: {QDRANT_URL}")
            print(f"Collections: {len(collections)}")

            for coll in collections:
                name = coll["name"]
                info_resp = client.get(f"{QDRANT_URL}/collections/{name}")
                if info_resp.status_code == 200:
                    info = info_resp.json().get("result", {})
                    points = info.get("points_count", 0)
                    status = info.get("status", "unknown")
                    print(f"  - {name}: {points:,} vectors ({status})")
        client.close()
    except Exception as e:
        print(f"Qdrant error: {e}")

    # Check progress files
    print(f"\nProgress files ({PROGRESS_DIR}):")
    if PROGRESS_DIR.exists():
        for pf in PROGRESS_DIR.glob("*.json"):
            try:
                with open(pf) as f:
                    data = json.load(f)
                    stats = data.get("stats", {})
                    print(f"  - {pf.stem}:")
                    print(f"      Docs: {stats.get('total_docs', 0):,}")
                    print(f"      Chunks: {stats.get('total_chunks', 0):,}")
                    print(f"      Last: {stats.get('last_updated', 'N/A')}")
            except:
                pass

    # Storage check
    print(f"\nStorage ({STORAGE_PATH}):")
    storage_path = Path(STORAGE_PATH)
    if storage_path.exists():
        import shutil
        total, used, free = shutil.disk_usage(storage_path)
        print(f"  Total: {total // (1024**3)} GB")
        print(f"  Used: {used // (1024**3)} GB")
        print(f"  Free: {free // (1024**3)} GB")
    else:
        print("  Storage path not mounted")

    print("=" * 70)


def list_datasets():
    """List available datasets."""
    print("\n" + "=" * 70)
    print("AVAILABLE DATASETS")
    print("=" * 70)

    for name, config in DATASETS.items():
        print(f"\n{name}:")
        print(f"  {config['description']}")
        print(f"  Collection: {config['collection']}")
        print(f"  Est. vectors: {config['estimated_vectors']}")

    print("\n" + "=" * 70)
    print("EMBEDDING OPTIONS")
    print("=" * 70)
    print("\nLocal (default, free):")
    print("  Model: intfloat/e5-large-v2")
    print("  Dimension: 1024")
    print("  Quantization: Binary (32x compression)")
    print("\nOpenAI (--use-openai):")
    print("  Model: text-embedding-ada-002")
    print("  Dimension: 1536")
    print("  Quantization: Scalar (4x compression)")
    print("=" * 70)


def main():
    parser = argparse.ArgumentParser(
        description="Elite multi-collection ingestion for KnowVerse",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List available datasets
  python scripts/ingest_elite.py --list

  # Check status of all collections
  python scripts/ingest_elite.py --status

  # Ingest Wikipedia (first 100K articles)
  python scripts/ingest_elite.py --dataset wikipedia --limit 100000

  # Ingest arXiv AI papers
  python scripts/ingest_elite.py --dataset arxiv --categories cs.AI cs.LG --limit 50000

  # Ingest with OpenAI embeddings (higher cost, better precision)
  python scripts/ingest_elite.py --dataset wikipedia --limit 10000 --use-openai

  # Fresh start (ignore previous progress)
  python scripts/ingest_elite.py --dataset wikipedia --limit 1000 --fresh
        """
    )

    parser.add_argument("--list", action="store_true", help="List available datasets")
    parser.add_argument("--status", action="store_true", help="Show ingestion status")
    parser.add_argument("--dataset", type=str, choices=list(DATASETS.keys()), help="Dataset to ingest")
    parser.add_argument("--limit", type=int, help="Limit number of documents")
    parser.add_argument("--batch-size", type=int, default=100, help="Batch size for upsert")
    parser.add_argument("--embedding-batch", type=int, default=32, help="Batch size for embeddings")
    parser.add_argument("--use-openai", action="store_true", help="Use OpenAI embeddings")
    parser.add_argument("--categories", nargs="+", help="Filter categories (arXiv)")
    parser.add_argument("--fresh", action="store_true", help="Start fresh (ignore progress)")

    args = parser.parse_args()

    if args.list:
        list_datasets()
        return

    if args.status:
        show_status()
        return

    if not args.dataset:
        parser.print_help()
        return

    # Check dependencies
    try:
        from datasets import load_dataset
        from sentence_transformers import SentenceTransformer
    except ImportError as e:
        print(f"Missing dependency: {e}")
        print("Install with: pip install datasets sentence-transformers")
        sys.exit(1)

    ingest_dataset(
        dataset_name=args.dataset,
        limit=args.limit,
        batch_size=args.batch_size,
        embedding_batch_size=args.embedding_batch,
        use_openai=args.use_openai,
        categories=args.categories,
        fresh=args.fresh
    )


if __name__ == "__main__":
    main()
