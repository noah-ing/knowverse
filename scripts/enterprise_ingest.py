#!/usr/bin/env python3
"""
Enterprise Document Ingestion Pipeline for Knowverse.

Architecture:
- OpenAI embeddings (ada-002, 1536d) for development
- Versioned collections: org_{id}_v{version}_{model}
- Recursive chunking (400-512 tokens, 10-15% overlap)
- Position metadata for context reconstruction
- Source tagging for filtering

Supported datasets:
- SEC EDGAR 10-K/10-Q filings (HTML versions for narrative flow)
- Enron email corpus
- CORD-19 scientific papers
- Wikipedia (for baseline testing)

Usage:
    python scripts/enterprise_ingest.py --dataset sec-edgar --years 5
    python scripts/enterprise_ingest.py --dataset enron --limit 10000
    python scripts/enterprise_ingest.py --list
"""

import argparse
import json
import os
import sys
import hashlib
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Generator, Dict, Any, List, Optional, Tuple
from dataclasses import dataclass, field
import time

# Load environment
from dotenv import load_dotenv
load_dotenv()

# Configuration
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
QDRANT_URL = os.getenv("QDRANT_URL", "http://localhost:6333")
STORAGE_PATH = os.getenv("STORAGE_PATH", "/Volumes/monster/knowverse")
PROGRESS_DIR = Path(STORAGE_PATH) / "ingestion_progress"

# Embedding models
EMBEDDING_MODELS = {
    "openai": {
        "name": "text-embedding-ada-002",
        "dimension": 1536,
        "max_tokens": 8191,
        "cost_per_1k": 0.0001  # $0.0001 per 1K tokens
    },
    "openai-3-small": {
        "name": "text-embedding-3-small",
        "dimension": 1536,
        "max_tokens": 8191,
        "cost_per_1k": 0.00002
    },
    "openai-3-large": {
        "name": "text-embedding-3-large",
        "dimension": 3072,
        "max_tokens": 8191,
        "cost_per_1k": 0.00013
    },
    "local-minilm": {
        "name": "all-MiniLM-L6-v2",
        "dimension": 384,
        "max_tokens": 512,
        "cost_per_1k": 0
    }
}

# Dataset configurations
DATASETS = {
    "sec-edgar": {
        "description": "SEC EDGAR 10-K/10-Q filings - financial narratives",
        "source": "sec.gov",
        "forms": ["10-K", "10-Q"],
        "estimated_docs": "~320,000 (10 years)",
    },
    "enron": {
        "hf_id": "aeslc",  # Enron email subset on HF
        "description": "Enron email corpus - enterprise communications",
        "source": "huggingface",
        "estimated_docs": "~500,000",
    },
    "cord19": {
        "hf_id": "allenai/cord19",
        "description": "COVID-19 scientific papers",
        "source": "huggingface",
        "estimated_docs": "~400,000",
    },
    "wikipedia": {
        "hf_id": "wikimedia/wikipedia",
        "hf_config": "20231101.en",
        "description": "English Wikipedia articles",
        "source": "huggingface",
        "estimated_docs": "~6,500,000",
    }
}


@dataclass
class Chunk:
    """Represents a document chunk with position metadata."""
    text: str
    chunk_index: int
    total_chunks: int
    start_char: int
    end_char: int
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class EmbeddingResult:
    """Result of embedding generation."""
    vector: List[float]
    model: str
    tokens_used: int


