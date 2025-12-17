#!/usr/bin/env python3
"""
High-Quality Dataset Ingestion Pipeline for Knowverse.

This script downloads, processes, and ingests high-quality datasets
into Knowverse's vector database for RAG applications.

Supported datasets:
- Wikipedia (English) - Comprehensive knowledge base
- MS MARCO - Information retrieval benchmark
- Natural Questions - Google's QA dataset
- SQuAD - Stanford Question Answering Dataset
- HotpotQA - Multi-hop reasoning dataset
- BEIR - Benchmarking IR datasets

Usage:
    python scripts/ingest_datasets.py --dataset wikipedia --limit 100000
    python scripts/ingest_datasets.py --dataset msmarco --organization-id 1
    python scripts/ingest_datasets.py --list

Requirements:
    pip install datasets sentence-transformers qdrant-client tqdm
"""

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Generator, Dict, Any, List, Optional

# Dataset configurations
DATASETS = {
    "wikipedia": {
        "hf_id": "wikimedia/wikipedia",
        "hf_config": "20231101.en",
        "split": "train",
        "text_field": "text",
        "title_field": "title",
        "description": "English Wikipedia - 6M+ articles, comprehensive world knowledge",
        "size": "~20GB",
        "documents": "6,458,670",
        "trust_remote_code": False
    },
    "wikipedia-simple": {
        "hf_id": "wikimedia/wikipedia",
        "hf_config": "20231101.simple",
        "split": "train",
        "text_field": "text",
        "title_field": "title",
        "description": "Simple English Wikipedia - easier language, good for testing",
        "size": "~200MB",
        "documents": "205,328",
        "trust_remote_code": False
    },
    "msmarco": {
        "hf_id": "ms_marco",
        "hf_config": "v2.1",
        "split": "train",
        "text_field": "passages",
        "description": "MS MARCO - Microsoft's reading comprehension dataset",
        "size": "~3GB",
        "documents": "8,841,823"
    },
    "natural-questions": {
        "hf_id": "natural_questions",
        "hf_config": "default",
        "split": "train",
        "text_field": "document",
        "description": "Google Natural Questions - real user queries from Google Search",
        "size": "~42GB",
        "documents": "307,373"
    },
    "squad": {
        "hf_id": "squad",
        "hf_config": None,
        "split": "train",
        "text_field": "context",
        "title_field": "title",
        "description": "Stanford QA Dataset - reading comprehension benchmark",
        "size": "~35MB",
        "documents": "87,599"
    },
    "hotpotqa": {
        "hf_id": "hotpot_qa",
        "hf_config": "fullwiki",
        "split": "train",
        "text_field": "context",
        "description": "HotpotQA - multi-hop reasoning dataset",
        "size": "~600MB",
        "documents": "90,447"
    },
    "pubmed": {
        "hf_id": "pubmed_qa",
        "hf_config": "pqa_labeled",
        "split": "train",
        "text_field": "context",
        "description": "PubMed QA - biomedical question answering",
        "size": "~50MB",
        "documents": "1,000"
    },
    "eli5": {
        "hf_id": "eli5",
        "hf_config": None,
        "split": "train_asks",
        "text_field": "answers",
        "title_field": "title",
        "description": "ELI5 - Explain Like I'm 5, long-form QA",
        "size": "~1.5GB",
        "documents": "272,634"
    },
    "arxiv": {
        "hf_id": "ccdv/arxiv-summarization",
        "hf_config": None,
        "split": "train",
        "text_field": "article",
        "title_field": "abstract",
        "description": "ArXiv papers - scientific research abstracts and articles",
        "size": "~5GB",
        "documents": "203,037"
    },
    "stackexchange": {
        "hf_id": "flax-sentence-embeddings/stackexchange_title_body_jsonl",
        "hf_config": None,
        "split": "train",
        "text_field": "body",
        "title_field": "title",
        "description": "StackExchange Q&A - technical questions and answers",
        "size": "~8GB",
        "documents": "15,000,000+"
    }
}


def check_dependencies():
    """Check if required packages are installed."""
    required = ["datasets", "sentence_transformers", "qdrant_client", "tqdm"]
    missing = []

    for package in required:
        try:
            __import__(package)
        except ImportError:
            missing.append(package.replace("_", "-"))

    if missing:
        print(f"Missing required packages: {', '.join(missing)}")
        print(f"Install with: pip install {' '.join(missing)}")
        sys.exit(1)


def list_datasets():
    """List all available datasets."""
    print("\nAvailable Datasets for Knowverse:")
    print("=" * 80)

    for name, config in DATASETS.items():
        print(f"\n{name}:")
        print(f"  Description: {config['description']}")
        print(f"  HuggingFace: {config['hf_id']}")
        print(f"  Size: {config['size']}")
        print(f"  Documents: {config['documents']}")


