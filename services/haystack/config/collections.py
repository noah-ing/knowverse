"""
Collection configuration for multi-domain RAG system.

Each collection has specific settings for:
- Embedding model and dimension
- Quantization strategy
- HNSW index parameters
- Chunking settings
- Metadata schema
"""

import os
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any
from enum import Enum


class EmbeddingProvider(Enum):
    """Embedding model providers."""
    OPENAI = "openai"
    LOCAL = "local"


class QuantizationType(Enum):
    """Vector quantization strategies."""
    NONE = "none"           # Full precision (float32)
    SCALAR = "scalar"       # 4x compression, good precision
    BINARY = "binary"       # 32x compression, fast but lower precision
    PRODUCT = "product"     # Configurable compression


@dataclass
class EmbeddingConfig:
    """Configuration for embedding generation."""
    provider: EmbeddingProvider
    model_name: str
    dimension: int
    batch_size: int = 100

    # OpenAI-specific
    openai_model: Optional[str] = None  # e.g., "text-embedding-ada-002"

    # Local model specific
    local_model_path: Optional[str] = None  # e.g., "intfloat/e5-large-v2"


@dataclass
class QuantizationConfig:
    """Configuration for vector quantization."""
    type: QuantizationType
    always_ram: bool = True  # Keep quantized vectors in RAM

    # Scalar quantization
    quantile: float = 0.99

    # Product quantization
    compression_ratio: str = "x16"  # x4, x8, x16, x32, x64


@dataclass
class HNSWConfig:
    """Configuration for HNSW index."""
    m: int = 16                    # Number of edges per node
    ef_construct: int = 100        # Build-time search width
    full_scan_threshold: int = 10000
    on_disk: bool = False          # Keep index in RAM


@dataclass
class ChunkingConfig:
    """Configuration for document chunking."""
    chunk_size: int = 512          # Target chunk size in tokens
    chunk_overlap: int = 50        # Overlap between chunks
    min_chunk_size: int = 100      # Minimum chunk size
    separator: str = "\n\n"        # Primary separator


@dataclass
class CollectionConfig:
    """Full configuration for a collection."""
    name: str
    display_name: str
    description: str
    domain: str

    embedding: EmbeddingConfig
    quantization: QuantizationConfig
    hnsw: HNSWConfig
    chunking: ChunkingConfig

    # Metadata fields to index for filtering
    metadata_fields: List[str] = field(default_factory=list)

    # Priority for cross-collection search (lower = higher priority)
    search_priority: int = 1

    # Collection-specific settings
    settings: Dict[str, Any] = field(default_factory=dict)


# =============================================================================
# COLLECTION DEFINITIONS
# =============================================================================