class ProgressTracker:
    """
    Track ingestion progress for resume capability.

    Logs processed accession numbers to a JSON file.
    Enables clean resume if ingestion dies mid-run.
    """

    def __init__(self, dataset: str, org_id: int, version: int):
        self.dataset = dataset
        self.org_id = org_id
        self.version = version

        # Create progress directory
        PROGRESS_DIR.mkdir(parents=True, exist_ok=True)

        # Progress file path
        self.progress_file = PROGRESS_DIR / f"{dataset}_org{org_id}_v{version}.json"

        # Load existing progress
        self.processed: Dict[str, Dict[str, Any]] = {}
        self.stats = {
            "started_at": None,
            "last_updated": None,
            "total_docs": 0,
            "total_chunks": 0,
            "total_tokens": 0,
            "estimated_cost": 0.0
        }
        self._load()

    def _load(self):
        """Load existing progress from file."""
        if self.progress_file.exists():
            try:
                with open(self.progress_file, 'r') as f:
                    data = json.load(f)
                    self.processed = data.get("processed", {})
                    self.stats = data.get("stats", self.stats)
                    print(f"Resuming from progress file: {len(self.processed)} filings already processed")
            except Exception as e:
                print(f"Warning: Could not load progress file: {e}")

    def _save(self):
        """Save progress to file."""
        self.stats["last_updated"] = datetime.now(timezone.utc).isoformat()

        data = {
            "dataset": self.dataset,
            "org_id": self.org_id,
            "version": self.version,
            "stats": self.stats,
            "processed": self.processed
        }

        # Write atomically (write to temp then rename)
        temp_file = self.progress_file.with_suffix('.tmp')
        with open(temp_file, 'w') as f:
            json.dump(data, f, indent=2)
        temp_file.rename(self.progress_file)

    def is_processed(self, accession: str) -> bool:
        """Check if an accession number has been processed."""
        return accession in self.processed

    def mark_processed(self, accession: str, metadata: Dict[str, Any], chunks: int, tokens: int, cost: float):
        """Mark an accession as processed and save progress."""
        self.processed[accession] = {
            "processed_at": datetime.now(timezone.utc).isoformat(),
            "chunks": chunks,
            "tokens": tokens,
            **metadata
        }

        # Update stats
        if self.stats["started_at"] is None:
            self.stats["started_at"] = datetime.now(timezone.utc).isoformat()
        self.stats["total_docs"] += 1
        self.stats["total_chunks"] += chunks
        self.stats["total_tokens"] += tokens
        self.stats["estimated_cost"] += cost

        # Save every 10 documents
        if self.stats["total_docs"] % 10 == 0:
            self._save()

    def finalize(self):
        """Save final progress."""
        self._save()

    def get_summary(self) -> str:
        """Get progress summary string."""
        return (
            f"Progress: {self.stats['total_docs']} docs, "
            f"{self.stats['total_chunks']} chunks, "
            f"{self.stats['total_tokens']:,} tokens, "
            f"${self.stats['estimated_cost']:.4f}"
        )


class RecursiveChunker:
    """
    Recursive character splitter with semantic awareness.

    Tries paragraph breaks first, then sentences, then words.
    Preserves position metadata for context reconstruction.
    """

    def __init__(
        self,
        chunk_size: int = 450,  # tokens (approx 4 chars per token)
        chunk_overlap: int = 50,  # ~11% overlap
        length_function: str = "tokens"
    ):
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap
        self.chars_per_token = 4  # Approximate

        # Separators in order of preference
        self.separators = [
            "\n\n\n",      # Section breaks
            "\n\n",        # Paragraphs
            "\n",          # Lines
            ". ",          # Sentences
            "! ",
            "? ",
            "; ",
            ", ",          # Clauses
            " ",           # Words
            ""             # Characters (last resort)
        ]

    def chunk(self, text: str, metadata: Dict[str, Any] = None) -> List[Chunk]:
        """Split text into chunks with position tracking."""
        if not text or not text.strip():
            return []

        metadata = metadata or {}
        chunks = []

        # Estimate chunk size in characters
        char_chunk_size = self.chunk_size * self.chars_per_token
        char_overlap = self.chunk_overlap * self.chars_per_token

        # Split recursively
        raw_chunks = self._split_recursive(text, char_chunk_size, char_overlap)

        # Track positions
        current_pos = 0
        for i, chunk_text in enumerate(raw_chunks):
            # Find actual position in original text
            start_pos = text.find(chunk_text, current_pos)
            if start_pos == -1:
                start_pos = current_pos
            end_pos = start_pos + len(chunk_text)

            chunks.append(Chunk(
                text=chunk_text.strip(),
                chunk_index=i,
                total_chunks=len(raw_chunks),
                start_char=start_pos,
                end_char=end_pos,
                metadata=metadata.copy()
            ))

            # Move position forward (accounting for overlap)
            current_pos = max(current_pos, end_pos - char_overlap)

        return chunks

    def _split_recursive(
        self,
        text: str,
        chunk_size: int,
        overlap: int,
        separators: List[str] = None
    ) -> List[str]:
        """Recursively split text using separator hierarchy."""
        separators = separators or self.separators

        if not text:
            return []

        # If text fits in chunk, return it
        if len(text) <= chunk_size:
            return [text] if text.strip() else []

        # Find best separator
        separator = separators[-1]  # Default to last (most granular)
        for sep in separators:
            if sep in text:
                separator = sep
                break

        # Split by separator
        if separator:
            parts = text.split(separator)
        else:
            # Character-level split (last resort)
            parts = [text[i:i+chunk_size] for i in range(0, len(text), chunk_size - overlap)]
            return parts

        # Merge small parts into chunks
        chunks = []
        current_chunk = []
        current_length = 0

        for part in parts:
            part_length = len(part) + len(separator)

            if current_length + part_length <= chunk_size:
                current_chunk.append(part)
                current_length += part_length
            else:
                # Save current chunk
                if current_chunk:
                    chunks.append(separator.join(current_chunk))

                # Handle oversized parts
                if part_length > chunk_size:
                    # Recursively split with finer separators
                    remaining_separators = separators[separators.index(separator) + 1:] if separator in separators else separators[-1:]
                    sub_chunks = self._split_recursive(part, chunk_size, overlap, remaining_separators)
                    chunks.extend(sub_chunks)
                    current_chunk = []
                    current_length = 0
                else:
                    current_chunk = [part]
                    current_length = part_length

        # Don't forget last chunk
        if current_chunk:
            chunks.append(separator.join(current_chunk))

        return chunks