def chunk_text(text: str, chunk_size: int = 450, overlap: int = 50) -> List[str]:
    """Split text into overlapping chunks."""
    words = text.split()
    chunks = []

    if len(words) <= chunk_size:
        return [text]

    i = 0
    while i < len(words):
        chunk_words = words[i:i + chunk_size]
        chunks.append(" ".join(chunk_words))
        i += chunk_size - overlap

    return chunks


def process_document(doc: Dict[str, Any], config: Dict[str, Any]) -> Generator[Dict[str, Any], None, None]:
    """Process a single document into chunks with metadata."""
    text_field = config["text_field"]
    title_field = config.get("title_field")

    # Extract text
    text = doc.get(text_field, "")
    if isinstance(text, list):
        text = " ".join(str(t) for t in text if t)
    if isinstance(text, dict):
        text = text.get("passage_text", "") or str(text)

    if not text or len(text.strip()) < 50:
        return

    # Extract title
    title = doc.get(title_field, "Untitled") if title_field else "Untitled"

    # Chunk the text
    chunks = chunk_text(text)

    for i, chunk in enumerate(chunks):
        yield {
            "content": chunk,
            "title": title,
            "chunk_index": i,
            "total_chunks": len(chunks),
            "source_dataset": config["hf_id"],
            "metadata": {
                "url": doc.get("url", ""),
                "id": doc.get("id", ""),
            }
        }


def ingest_dataset(
    dataset_name: str,
    organization_id: int,
    limit: Optional[int] = None,
    qdrant_url: str = "http://localhost:6333",
    embedding_model: str = "all-MiniLM-L6-v2",
    batch_size: int = 100
):
    """Ingest a dataset into Knowverse's vector database."""
    from datasets import load_dataset
    from sentence_transformers import SentenceTransformer
    from qdrant_client import QdrantClient
    from qdrant_client.models import Distance, VectorParams, PointStruct
    from tqdm import tqdm
    import uuid

    if dataset_name not in DATASETS:
        print(f"Unknown dataset: {dataset_name}")
        print(f"Available: {', '.join(DATASETS.keys())}")
        sys.exit(1)

    config = DATASETS[dataset_name]

    print(f"\n{'='*60}")
    print(f"Ingesting: {dataset_name}")
    print(f"Description: {config['description']}")
    print(f"Organization ID: {organization_id}")
    if limit:
        print(f"Limit: {limit} documents")
    print(f"{'='*60}\n")

    # Load embedding model
    print("Loading embedding model...")
    model = SentenceTransformer(embedding_model)
    dimension = model.get_sentence_embedding_dimension()
    print(f"Model: {embedding_model}, Dimension: {dimension}")

    # Connect to Qdrant
    print(f"Connecting to Qdrant at {qdrant_url}...")
    client = QdrantClient(url=qdrant_url)

    # Create collection
    collection_name = f"org_{organization_id}_documents"
    print(f"Collection: {collection_name}")

    try:
        client.get_collection(collection_name)
        print(f"Collection {collection_name} exists")
    except:
        print(f"Creating collection {collection_name}...")
        client.create_collection(
            collection_name=collection_name,
            vectors_config=VectorParams(size=dimension, distance=Distance.COSINE)
        )

    # Load dataset
    print(f"\nLoading dataset from HuggingFace: {config['hf_id']}...")
    trust_remote_code = config.get("trust_remote_code", True)
    if config.get("hf_config"):
        dataset = load_dataset(
            config["hf_id"],
            config["hf_config"],
            split=config["split"],
            streaming=True,
            trust_remote_code=trust_remote_code
        )
    else:
        dataset = load_dataset(
            config["hf_id"],
            split=config["split"],
            streaming=True,
            trust_remote_code=trust_remote_code
        )

    # Process and ingest
    print("\nProcessing and ingesting documents...")
    batch = []
    total_chunks = 0
    doc_count = 0

    try:
        for doc in tqdm(dataset, desc="Processing"):
            if limit and doc_count >= limit:
                break

            for chunk_data in process_document(doc, config):
                # Generate embedding
                embedding = model.encode(chunk_data["content"]).tolist()

                # Create point
                point = PointStruct(
                    id=str(uuid.uuid4()),
                    vector=embedding,
                    payload={
                        "content": chunk_data["content"],
                        "title": chunk_data["title"],
                        "chunk_index": chunk_data["chunk_index"],
                        "total_chunks": chunk_data["total_chunks"],
                        "source": chunk_data["source_dataset"],
                        "organization_id": organization_id,
                        "ingested_at": datetime.utcnow().isoformat(),
                        **chunk_data["metadata"]
                    }
                )
                batch.append(point)
                total_chunks += 1

                # Upsert batch
                if len(batch) >= batch_size:
                    client.upsert(collection_name=collection_name, points=batch)
                    batch = []

            doc_count += 1

        # Upsert remaining
        if batch:
            client.upsert(collection_name=collection_name, points=batch)

    except KeyboardInterrupt:
        print("\n\nIngestion interrupted by user.")
        if batch:
            print(f"Saving remaining {len(batch)} points...")
            client.upsert(collection_name=collection_name, points=batch)

    # Summary
    print(f"\n{'='*60}")
    print("INGESTION COMPLETE")
    print(f"{'='*60}")
    print(f"Documents processed: {doc_count}")
    print(f"Chunks created: {total_chunks}")
    print(f"Collection: {collection_name}")

    # Get collection info
    info = client.get_collection(collection_name)
    print(f"Total vectors in collection: {info.points_count}")