COLLECTIONS: Dict[str, CollectionConfig] = {

    # =========================================================================
    # FINANCE DOMAIN
    # =========================================================================

    "sec_edgar": CollectionConfig(
        name="sec_edgar",
        display_name="SEC EDGAR Filings",
        description="SEC 10-K and 10-Q filings from major US companies",
        domain="finance",

        embedding=EmbeddingConfig(
            provider=EmbeddingProvider.OPENAI,
            model_name="ada-002",
            dimension=1536,
            batch_size=100,
            openai_model="text-embedding-ada-002",
        ),

        quantization=QuantizationConfig(
            type=QuantizationType.SCALAR,  # Need precision for financial data
            always_ram=True,
            quantile=0.99,
        ),

        hnsw=HNSWConfig(
            m=16,
            ef_construct=100,
            on_disk=False,
        ),

        chunking=ChunkingConfig(
            chunk_size=1000,   # Larger chunks for financial context
            chunk_overlap=200,
            min_chunk_size=200,
        ),

        metadata_fields=["company", "form_type", "filing_date", "section", "cik"],
        search_priority=1,

        settings={
            "source_url_template": "https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK={cik}",
        },
    ),

    # =========================================================================
    # GENERAL KNOWLEDGE DOMAIN
    # =========================================================================

    "wikipedia": CollectionConfig(
        name="wikipedia",
        display_name="Wikipedia",
        description="English Wikipedia articles for general knowledge",
        domain="general",

        embedding=EmbeddingConfig(
            provider=EmbeddingProvider.LOCAL,
            model_name="e5-large-v2",
            dimension=1024,
            batch_size=64,
            local_model_path="intfloat/e5-large-v2",
        ),

        quantization=QuantizationConfig(
            type=QuantizationType.BINARY,  # Scale optimization for 6M+ vectors
            always_ram=True,
        ),

        hnsw=HNSWConfig(
            m=8,           # Lower for scale
            ef_construct=64,
            on_disk=False,
        ),

        chunking=ChunkingConfig(
            chunk_size=500,
            chunk_overlap=100,
            min_chunk_size=100,
        ),

        metadata_fields=["title", "categories", "page_id", "revision_id"],
        search_priority=3,

        settings={
            "source_url_template": "https://en.wikipedia.org/wiki/{title}",
        },
    ),

    # =========================================================================
    # TECHNICAL DOMAIN
    # =========================================================================

    "stackoverflow": CollectionConfig(
        name="stackoverflow",
        display_name="Stack Overflow",
        description="Programming Q&A from Stack Overflow",
        domain="technical",

        embedding=EmbeddingConfig(
            provider=EmbeddingProvider.LOCAL,
            model_name="e5-large-v2",
            dimension=1024,
            batch_size=64,
            local_model_path="intfloat/e5-large-v2",
        ),

        quantization=QuantizationConfig(
            type=QuantizationType.BINARY,  # Scale for 15M+ vectors
            always_ram=True,
        ),

        hnsw=HNSWConfig(
            m=8,
            ef_construct=64,
            on_disk=False,
        ),

        chunking=ChunkingConfig(
            chunk_size=800,   # Code often needs more context
            chunk_overlap=100,
            min_chunk_size=150,
        ),

        metadata_fields=["question_id", "answer_id", "tags", "score", "accepted"],
        search_priority=2,

        settings={
            "source_url_template": "https://stackoverflow.com/q/{question_id}",
        },
    ),

    # =========================================================================
    # SCIENCE DOMAIN
    # =========================================================================

    "arxiv": CollectionConfig(
        name="arxiv",
        display_name="arXiv Papers",
        description="Scientific papers from arXiv",
        domain="science",

        embedding=EmbeddingConfig(
            provider=EmbeddingProvider.LOCAL,
            model_name="e5-large-v2",  # Could use SPECTER2 for better science embeddings
            dimension=1024,
            batch_size=32,
            local_model_path="intfloat/e5-large-v2",
        ),

        quantization=QuantizationConfig(
            type=QuantizationType.SCALAR,  # Need precision for scientific search
            always_ram=True,
            quantile=0.99,
        ),

        hnsw=HNSWConfig(
            m=16,
            ef_construct=100,
            on_disk=False,
        ),

        chunking=ChunkingConfig(
            chunk_size=600,
            chunk_overlap=100,
            min_chunk_size=150,
        ),

        metadata_fields=["arxiv_id", "title", "authors", "categories", "year", "abstract"],
        search_priority=2,

        settings={
            "source_url_template": "https://arxiv.org/abs/{arxiv_id}",
        },
    ),

    # =========================================================================
    # BENCHMARK DOMAIN
    # =========================================================================

    "msmarco": CollectionConfig(
        name="msmarco",
        display_name="MS MARCO",
        description="Microsoft MARCO passage ranking dataset",
        domain="benchmark",

        embedding=EmbeddingConfig(
            provider=EmbeddingProvider.LOCAL,
            model_name="e5-large-v2",
            dimension=1024,
            batch_size=64,
            local_model_path="intfloat/e5-large-v2",
        ),

        quantization=QuantizationConfig(
            type=QuantizationType.BINARY,
            always_ram=True,
        ),

        hnsw=HNSWConfig(
            m=8,
            ef_construct=64,
            on_disk=False,
        ),

        chunking=ChunkingConfig(
            chunk_size=512,
            chunk_overlap=50,
            min_chunk_size=100,
        ),

        metadata_fields=["passage_id", "query_ids"],
        search_priority=4,  # Lower priority - mainly for benchmarking

        settings={},
    ),

    # =========================================================================
    # ORGANIZATION-SPECIFIC (Template)
    # =========================================================================

    "org_documents": CollectionConfig(
        name="knowverse_org_{org_id}_embeddings",
        display_name="Organization Documents",
        description="User-uploaded documents for an organization",
        domain="custom",

        embedding=EmbeddingConfig(
            provider=EmbeddingProvider.LOCAL,
            model_name="all-mpnet-base-v2",
            dimension=768,
            batch_size=32,
            local_model_path="sentence-transformers/all-mpnet-base-v2",
        ),

        quantization=QuantizationConfig(
            type=QuantizationType.SCALAR,
            always_ram=True,
        ),

        hnsw=HNSWConfig(
            m=16,
            ef_construct=100,
            on_disk=False,
        ),

        chunking=ChunkingConfig(
            chunk_size=512,
            chunk_overlap=50,
            min_chunk_size=100,
        ),

        metadata_fields=["document_id", "title", "file_type", "uploaded_at"],
        search_priority=0,  # Highest priority - user's own data

        settings={},
    ),
}


# =============================================================================
# DOMAIN ROUTING
# =============================================================================