class OpenAIEmbedder:
    """OpenAI embedding client with batching and rate limiting."""

    def __init__(self, model: str = "openai"):
        self.config = EMBEDDING_MODELS[model]
        self.model_name = self.config["name"]
        self.dimension = self.config["dimension"]
        self.api_key = OPENAI_API_KEY

        if not self.api_key:
            raise ValueError("OPENAI_API_KEY not set in environment")

        # Rate limiting
        self.requests_per_minute = 3000
        self.tokens_per_minute = 1000000
        self.last_request_time = 0
        self.tokens_used_this_minute = 0

        # Stats
        self.total_tokens = 0
        self.total_requests = 0

    def embed(self, text: str) -> EmbeddingResult:
        """Generate embedding for a single text."""
        return self.embed_batch([text])[0]

    def embed_batch(self, texts: List[str], batch_size: int = 100) -> List[EmbeddingResult]:
        """Generate embeddings for multiple texts with batching."""
        import openai

        client = openai.OpenAI(api_key=self.api_key)
        results = []

        for i in range(0, len(texts), batch_size):
            batch = texts[i:i + batch_size]

            # Simple rate limiting
            time.sleep(0.1)

            try:
                response = client.embeddings.create(
                    model=self.model_name,
                    input=batch
                )

                for j, embedding_data in enumerate(response.data):
                    results.append(EmbeddingResult(
                        vector=embedding_data.embedding,
                        model=self.model_name,
                        tokens_used=response.usage.total_tokens // len(batch)
                    ))

                self.total_tokens += response.usage.total_tokens
                self.total_requests += 1

            except Exception as e:
                print(f"Embedding error: {e}")
                # Return zero vectors for failed batch
                for _ in batch:
                    results.append(EmbeddingResult(
                        vector=[0.0] * self.dimension,
                        model=self.model_name,
                        tokens_used=0
                    ))

        return results

    def get_cost_estimate(self) -> float:
        """Estimate cost based on tokens used."""
        return (self.total_tokens / 1000) * self.config["cost_per_1k"]


class QdrantStore:
    """Qdrant vector store with versioned collections."""

    def __init__(self, url: str = QDRANT_URL):
        from qdrant_client import QdrantClient
        from qdrant_client.models import Distance, VectorParams

        self.client = QdrantClient(url=url, timeout=60, check_compatibility=False)
        self.Distance = Distance
        self.VectorParams = VectorParams

    def collection_name(self, org_id: int, version: int, model: str) -> str:
        """Generate versioned collection name."""
        model_short = model.replace("text-embedding-", "").replace("-", "")
        return f"org_{org_id}_v{version}_{model_short}"

    def ensure_collection(self, name: str, dimension: int):
        """Create collection if it doesn't exist."""
        from qdrant_client.models import Distance, VectorParams

        try:
            self.client.get_collection(name)
            print(f"Collection {name} exists")
        except:
            print(f"Creating collection {name} (dim={dimension})...")
            self.client.create_collection(
                collection_name=name,
                vectors_config=VectorParams(size=dimension, distance=Distance.COSINE)
            )

    def upsert_batch(self, collection: str, points: List[Dict]) -> int:
        """Upsert a batch of points."""
        from qdrant_client.models import PointStruct

        qdrant_points = [
            PointStruct(
                id=p["id"],
                vector=p["vector"],
                payload=p["payload"]
            )
            for p in points
        ]

        self.client.upsert(collection_name=collection, points=qdrant_points)
        return len(qdrant_points)

    def get_count(self, collection: str) -> int:
        """Get point count in collection."""
        try:
            info = self.client.get_collection(collection)
            return info.points_count
        except:
            return 0