def export_to_jsonl(
    dataset_name: str,
    output_path: str,
    limit: Optional[int] = None
):
    """Export a dataset to JSONL format for later ingestion."""
    from datasets import load_dataset
    from tqdm import tqdm

    if dataset_name not in DATASETS:
        print(f"Unknown dataset: {dataset_name}")
        sys.exit(1)

    config = DATASETS[dataset_name]

    print(f"Exporting {dataset_name} to {output_path}...")

    trust_remote_code = config.get("trust_remote_code", True)
    if config.get("hf_config"):
        dataset = load_dataset(
            config["hf_id"],
            config["hf_config"],
            split=config["split"],
            streaming=True,
            trust_remote_code=trust_remote_code
        )
    else:
        dataset = load_dataset(
            config["hf_id"],
            split=config["split"],
            streaming=True,
            trust_remote_code=trust_remote_code
        )

    with open(output_path, 'w') as f:
        doc_count = 0
        for doc in tqdm(dataset, desc="Exporting"):
            if limit and doc_count >= limit:
                break

            for chunk_data in process_document(doc, config):
                f.write(json.dumps(chunk_data) + "\n")

            doc_count += 1

    print(f"Exported {doc_count} documents to {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Ingest high-quality datasets into Knowverse",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List available datasets
  python scripts/ingest_datasets.py --list

  # Ingest Wikipedia (first 10000 docs)
  python scripts/ingest_datasets.py --dataset wikipedia --limit 10000 --org-id 1

  # Ingest MS MARCO
  python scripts/ingest_datasets.py --dataset msmarco --org-id 1

  # Export to JSONL for later
  python scripts/ingest_datasets.py --dataset wikipedia --export wiki.jsonl --limit 1000

Available datasets:
  - wikipedia: Full English Wikipedia (6M+ articles)
  - wikipedia-simple: Simple English Wikipedia (200K articles)
  - msmarco: Microsoft MARCO passages (8M+ passages)
  - natural-questions: Google's QA dataset
  - squad: Stanford QA Dataset
  - hotpotqa: Multi-hop reasoning
  - pubmed: Biomedical QA
  - eli5: Long-form QA (Explain Like I'm 5)
  - arxiv: Scientific papers
  - stackexchange: Technical Q&A
        """
    )

    parser.add_argument("--list", action="store_true", help="List available datasets")
    parser.add_argument("--dataset", type=str, help="Dataset to ingest")
    parser.add_argument("--org-id", type=int, default=1, help="Organization ID (default: 1)")
    parser.add_argument("--limit", type=int, help="Limit number of documents to process")
    parser.add_argument("--qdrant-url", type=str, default="http://localhost:6333",
                        help="Qdrant server URL (default: http://localhost:6333)")
    parser.add_argument("--embedding-model", type=str, default="all-MiniLM-L6-v2",
                        help="Embedding model (default: all-MiniLM-L6-v2)")
    parser.add_argument("--batch-size", type=int, default=100,
                        help="Batch size for ingestion (default: 100)")
    parser.add_argument("--export", type=str, help="Export to JSONL file instead of ingesting")

    args = parser.parse_args()

    if args.list:
        list_datasets()
        return

    if not args.dataset:
        parser.print_help()
        print("\nError: --dataset is required unless using --list")
        sys.exit(1)

    check_dependencies()

    if args.export:
        export_to_jsonl(args.dataset, args.export, args.limit)
    else:
        ingest_dataset(
            dataset_name=args.dataset,
            organization_id=args.org_id,
            limit=args.limit,
            qdrant_url=args.qdrant_url,
            embedding_model=args.embedding_model,
            batch_size=args.batch_size
        )


if __name__ == "__main__":
    main()