DOMAIN_KEYWORDS = {
    "finance": [
        "revenue", "profit", "earnings", "stock", "market", "quarterly",
        "fiscal", "dividend", "SEC", "10-K", "10-Q", "filing", "investor",
        "shareholder", "capital", "assets", "liabilities", "balance sheet",
        "income statement", "cash flow", "GAAP", "EPS", "P/E ratio",
    ],
    "science": [
        "research", "study", "experiment", "hypothesis", "theory", "data",
        "analysis", "methodology", "results", "conclusion", "abstract",
        "peer-reviewed", "citation", "journal", "arxiv", "paper", "theorem",
        "proof", "equation", "model", "simulation",
    ],
    "technical": [
        "code", "programming", "error", "bug", "fix", "implementation",
        "function", "class", "method", "API", "library", "framework",
        "database", "server", "client", "deploy", "docker", "kubernetes",
        "git", "python", "javascript", "java", "rust", "golang",
    ],
    "general": [],  # Fallback - no specific keywords
}

DOMAIN_TO_COLLECTIONS = {
    "finance": ["sec_edgar"],
    "science": ["arxiv"],
    "technical": ["stackoverflow"],
    "general": ["wikipedia"],
    "benchmark": ["msmarco"],
    "custom": ["org_documents"],
}


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def get_collection_config(name: str) -> Optional[CollectionConfig]:
    """Get configuration for a collection by name."""
    return COLLECTIONS.get(name)


def get_collections_for_domain(domain: str) -> List[CollectionConfig]:
    """Get all collections for a domain."""
    collection_names = DOMAIN_TO_COLLECTIONS.get(domain, [])
    return [COLLECTIONS[name] for name in collection_names if name in COLLECTIONS]


def get_all_collections() -> List[CollectionConfig]:
    """Get all collection configurations."""
    return list(COLLECTIONS.values())


def get_qdrant_collection_name(config: CollectionConfig, org_id: Optional[int] = None) -> str:
    """
    Get the actual Qdrant collection name.

    Handles org-specific collection naming.
    """
    if "{org_id}" in config.name and org_id:
        return config.name.format(org_id=org_id)
    return config.name


def get_collection_for_existing_data(org_id: int) -> str:
    """
    Get collection name for existing SEC EDGAR data.

    The existing data uses: org_{org_id}_v1_ada002
    """
    return f"org_{org_id}_v1_ada002"


# =============================================================================
# QDRANT COLLECTION CREATION PARAMS
# =============================================================================

def get_qdrant_create_params(config: CollectionConfig) -> Dict[str, Any]:
    """
    Generate Qdrant collection creation parameters from config.
    """
    params = {
        "vectors_config": {
            "size": config.embedding.dimension,
            "distance": "Cosine",
        },
        "hnsw_config": {
            "m": config.hnsw.m,
            "ef_construct": config.hnsw.ef_construct,
            "full_scan_threshold": config.hnsw.full_scan_threshold,
            "on_disk": config.hnsw.on_disk,
        },
        "on_disk_payload": True,
    }

    # Add quantization config
    if config.quantization.type == QuantizationType.SCALAR:
        params["quantization_config"] = {
            "scalar": {
                "type": "int8",
                "quantile": config.quantization.quantile,
                "always_ram": config.quantization.always_ram,
            }
        }
    elif config.quantization.type == QuantizationType.BINARY:
        params["quantization_config"] = {
            "binary": {
                "always_ram": config.quantization.always_ram,
            }
        }
    elif config.quantization.type == QuantizationType.PRODUCT:
        params["quantization_config"] = {
            "product": {
                "compression": config.quantization.compression_ratio,
                "always_ram": config.quantization.always_ram,
            }
        }

    return params


# =============================================================================
# MEMORY ESTIMATION
# =============================================================================

def estimate_memory_usage(
    num_vectors: int,
    config: CollectionConfig
) -> Dict[str, str]:
    """
    Estimate memory usage for a collection.

    Returns human-readable memory estimates.
    """
    dim = config.embedding.dimension

    # Base vector size (float32)
    raw_size_bytes = num_vectors * dim * 4

    # Quantized sizes
    if config.quantization.type == QuantizationType.BINARY:
        quantized_size = num_vectors * (dim // 8)  # 1 bit per dimension
        compression = "32x"
    elif config.quantization.type == QuantizationType.SCALAR:
        quantized_size = num_vectors * dim  # 1 byte per dimension
        compression = "4x"
    elif config.quantization.type == QuantizationType.PRODUCT:
        # Depends on compression ratio, approximate
        ratio = int(config.quantization.compression_ratio.replace("x", ""))
        quantized_size = raw_size_bytes // ratio
        compression = config.quantization.compression_ratio
    else:
        quantized_size = raw_size_bytes
        compression = "1x"

    # HNSW index overhead (~20-30% typically)
    index_overhead = int(quantized_size * 0.25)

    total = quantized_size + index_overhead

    def format_bytes(b: int) -> str:
        if b >= 1e9:
            return f"{b/1e9:.1f} GB"
        elif b >= 1e6:
            return f"{b/1e6:.1f} MB"
        else:
            return f"{b/1e3:.1f} KB"

    return {
        "raw_vectors": format_bytes(raw_size_bytes),
        "quantized_vectors": format_bytes(quantized_size),
        "compression": compression,
        "index_overhead": format_bytes(index_overhead),
        "total_estimated": format_bytes(total),
    }