class SECEdgarFetcher:
    """
    Fetch SEC EDGAR 10-K and 10-Q filings.

    Uses SEC's full-text search API and EDGAR archives.
    Fetches HTML versions for narrative flow (not XBRL).
    """

    BASE_URL = "https://www.sec.gov"
    SEARCH_URL = "https://efts.sec.gov/LATEST/search-index"

    def __init__(self, forms: List[str] = None, years: int = 5):
        self.forms = forms or ["10-K", "10-Q"]
        self.years = years
        self.user_agent = "Knowverse Research contact@knowverse.ai"

    def fetch_filings(self, limit: int = None) -> Generator[Dict[str, Any], None, None]:
        """
        Fetch filings from SEC EDGAR.

        Yields filing metadata and content.
        """
        import requests

        headers = {"User-Agent": self.user_agent}
        count = 0

        # Sample companies (top by market cap)
        sample_ciks = [
            "0000320193",  # Apple
            "0000789019",  # Microsoft
            "0001652044",  # Alphabet
            "0001018724",  # Amazon
            "0001326801",  # Meta
            "0001045810",  # NVIDIA
            "0000051143",  # IBM
            "0000078003",  # Pfizer
            "0000034088",  # Exxon
            "0000019617",  # JPMorgan
        ]

        for cik in sample_ciks:
            if limit and count >= limit:
                return

            try:
                # Fetch company submissions
                submissions_url = f"https://data.sec.gov/submissions/CIK{cik.zfill(10)}.json"
                sub_resp = requests.get(submissions_url, headers=headers)

                if sub_resp.status_code != 200:
                    print(f"  Failed to fetch {cik}: {sub_resp.status_code}")
                    continue

                data = sub_resp.json()
                company_name = data.get("name", "Unknown")
                print(f"\n  {company_name} ({cik})")

                # Get recent filings
                recent = data.get("filings", {}).get("recent", {})
                forms_list = recent.get("form", [])
                accessions = recent.get("accessionNumber", [])
                dates = recent.get("filingDate", [])
                docs = recent.get("primaryDocument", [])

                # Process each filing
                for i, form in enumerate(forms_list):
                    if form not in self.forms:
                        continue

                    if limit and count >= limit:
                        return

                    accession = accessions[i].replace("-", "")
                    doc_name = docs[i]
                    filing_date = dates[i]

                    # Build document URL (CIK without leading zeros)
                    cik_num = cik.lstrip("0")
                    doc_url = f"{self.BASE_URL}/Archives/edgar/data/{cik_num}/{accession}/{doc_name}"

                    try:
                        doc_resp = requests.get(doc_url, headers=headers)
                        time.sleep(0.15)  # Rate limiting (SEC allows 10 req/sec)

                        if doc_resp.status_code == 200:
                            content = self._extract_text_from_html(doc_resp.text)

                            if len(content) > 1000:
                                yield {
                                    "id": f"sec_{cik}_{accession}",
                                    "content": content,
                                    "title": f"{company_name} {form} {filing_date}",
                                    "metadata": {
                                        "source": "sec_edgar",
                                        "form_type": form,
                                        "cik": cik,
                                        "company": company_name,
                                        "filing_date": filing_date,
                                        "accession": accessions[i],
                                        "url": doc_url
                                    }
                                }
                                count += 1
                                print(f"    {form} {filing_date} - {len(content):,} chars")

                    except Exception as e:
                        print(f"    Error: {e}")
                        continue

            except Exception as e:
                print(f"  Error processing {cik}: {e}")
                continue

            time.sleep(0.2)  # Be nice to SEC servers

    def _extract_text_from_html(self, html: str) -> str:
        """Extract clean text from SEC filing HTML."""
        from html.parser import HTMLParser
        import re

        class TextExtractor(HTMLParser):
            def __init__(self):
                super().__init__()
                self.text_parts = []
                self.skip_tags = {'script', 'style', 'head', 'meta', 'link'}
                self.current_tag = None

            def handle_starttag(self, tag, attrs):
                self.current_tag = tag.lower()

            def handle_endtag(self, tag):
                self.current_tag = None

            def handle_data(self, data):
                if self.current_tag not in self.skip_tags:
                    text = data.strip()
                    if text:
                        self.text_parts.append(text)

        try:
            parser = TextExtractor()
            parser.feed(html)
            text = " ".join(parser.text_parts)

            # Clean up
            text = re.sub(r'\s+', ' ', text)
            text = re.sub(r'[^\x00-\x7F]+', ' ', text)  # Remove non-ASCII

            return text.strip()
        except:
            return ""


def ingest_sec_edgar(
    org_id: int = 1,
    version: int = 1,
    model: str = "openai",
    years: int = 5,
    limit: int = None,
    batch_size: int = 50,
    fresh: bool = False
):
    """Ingest SEC EDGAR 10-K/10-Q filings with resume capability."""

    print("\n" + "=" * 60)
    print("SEC EDGAR INGESTION")
    print("=" * 60)
    print(f"Organization: {org_id}")
    print(f"Model: {model} ({EMBEDDING_MODELS[model]['dimension']}d)")
    print(f"Years: {years}")
    print(f"Limit: {limit or 'None'}")
    print(f"Fresh start: {fresh}")
    print("=" * 60 + "\n")

    # Initialize components
    chunker = RecursiveChunker(chunk_size=450, chunk_overlap=50)
    embedder = OpenAIEmbedder(model=model)
    store = QdrantStore()
    fetcher = SECEdgarFetcher(years=years)

    # Initialize progress tracker
    progress = ProgressTracker("sec-edgar", org_id, version)
    if fresh and progress.progress_file.exists():
        print("Fresh start requested - clearing progress file")
        progress.progress_file.unlink()
        progress = ProgressTracker("sec-edgar", org_id, version)

    # Create collection
    collection = store.collection_name(org_id, version, embedder.model_name)
    store.ensure_collection(collection, embedder.dimension)

    # Process filings
    batch = []
    session_chunks = 0
    session_docs = 0
    skipped_docs = 0

    try:
        for filing in fetcher.fetch_filings(limit=limit):
            accession = filing["metadata"].get("accession", filing["id"])

            # Skip if already processed
            if progress.is_processed(accession):
                skipped_docs += 1
                continue

            # Chunk the document
            chunks = chunker.chunk(
                filing["content"],
                metadata={
                    "doc_id": filing["id"],
                    "title": filing["title"],
                    **filing["metadata"]
                }
            )

            if not chunks:
                continue

            # Generate embeddings
            chunk_texts = [c.text for c in chunks]
            embeddings = embedder.embed_batch(chunk_texts)

            # Calculate tokens used for this filing
            filing_tokens = sum(e.tokens_used for e in embeddings)
            filing_cost = (filing_tokens / 1000) * EMBEDDING_MODELS[model]["cost_per_1k"]

            # Build points
            for chunk, embedding in zip(chunks, embeddings):
                point_id = hashlib.md5(
                    f"{filing['id']}_{chunk.chunk_index}".encode()
                ).hexdigest()

                batch.append({
                    "id": point_id,
                    "vector": embedding.vector,
                    "payload": {
                        "content": chunk.text,
                        "chunk_index": chunk.chunk_index,
                        "total_chunks": chunk.total_chunks,
                        "start_char": chunk.start_char,
                        "end_char": chunk.end_char,
                        "organization_id": org_id,
                        "source": "sec_edgar",
                        "ingested_at": datetime.now(timezone.utc).isoformat(),
                        **chunk.metadata
                    }
                })
                session_chunks += 1

            session_docs += 1

            # Upsert batch
            if len(batch) >= batch_size:
                store.upsert_batch(collection, batch)
                batch = []

            # Mark as processed (after successful upsert)
            progress.mark_processed(
                accession=accession,
                metadata={
                    "company": filing["metadata"].get("company"),
                    "form_type": filing["metadata"].get("form_type"),
                    "filing_date": filing["metadata"].get("filing_date")
                },
                chunks=len(chunks),
                tokens=filing_tokens,
                cost=filing_cost
            )

            # Progress update every 5 docs
            if session_docs % 5 == 0:
                print(f"  {progress.get_summary()}")

    except KeyboardInterrupt:
        print("\n\nIngestion interrupted - saving progress...")
    except Exception as e:
        print(f"\nError during ingestion: {e}")
        print("Progress has been saved - run again to resume")
    finally:
        # Final batch
        if batch:
            store.upsert_batch(collection, batch)

        # Save progress
        progress.finalize()

    # Summary
    print("\n" + "=" * 60)
    print("INGESTION SUMMARY")
    print("=" * 60)
    print(f"Session docs processed: {session_docs}")
    print(f"Session chunks created: {session_chunks}")
    print(f"Skipped (already done): {skipped_docs}")
    print(f"\nTotal progress:")
    print(f"  Documents: {progress.stats['total_docs']}")
    print(f"  Chunks: {progress.stats['total_chunks']}")
    print(f"  Tokens: {progress.stats['total_tokens']:,}")
    print(f"  Cost: ${progress.stats['estimated_cost']:.4f}")
    print(f"\nCollection: {collection}")
    print(f"Vectors: {store.get_count(collection)}")
    print(f"Progress file: {progress.progress_file}")
    print("=" * 60)


def list_datasets():
    """List available datasets."""
    print("\n" + "=" * 60)
    print("AVAILABLE DATASETS")
    print("=" * 60)

    for name, config in DATASETS.items():
        print(f"\n{name}:")
        print(f"  {config['description']}")
        print(f"  Source: {config['source']}")
        print(f"  Estimated: {config['estimated_docs']}")

    print("\n" + "=" * 60)
    print("EMBEDDING MODELS")
    print("=" * 60)

    for name, config in EMBEDDING_MODELS.items():
        cost_str = f"${config['cost_per_1k']}/1K tokens" if config['cost_per_1k'] > 0 else "Free (local)"
        print(f"\n{name}:")
        print(f"  Model: {config['name']}")
        print(f"  Dimension: {config['dimension']}")
        print(f"  Cost: {cost_str}")


def main():
    parser = argparse.ArgumentParser(
        description="Enterprise document ingestion for Knowverse",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List available datasets and models
  python scripts/enterprise_ingest.py --list

  # Ingest SEC EDGAR filings (10-K/10-Q)
  python scripts/enterprise_ingest.py --dataset sec-edgar --years 5 --limit 100

  # Ingest with specific model version
  python scripts/enterprise_ingest.py --dataset sec-edgar --model openai-3-small --version 2
        """
    )

    parser.add_argument("--list", action="store_true", help="List datasets and models")
    parser.add_argument("--dataset", type=str, choices=list(DATASETS.keys()), help="Dataset to ingest")
    parser.add_argument("--model", type=str, default="openai", choices=list(EMBEDDING_MODELS.keys()), help="Embedding model")
    parser.add_argument("--org-id", type=int, default=1, help="Organization ID")
    parser.add_argument("--version", type=int, default=1, help="Collection version")
    parser.add_argument("--years", type=int, default=5, help="Years of data (SEC)")
    parser.add_argument("--limit", type=int, help="Limit documents")
    parser.add_argument("--batch-size", type=int, default=50, help="Batch size")
    parser.add_argument("--fresh", action="store_true", help="Start fresh (ignore progress file)")

    args = parser.parse_args()

    if args.list:
        list_datasets()
        return

    if not args.dataset:
        parser.print_help()
        return

    # Check dependencies
    try:
        import openai
        import requests
        from qdrant_client import QdrantClient
    except ImportError as e:
        print(f"Missing dependency: {e}")
        print("Install with: pip install openai requests qdrant-client python-dotenv")
        sys.exit(1)

    # Route to appropriate ingestion
    if args.dataset == "sec-edgar":
        ingest_sec_edgar(
            org_id=args.org_id,
            version=args.version,
            model=args.model,
            years=args.years,
            limit=args.limit,
            batch_size=args.batch_size,
            fresh=args.fresh
        )
    else:
        print(f"Dataset {args.dataset} not yet implemented")
        print("Currently supported: sec-edgar")


if __name__ == "__main__":
    main()
