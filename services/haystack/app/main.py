import logging
import tempfile
import os
from fastapi import FastAPI, Depends, HTTPException, status, BackgroundTasks, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from typing import Dict, List, Optional, Any, Union, Tuple
import numpy as np
import time
import json
import asyncio

# Import custom modules
from app.document_store import get_document_store
from app.embeddings import (
    get_embedding_model, generate_embeddings, detect_query_domain,
    get_available_domains, fine_tune_domain_model, model_registry
)
from app.search import get_retriever, get_search_pipeline, get_qa_pipeline, get_hybrid_searcher
from app.visualization import DimensionReduction, ClusterAnalysis
from app.query_parser import QueryParser
from app.retrieval import retrieve_and_rank, get_context_retriever
from app.generation import llm_registry
from app.health import router as health_router

# Import elite RAG modules
from app.query_understanding import analyze_query, QueryAnalysis, QueryIntent
from app.advanced_retrieval import (
    AdvancedRetriever, RAGFusion, CrossEncoderReranker,
    RetrievalConfig, RetrievalResult
)
from app.quality import check_response_quality, QualityReport
from app.memory import get_memory_manager

# Import settings
from config.settings import DEBUG, ENVIRONMENT, DEFAULT_DOMAIN, EMBEDDING_MODELS

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("haystack_service")

# Create FastAPI app
app = FastAPI(
    title="KnowVerse Haystack Service",
    description="API for document processing, embedding generation, and semantic search",
    version="1.1.0",
    debug=DEBUG
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For production, specify domains
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include health router for comprehensive health checks
app.include_router(health_router, tags=["health"])

# Domain-specific models and endpoints
class DomainInfo(BaseModel):
    domain: str = Field(..., description="Domain name")
    description: Optional[str] = Field(None, description="Domain description")
    model_count: int = Field(0, description="Number of models in this domain")

class DomainEmbeddingModel(BaseModel):
    name: str = Field(..., description="Model name")
    domain: str = Field(..., description="Domain name")
    base_model: str = Field(..., description="Base model name")
    dimension: int = Field(..., description="Vector dimension")
    version: Optional[str] = Field(None, description="Model version")
    performance_metrics: Optional[Dict[str, Any]] = Field(None, description="Performance metrics")
    
class DomainDetectionRequest(BaseModel):
    query: str = Field(..., description="Query text to detect domain")
    organization_id: int = Field(..., description="Organization ID for tenant isolation")

class DomainDetectionResponse(BaseModel):
    domain: str = Field(..., description="Detected domain")
    confidence: float = Field(..., description="Confidence score (0.0-1.0)")
    alternatives: Optional[Dict[str, float]] = Field(None, description="Alternative domains with confidence scores")
    processing_time: float = Field(..., description="Processing time in seconds")

class DomainEmbeddingRequest(BaseModel):
    text: str = Field(..., description="Text content to generate embeddings for")
    model_name: str = Field("base", description="Model name (mini, small, base, large, xl)")
    domain: str = Field(DEFAULT_DOMAIN, description="Domain name")
    organization_id: Optional[int] = Field(None, description="Organization ID for tenant isolation")

class DomainModelFineTuneRequest(BaseModel):
    domain: str = Field(..., description="Domain name")
    base_model: str = Field("base", description="Base model to fine-tune")
    organization_id: int = Field(..., description="Organization ID for tenant isolation")
    training_data: List[Tuple[str, str, float]] = Field(..., description="List of tuples (text1, text2, similarity_score)")
    name: str = Field(..., description="Model name")
    description: Optional[str] = Field(None, description="Model description")

class DomainModelFineTuneResponse(BaseModel):
    status: str = Field(..., description="Status of fine-tuning (success, error)")
    model_path: Optional[str] = Field(None, description="Path to fine-tuned model")
    metrics: Dict[str, Any] = Field(default_factory=dict, description="Fine-tuning metrics")
    processing_time: float = Field(..., description="Processing time in seconds")

# Request models
class EmbeddingRequest(BaseModel):
    text: str = Field(..., description="Text content to generate embeddings for")
    model_name: Optional[str] = Field("base", description="Embedding model to use (mini, small, base, large, xl)")

class DocumentRequest(BaseModel):
    content: str = Field(..., description="Document content to index")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Document metadata")
    
class RAGRequest(BaseModel):
    query: str = Field(..., description="Question or query for RAG")
    org_id: int = Field(..., description="Organization ID for tenant isolation")
    provider: Optional[str] = Field(default=None, description="LLM provider name (openai, anthropic, local)")
    retrieval_options: Dict[str, Any] = Field(default_factory=dict, description="Options for document retrieval")
    generation_options: Dict[str, Any] = Field(default_factory=dict, description="Options for response generation")


class AgentRAGRequest(BaseModel):
    """Request model for agentic RAG with tool use."""
    query: str = Field(..., description="Question or query for the agent")
    org_id: int = Field(..., description="Organization ID for tenant isolation")
    session_id: Optional[str] = Field(default=None, description="Session ID for conversation context")
    mode: Optional[str] = Field(default="auto", description="Agent mode: auto, react, deep_research, plan_execute")
    provider: Optional[str] = Field(default=None, description="LLM provider name")
    max_iterations: int = Field(default=10, description="Maximum reasoning iterations")
    include_trace: bool = Field(default=True, description="Include execution trace in response")
    temperature: float = Field(default=0.7, description="LLM temperature")
    max_tokens: int = Field(default=1000, description="Maximum tokens for response")
    system_prompt: Optional[str] = Field(default=None, description="Custom system prompt")
    conversation_history: Optional[List[Dict[str, str]]] = Field(default=None, description="Previous conversation messages")


class SearchRequest(BaseModel):
    query: str = Field(..., description="Search query")
    filters: Optional[Dict[str, Any]] = Field(default=None, description="Search filters")
    top_k: int = Field(default=10, description="Number of results to return")

class HybridSearchRequest(BaseModel):
    query: str = Field(..., description="Search query")
    filters: Optional[Dict[str, Any]] = Field(default=None, description="Search filters")
    top_k: int = Field(default=10, description="Number of results to return")
    vector_weight: Optional[float] = Field(default=None, description="Weight for vector search (0.0-1.0)")
    keyword_weight: Optional[float] = Field(default=None, description="Weight for keyword search (0.0-1.0)")
    early_termination: bool = Field(default=True, description="Whether to use early termination optimization")

class ParseQueryRequest(BaseModel):
    query: str = Field(..., description="Query text to parse")

class QuestionRequest(BaseModel):
    question: str = Field(..., description="Question to answer")
    filters: Optional[Dict[str, Any]] = Field(default=None, description="Search filters")

# Response models
class HealthResponse(BaseModel):
    status: str
    version: str
    environment: str
    
class RAGContextItem(BaseModel):
    document_id: Optional[str] = None
    title: Optional[str] = None
    source: Optional[str] = None
    text: str
    score: float
    
class RAGResponse(BaseModel):
    answer: str
    context: List[RAGContextItem]
    metadata: Dict[str, Any]
    query: str
    processing_time: float


# Advanced RAG request/response models
class AdvancedRAGRequest(BaseModel):
    """Request for advanced RAG with elite features."""
    query: str = Field(..., description="Question or query for RAG")
    org_id: int = Field(..., description="Organization ID for tenant isolation")
    session_id: Optional[str] = Field(None, description="Session ID for memory/conversation context")

    # Retrieval strategy
    strategy: str = Field(
        default="auto",
        description="Retrieval strategy: auto, basic, rag_fusion, hyde, rerank"
    )

    # Collection routing
    collections: Optional[List[str]] = Field(
        None,
        description="Specific collections to search (None = auto-route based on query)"
    )

    # Advanced options
    top_k: int = Field(default=10, description="Number of documents to retrieve")
    rerank: bool = Field(default=True, description="Whether to apply cross-encoder reranking")
    include_quality_check: bool = Field(default=True, description="Include hallucination risk assessment")
    include_query_analysis: bool = Field(default=True, description="Include query understanding in response")

    # LLM options
    provider: Optional[str] = Field(None, description="LLM provider (openai, anthropic)")
    generation_options: Dict[str, Any] = Field(default_factory=dict, description="LLM generation options")


class QueryAnalysisResponse(BaseModel):
    """Query understanding results."""
    intent: str
    intent_confidence: float
    entities: List[Dict[str, Any]]
    domain: str
    domain_confidence: float
    complexity: str
    suggested_collections: List[str]


class QualityCheckResponse(BaseModel):
    """Response quality assessment."""
    hallucination_risk: str  # low, medium, high
    confidence_score: float
    grounding_ratio: float
    flagged_claims: List[str]
    recommendation: str


class AdvancedRAGResponse(BaseModel):
    """Response from advanced RAG with full diagnostics."""
    answer: str
    context: List[RAGContextItem]
    query: str
    processing_time: float

    # Advanced metadata
    strategy_used: str
    collections_searched: List[str]

    # Optional analysis
    query_analysis: Optional[QueryAnalysisResponse] = None
    quality_check: Optional[QualityCheckResponse] = None

    # Performance metrics
    retrieval_time: float
    generation_time: float
    total_documents_considered: int


class LLMProviderInfo(BaseModel):
    name: str
    default: bool = False

class EmbeddingResponse(BaseModel):
    embedding: List[float]
    dimension: int
    processing_time: float

class DocumentResponse(BaseModel):
    document_id: str
    status: str
    processing_time: float

class SearchResult(BaseModel):
    content: str
    score: float
    metadata: Dict[str, Any]

class SearchResponse(BaseModel):
    query: str
    results: List[SearchResult]
    processing_time: float

class HybridSearchResponse(BaseModel):
    query: str
    results: List[SearchResult]
    processing_time: float
    metadata: Dict[str, Any]

class ParseQueryResponse(BaseModel):
    vector_query: str
    keyword_query: str
    exact_phrases: List[str]
    required_terms: List[str]
    excluded_terms: List[str]
    boosted_terms: Dict[str, float]
    keywords: List[str]
    complexity: str
    weights: Dict[str, float]

class AnswerResponse(BaseModel):
    question: str
    answer: str
    context: str
    score: float
    processing_time: float

# Visualization API request/response models
class DimensionReductionRequest(BaseModel):
    vectors: List[List[float]] = Field(..., description="List of vectors to reduce dimensions")
    algorithm: str = Field(default="tsne", description="Dimension reduction algorithm (tsne, umap)")
    params: Dict[str, Any] = Field(default_factory=dict, description="Algorithm-specific parameters")

class ClusteringRequest(BaseModel):
    vectors: List[List[float]] = Field(..., description="List of vectors to cluster")
    document_ids: List[int] = Field(..., description="List of document IDs corresponding to vectors")
    algorithm: str = Field(default="kmeans", description="Clustering algorithm (kmeans, hierarchical, dbscan)")
    params: Dict[str, Any] = Field(default_factory=dict, description="Algorithm-specific parameters")

class DimensionReductionResponse(BaseModel):
    reduced_vectors: List[List[float]]
    algorithm: str
    dimensions: int
    processing_time: float

class ClusteringResponse(BaseModel):
    clusters: List[Dict[str, Any]]
    num_clusters: int
    algorithm: str
    parameters: Dict[str, Any]
    processing_time: float

class GPUCapabilitiesResponse(BaseModel):
    gpu_available: bool
    supported_algorithms: List[str]
    gpu_accelerated: Optional[List[str]] = None

# Token Rate Tracker for streaming performance metrics
class TokenRateTracker:
    """Track token streaming rate"""
    def __init__(self):
        self.tokens = 0
        self.start_time = time.time()
        self.last_token_time = None
        
    def add_token(self):
        self.tokens += 1
        self.last_token_time = time.time()
        
    def get_rate(self):
        if self.tokens == 0:
            return 0
        duration = self.last_token_time - self.start_time
        if duration <= 0:
            return 0
        return self.tokens / duration

# Routes
@app.get("/health", response_model=HealthResponse)
def health_check():
    """Check the health of the service"""
    return {
        "status": "healthy",
        "version": "1.1.0",
        "environment": ENVIRONMENT
    }

# Simple test route for basic connectivity
@app.get("/")
def root():
    """Root endpoint for basic connectivity test"""
    return {
        "service": "KnowVerse Haystack Service",
        "message": "KnowVerse Haystack Service is running",
        "status": "healthy",
        "version": "1.1.0"
    }


# =============================================================================
# DOCUMENT EXTRACTION ENDPOINTS
# Enterprise-grade document text extraction with PDF, DOCX, and Excel support
# =============================================================================

class ExtractionResponse(BaseModel):
    """Response model for document extraction."""
    success: bool
    content: str
    metadata: Dict[str, Any] = Field(default_factory=dict)
    extraction_method: Optional[str] = None
    total_chars: int = 0
    total_words: int = 0
    errors: List[str] = Field(default_factory=list)
    processing_time: float = 0.0


class ChunkingRequest(BaseModel):
    """Request model for text chunking."""
    content: str = Field(..., description="Text content to chunk")
    chunk_size: int = Field(default=512, description="Target chunk size in tokens")
    chunk_overlap: int = Field(default=64, description="Overlap between chunks in tokens")
    chunking_strategy: str = Field(default="semantic", description="Chunking strategy: semantic, fixed, or sentence")


class ChunkingResponse(BaseModel):
    """Response model for text chunking."""
    chunks: List[Dict[str, Any]]
    total_chunks: int
    avg_chunk_size: float
    strategy_used: str
    processing_time: float


@app.post("/extract/pdf", response_model=ExtractionResponse, tags=["extraction"])
async def extract_pdf(
    file: UploadFile = File(..., description="PDF file to extract text from"),
    extract_tables: bool = Form(default=True, description="Whether to extract tables"),
    preserve_layout: bool = Form(default=True, description="Whether to preserve text layout")
):
    """
    Extract text and tables from a PDF document.

    Uses pdfplumber for layout-aware extraction with table detection,
    falling back to pypdf for simpler documents.

    Returns:
        ExtractionResponse with extracted content and metadata
    """
    start_time = time.time()

    try:
        from app.extractors import extract_text_from_pdf

        # Read file content
        content = await file.read()

        # Extract text
        result = extract_text_from_pdf(
            content,
            extract_tables=extract_tables,
            preserve_layout=preserve_layout
        )

        processing_time = time.time() - start_time

        return ExtractionResponse(
            success=result.get("success", False),
            content=result.get("content", ""),
            metadata={
                "filename": file.filename,
                "total_pages": result.get("total_pages", 0),
                "total_tables": result.get("total_tables", 0),
                "pdf_metadata": result.get("metadata", {}),
            },
            extraction_method=result.get("extraction_method", "unknown"),
            total_chars=result.get("total_chars", 0),
            total_words=result.get("total_words", 0),
            errors=result.get("errors", []),
            processing_time=processing_time
        )

    except ImportError as e:
        logger.error(f"PDF extraction library not available: {e}")
        raise HTTPException(
            status_code=status.HTTP_501_NOT_IMPLEMENTED,
            detail="PDF extraction not available. Install pdfplumber or pypdf."
        )
    except Exception as e:
        logger.error(f"PDF extraction failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"PDF extraction failed: {str(e)}"
        )


@app.post("/extract/docx", response_model=ExtractionResponse, tags=["extraction"])
async def extract_docx(
    file: UploadFile = File(..., description="Word document to extract text from"),
    extract_tables: bool = Form(default=True, description="Whether to extract tables"),
    preserve_structure: bool = Form(default=True, description="Whether to preserve document structure")
):
    """
    Extract text and tables from a Word document (.docx).

    Uses python-docx for structure-aware extraction with heading,
    list, and table preservation.

    Returns:
        ExtractionResponse with extracted content and metadata
    """
    start_time = time.time()

    try:
        from app.extractors import extract_text_from_docx

        # Read file content
        content = await file.read()

        # Extract text
        result = extract_text_from_docx(
            content,
            extract_tables=extract_tables,
            preserve_structure=preserve_structure
        )

        processing_time = time.time() - start_time

        return ExtractionResponse(
            success=result.get("success", False),
            content=result.get("content", ""),
            metadata={
                "filename": file.filename,
                "total_paragraphs": result.get("total_paragraphs", 0),
                "total_tables": result.get("total_tables", 0),
                "docx_metadata": result.get("metadata", {}),
            },
            extraction_method="python-docx",
            total_chars=result.get("total_chars", 0),
            total_words=result.get("total_words", 0),
            errors=result.get("errors", []),
            processing_time=processing_time
        )

    except ImportError as e:
        logger.error(f"DOCX extraction library not available: {e}")
        raise HTTPException(
            status_code=status.HTTP_501_NOT_IMPLEMENTED,
            detail="DOCX extraction not available. Install python-docx."
        )
    except Exception as e:
        logger.error(f"DOCX extraction failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"DOCX extraction failed: {str(e)}"
        )


@app.post("/extract/excel", response_model=ExtractionResponse, tags=["extraction"])
async def extract_excel(
    file: UploadFile = File(..., description="Excel file to extract text from"),
    max_preview_rows: int = Form(default=100, description="Maximum rows to include in preview"),
    include_empty_sheets: bool = Form(default=False, description="Whether to include empty sheets")
):
    """
    Extract text and data from an Excel workbook (.xlsx, .xls).

    Uses fastexcel (Rust/calamine) for high-performance extraction,
    10-100x faster than openpyxl. Handles large files with 30+ tabs.

    Returns:
        ExtractionResponse with extracted content and metadata
    """
    start_time = time.time()

    try:
        from app.extractors import extract_text_from_excel

        # Read file content
        content = await file.read()

        # Extract text
        result = extract_text_from_excel(
            content,
            max_preview_rows=max_preview_rows,
            include_empty_sheets=include_empty_sheets
        )

        processing_time = time.time() - start_time

        return ExtractionResponse(
            success=result.get("success", False),
            content=result.get("content", ""),
            metadata={
                "filename": file.filename,
                "total_sheets": result.get("total_sheets", 0),
                "total_rows": result.get("total_rows", 0),
                "total_tables": result.get("total_tables", 0),
                "sheet_names": result.get("metadata", {}).get("sheet_names", []),
            },
            extraction_method=result.get("extraction_method", "unknown"),
            total_chars=len(result.get("content", "")),
            total_words=len(result.get("content", "").split()),
            errors=result.get("errors", []),
            processing_time=processing_time
        )

    except ImportError as e:
        logger.error(f"Excel extraction library not available: {e}")
        raise HTTPException(
            status_code=status.HTTP_501_NOT_IMPLEMENTED,
            detail="Excel extraction not available. Install fastexcel and polars."
        )
    except Exception as e:
        logger.error(f"Excel extraction failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Excel extraction failed: {str(e)}"
        )


@app.post("/extract/auto", response_model=ExtractionResponse, tags=["extraction"])
async def extract_auto(
    file: UploadFile = File(..., description="Document to extract text from (auto-detect type)")
):
    """
    Auto-detect document type and extract text.

    Supports: PDF, DOCX, XLSX, XLS, TXT, MD, RTF

    Returns:
        ExtractionResponse with extracted content and metadata
    """
    start_time = time.time()

    filename = file.filename or ""
    ext = filename.lower().split('.')[-1] if '.' in filename else ""

    try:
        content = await file.read()

        if ext == "pdf":
            from app.extractors import extract_text_from_pdf
            result = extract_text_from_pdf(content)
            extraction_method = "pdf"
        elif ext in ("docx", "doc"):
            from app.extractors import extract_text_from_docx
            result = extract_text_from_docx(content)
            extraction_method = "docx"
        elif ext in ("xlsx", "xls"):
            from app.extractors import extract_text_from_excel
            result = extract_text_from_excel(content)
            extraction_method = "excel"
        elif ext in ("txt", "md", "rtf"):
            # Plain text - just decode
            try:
                text_content = content.decode('utf-8')
            except UnicodeDecodeError:
                text_content = content.decode('latin-1')

            result = {
                "success": True,
                "content": text_content,
                "total_chars": len(text_content),
                "total_words": len(text_content.split()),
                "errors": []
            }
            extraction_method = "text"
        else:
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail=f"Unsupported file type: {ext}. Supported: pdf, docx, xlsx, xls, txt, md, rtf"
            )

        processing_time = time.time() - start_time

        return ExtractionResponse(
            success=result.get("success", False),
            content=result.get("content", ""),
            metadata={
                "filename": filename,
                "detected_type": ext,
                **{k: v for k, v in result.get("metadata", {}).items() if k != "filename"}
            },
            extraction_method=extraction_method,
            total_chars=result.get("total_chars", len(result.get("content", ""))),
            total_words=result.get("total_words", len(result.get("content", "").split())),
            errors=result.get("errors", []),
            processing_time=processing_time
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Auto extraction failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Extraction failed: {str(e)}"
        )


@app.post("/chunk", response_model=ChunkingResponse, tags=["extraction"])
async def chunk_text(request: ChunkingRequest):
    """
    Chunk text content for optimal embedding generation.

    Strategies:
    - semantic: Split on natural boundaries (paragraphs, sections)
    - fixed: Fixed-size chunks with overlap
    - sentence: Split on sentence boundaries

    Returns:
        ChunkingResponse with list of chunks
    """
    start_time = time.time()

    content = request.content
    chunk_size = request.chunk_size
    overlap = request.chunk_overlap
    strategy = request.chunking_strategy

    chunks = []

    if strategy == "semantic":
        # Split on natural boundaries
        sections = _split_semantic(content)
        for i, section in enumerate(sections):
            if len(section.split()) > chunk_size:
                # Section too large, split with overlap
                sub_chunks = _split_with_overlap(section, chunk_size, overlap)
                for j, sub_chunk in enumerate(sub_chunks):
                    chunks.append({
                        "index": len(chunks),
                        "content": sub_chunk,
                        "word_count": len(sub_chunk.split()),
                        "char_count": len(sub_chunk),
                        "section_index": i,
                        "sub_index": j
                    })
            else:
                chunks.append({
                    "index": len(chunks),
                    "content": section,
                    "word_count": len(section.split()),
                    "char_count": len(section),
                    "section_index": i,
                    "sub_index": 0
                })

    elif strategy == "sentence":
        # Split on sentence boundaries
        sentences = _split_sentences(content)
        current_chunk = []
        current_words = 0

        for sentence in sentences:
            sentence_words = len(sentence.split())
            if current_words + sentence_words > chunk_size and current_chunk:
                chunk_text = " ".join(current_chunk)
                chunks.append({
                    "index": len(chunks),
                    "content": chunk_text,
                    "word_count": len(chunk_text.split()),
                    "char_count": len(chunk_text)
                })
                # Keep overlap
                overlap_sentences = []
                overlap_words = 0
                for s in reversed(current_chunk):
                    if overlap_words + len(s.split()) <= overlap:
                        overlap_sentences.insert(0, s)
                        overlap_words += len(s.split())
                    else:
                        break
                current_chunk = overlap_sentences
                current_words = overlap_words

            current_chunk.append(sentence)
            current_words += sentence_words

        if current_chunk:
            chunk_text = " ".join(current_chunk)
            chunks.append({
                "index": len(chunks),
                "content": chunk_text,
                "word_count": len(chunk_text.split()),
                "char_count": len(chunk_text)
            })

    else:  # fixed
        chunks_list = _split_with_overlap(content, chunk_size, overlap)
        for i, chunk in enumerate(chunks_list):
            chunks.append({
                "index": i,
                "content": chunk,
                "word_count": len(chunk.split()),
                "char_count": len(chunk)
            })

    processing_time = time.time() - start_time
    avg_size = sum(c["word_count"] for c in chunks) / len(chunks) if chunks else 0

    return ChunkingResponse(
        chunks=chunks,
        total_chunks=len(chunks),
        avg_chunk_size=avg_size,
        strategy_used=strategy,
        processing_time=processing_time
    )


def _split_semantic(text: str) -> List[str]:
    """Split text on semantic boundaries (headers, paragraphs)."""
    import re

    # Split on markdown headers or double newlines
    pattern = r'(?=^#{1,6}\s)|(?:\n\n)'
    sections = re.split(pattern, text, flags=re.MULTILINE)

    # Clean and filter
    sections = [s.strip() for s in sections if s.strip()]
    return sections


def _split_sentences(text: str) -> List[str]:
    """Split text into sentences."""
    import re

    # Simple sentence splitting
    sentences = re.split(r'(?<=[.!?])\s+', text)
    return [s.strip() for s in sentences if s.strip()]


def _split_with_overlap(text: str, chunk_size: int, overlap: int) -> List[str]:
    """Split text into fixed-size chunks with overlap."""
    words = text.split()
    chunks = []

    i = 0
    while i < len(words):
        chunk_words = words[i:i + chunk_size]
        chunks.append(" ".join(chunk_words))
        i += chunk_size - overlap

    return chunks


# =============================================================================
# SEARCH ENDPOINTS
# Semantic, keyword, and hybrid search functionality
# =============================================================================

@app.post("/search", response_model=SearchResponse, tags=["search"])
async def search(request: SearchRequest):
    """
    Perform semantic search using vector embeddings.

    Args:
        request: Search request with query, filters, and top_k

    Returns:
        SearchResponse with matching documents and scores
    """
    start_time = time.time()

    try:
        # Get search pipeline
        search_pipeline = get_search_pipeline()

        # Execute search
        results = search_pipeline.run(
            query=request.query,
            params={
                "Retriever": {"top_k": request.top_k},
                "filters": request.filters or {}
            }
        )

        # Format results
        formatted_results = []
        for doc in results.get("documents", []):
            formatted_results.append(SearchResult(
                content=doc.content if hasattr(doc, 'content') else str(doc),
                score=doc.score if hasattr(doc, 'score') else 0.0,
                metadata=doc.meta if hasattr(doc, 'meta') else {}
            ))

        processing_time = time.time() - start_time

        return SearchResponse(
            query=request.query,
            results=formatted_results,
            processing_time=processing_time
        )

    except Exception as e:
        logger.error(f"Search failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Search failed: {str(e)}"
        )


@app.post("/hybrid-search", response_model=HybridSearchResponse, tags=["search"])
async def hybrid_search(request: HybridSearchRequest):
    """
    Perform hybrid search combining vector similarity and keyword matching.

    Uses reciprocal rank fusion to combine results from both methods.

    Args:
        request: Hybrid search request with weights and options

    Returns:
        HybridSearchResponse with fused results
    """
    start_time = time.time()

    try:
        # Get hybrid searcher
        hybrid_searcher = get_hybrid_searcher()

        # Execute hybrid search
        results = hybrid_searcher.search(
            query=request.query,
            top_k=request.top_k,
            filters=request.filters,
            vector_weight=request.vector_weight,
            keyword_weight=request.keyword_weight,
            early_termination=request.early_termination
        )

        # Format results
        formatted_results = []
        for doc in results.get("documents", []):
            formatted_results.append(SearchResult(
                content=doc.get("content", ""),
                score=doc.get("score", 0.0),
                metadata=doc.get("metadata", {})
            ))

        processing_time = time.time() - start_time

        return HybridSearchResponse(
            query=request.query,
            results=formatted_results,
            processing_time=processing_time,
            metadata={
                "vector_weight": request.vector_weight or 0.5,
                "keyword_weight": request.keyword_weight or 0.5,
                "method": "reciprocal_rank_fusion"
            }
        )

    except Exception as e:
        logger.error(f"Hybrid search failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Hybrid search failed: {str(e)}"
        )


class RerankRequest(BaseModel):
    """Request for cross-encoder reranking."""
    query: str = Field(..., description="Query to rerank results against")
    documents: List[Dict[str, Any]] = Field(..., description="Documents to rerank")
    top_k: int = Field(default=10, description="Number of results to return after reranking")


class RerankResponse(BaseModel):
    """Response from reranking."""
    results: List[Dict[str, Any]]
    processing_time: float


@app.post("/search/rerank", response_model=RerankResponse, tags=["search"])
async def rerank_results(request: RerankRequest):
    """
    Rerank search results using cross-encoder model.

    Uses ms-marco-MiniLM-L-6-v2 cross-encoder for pairwise relevance scoring.
    More accurate than bi-encoder similarity but slower.

    Args:
        request: Query and documents to rerank

    Returns:
        RerankResponse with reranked documents and scores
    """
    start_time = time.time()

    try:
        # Initialize cross-encoder reranker
        reranker = CrossEncoderReranker()

        # Convert documents to RetrievalResult format
        retrieval_results = []
        for doc in request.documents:
            retrieval_results.append(RetrievalResult(
                id=str(doc.get("document_id", doc.get("id", ""))),
                content=doc.get("snippet", doc.get("content", doc.get("text", ""))),
                score=doc.get("score", 0.0),
                metadata=doc,
                collection=doc.get("collection", "")
            ))

        # Rerank using cross-encoder
        reranked = reranker.rerank(
            query=request.query,
            results=retrieval_results,
            top_k=request.top_k
        )

        # Convert back to dict format
        results = []
        for r in reranked:
            result = r.metadata.copy() if r.metadata else {}
            result["rerank_score"] = r.score
            result["document_id"] = r.id
            result["content"] = r.content
            results.append(result)

        processing_time = time.time() - start_time
        logger.info(f"Reranked {len(request.documents)} docs to top {len(results)} in {processing_time:.3f}s")

        return RerankResponse(
            results=results,
            processing_time=processing_time
        )

    except Exception as e:
        logger.error(f"Reranking failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Reranking failed: {str(e)}"
        )


# =============================================================================
# EMBEDDING ENDPOINTS
# Vector embedding generation
# =============================================================================

@app.post("/embeddings/generate", response_model=EmbeddingResponse, tags=["embeddings"])
async def generate_embedding(request: EmbeddingRequest):
    """
    Generate vector embeddings for text content.

    Args:
        request: Embedding request with text and model name

    Returns:
        EmbeddingResponse with embedding vector
    """
    start_time = time.time()

    try:
        # Generate embedding using the specified model (wraps text in list)
        embeddings = generate_embeddings(
            texts=[request.text],
            model_name=request.model_name or "base"
        )

        # Get first embedding result
        embedding = embeddings[0] if len(embeddings) > 0 else []

        # Convert to list if numpy array
        if isinstance(embedding, np.ndarray):
            embedding_list = embedding.tolist()
        else:
            embedding_list = list(embedding)

        processing_time = time.time() - start_time

        return EmbeddingResponse(
            embedding=embedding_list,
            dimension=len(embedding_list),
            processing_time=processing_time
        )

    except Exception as e:
        logger.error(f"Embedding generation failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Embedding generation failed: {str(e)}"
        )


# =============================================================================
# RAG ENDPOINTS
# Retrieval-Augmented Generation functionality
# =============================================================================

@app.post("/rag/answer", response_model=RAGResponse, tags=["rag"])
async def rag_answer(request: RAGRequest):
    """
    Generate an answer using Retrieval-Augmented Generation.

    Retrieves relevant documents and uses an LLM to generate a response.

    Args:
        request: RAG request with query, organization ID, and options

    Returns:
        RAGResponse with answer, context, and metadata
    """
    start_time = time.time()

    try:
        # Retrieve relevant context
        context_docs = await asyncio.to_thread(
            retrieve_and_rank,
            query=request.query,
            org_id=request.org_id,
            options=request.retrieval_options  # Pass as options dict, not spread
        )

        # Build context string
        context_items = []
        for doc in context_docs:
            context_items.append(RAGContextItem(
                document_id=doc.get("document_id") or doc.get("id"),
                title=doc.get("title", ""),
                source=doc.get("source", ""),
                text=doc.get("text") or doc.get("content", ""),  # retrieval returns 'text'
                score=doc.get("score", 0.0)
            ))

        context_text = "\n\n".join([item.text for item in context_items])

        # Generate response using LLM
        provider = request.provider or "openai"
        llm = llm_registry.get_provider(provider)

        # LLM generate expects (prompt, context, options)
        answer = await asyncio.to_thread(
            llm.generate,
            request.query,
            [{"text": item.text, "title": item.title, "source": item.source} for item in context_items],
            request.generation_options
        )

        processing_time = time.time() - start_time

        return RAGResponse(
            answer=answer,
            context=context_items,
            metadata={
                "provider": provider,
                "num_context_docs": len(context_items),
                "retrieval_options": request.retrieval_options
            },
            query=request.query,
            processing_time=processing_time
        )

    except Exception as e:
        logger.error(f"RAG answer generation failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"RAG answer generation failed: {str(e)}"
        )


@app.post("/rag/advanced", response_model=AdvancedRAGResponse, tags=["rag"])
async def advanced_rag_answer(request: AdvancedRAGRequest):
    """
    Advanced RAG with elite retrieval features.

    Features:
    - Query understanding (intent, entities, domain detection)
    - Advanced retrieval strategies (RAG-Fusion, HyDE, reranking)
    - Multi-collection search with intelligent routing
    - Quality checks (hallucination detection, grounding verification)
    - Conversation memory (optional)

    Args:
        request: AdvancedRAGRequest with query and options

    Returns:
        AdvancedRAGResponse with answer, context, and full diagnostics
    """
    start_time = time.time()
    retrieval_start = time.time()
    memory_manager = None

    try:
        # =================================================================
        # Step 1: Query Understanding
        # =================================================================
        query_analysis = None
        suggested_collections = []
        is_complex = False

        if request.include_query_analysis:
            try:
                analysis = await asyncio.to_thread(
                    analyze_query,
                    request.query
                )
                is_complex = analysis.is_complex
                query_analysis = QueryAnalysisResponse(
                    intent=analysis.intent.value if hasattr(analysis.intent, 'value') else str(analysis.intent),
                    intent_confidence=analysis.intent_confidence,
                    entities=[{"text": e.text, "type": e.type.value if hasattr(e.type, 'value') else str(e.type), "value": e.normalized or e.text}
                              for e in analysis.entities] if analysis.entities else [],
                    domain=analysis.domain.value if hasattr(analysis.domain, 'value') else str(analysis.domain),
                    domain_confidence=analysis.domain_confidence,
                    complexity="complex" if analysis.is_complex else "simple",
                    suggested_collections=analysis.suggested_collections or []
                )
                suggested_collections = analysis.suggested_collections or []
            except Exception as e:
                logger.warning(f"Query analysis failed, continuing without: {e}")

        # =================================================================
        # Step 2: Determine Collections to Search
        # =================================================================
        collections_to_search = request.collections or suggested_collections
        if not collections_to_search:
            # Default fallback based on org_id
            collections_to_search = [f"org_{request.org_id}_documents"]

        # =================================================================
        # Step 3: Memory Context (if session provided)
        # =================================================================
        memory_context = ""
        if request.session_id:
            try:
                memory_manager = get_memory_manager()
                working_memory = await asyncio.to_thread(
                    memory_manager.start_request,
                    request.query,
                    request.session_id
                )
                # Get context from working memory
                memory_context = await asyncio.to_thread(
                    memory_manager.get_context_for_generation,
                    include_memories=True,
                    include_conversation=True,
                    max_tokens=500
                )
            except Exception as e:
                logger.warning(f"Memory retrieval failed, continuing without: {e}")

        # =================================================================
        # Step 4: Advanced Retrieval
        # =================================================================
        strategy = request.strategy

        # Auto-select strategy based on query analysis
        if strategy == "auto":
            if is_complex:
                strategy = "rag_fusion"
            elif query_analysis and query_analysis.intent in ["comparative", "analytical"]:
                strategy = "rag_fusion"
            else:
                strategy = "basic"

        # Initialize advanced retriever
        retriever = AdvancedRetriever()

        # Configure retrieval based on strategy
        use_rag_fusion = strategy in ["rag_fusion", "auto"]
        use_hyde = strategy == "hyde"

        config = RetrievalConfig(
            use_rag_fusion=use_rag_fusion,
            use_hyde=use_hyde,
            use_reranking=request.rerank,
            final_k=request.top_k,
            initial_k=request.top_k * 3  # Get more initially for fusion/reranking
        )

        # Execute retrieval for each collection
        all_results = []
        for collection in collections_to_search:
            try:
                results = await asyncio.to_thread(
                    retriever.retrieve,
                    request.query,
                    collection=collection,
                    org_id=request.org_id,
                    config=config
                )
                all_results.extend(results)
            except Exception as e:
                logger.warning(f"Retrieval from {collection} failed: {e}")

        # Sort by score and limit
        all_results.sort(key=lambda x: x.score, reverse=True)
        all_results = all_results[:request.top_k]

        retrieval_time = time.time() - retrieval_start

        # =================================================================
        # Step 5: Build Context
        # =================================================================
        context_items = []
        for result in all_results:
            context_items.append(RAGContextItem(
                document_id=result.id,
                title=result.metadata.get("title", ""),
                source=result.metadata.get("source", result.collection),
                text=result.content,
                score=result.score
            ))

        total_considered = len(all_results)

        # =================================================================
        # Step 6: Generate Response
        # =================================================================
        generation_start = time.time()

        provider = request.provider or "openai"
        llm = llm_registry.get_provider(provider)

        # Build enhanced prompt with memory context
        enhanced_query = f"{memory_context}\n\n{request.query}" if memory_context else request.query

        answer = await asyncio.to_thread(
            llm.generate,
            enhanced_query,
            [{"text": item.text, "title": item.title, "source": item.source} for item in context_items],
            request.generation_options
        )

        generation_time = time.time() - generation_start

        # =================================================================
        # Step 7: Quality Check
        # =================================================================
        quality_check = None

        if request.include_quality_check and context_items:
            try:
                # Build sources list for quality check
                sources = [{"text": item.text, "title": item.title, "source": item.source}
                          for item in context_items]

                quality_report = await asyncio.to_thread(
                    check_response_quality,
                    answer,
                    sources,
                    request.query
                )

                # Map hallucination_risk float (0-1) to category
                risk_level = "low"
                if quality_report.hallucination_risk > 0.6:
                    risk_level = "high"
                elif quality_report.hallucination_risk > 0.3:
                    risk_level = "medium"

                quality_check = QualityCheckResponse(
                    hallucination_risk=risk_level,
                    confidence_score=quality_report.confidence_score,
                    grounding_ratio=quality_report.source_coverage,
                    flagged_claims=quality_report.warnings or [],
                    recommendation="Response appears well-grounded" if risk_level == "low" else "Review flagged claims"
                )
            except Exception as e:
                logger.warning(f"Quality check failed, continuing without: {e}")

        # =================================================================
        # Step 8: Store in Memory (if session provided)
        # =================================================================
        if request.session_id and memory_manager:
            try:
                await asyncio.to_thread(
                    memory_manager.end_request,
                    request.session_id,
                    None,  # user_id
                    None,  # org_id
                    answer,
                    False  # save_to_ltm
                )
            except Exception as e:
                logger.warning(f"Memory storage failed: {e}")

        # =================================================================
        # Build Response
        # =================================================================
        processing_time = time.time() - start_time

        return AdvancedRAGResponse(
            answer=answer,
            context=context_items,
            query=request.query,
            processing_time=processing_time,
            strategy_used=strategy,
            collections_searched=collections_to_search,
            query_analysis=query_analysis,
            quality_check=quality_check,
            retrieval_time=retrieval_time,
            generation_time=generation_time,
            total_documents_considered=total_considered
        )

    except Exception as e:
        logger.error(f"Advanced RAG failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Advanced RAG failed: {str(e)}"
        )


@app.post("/rag/stream", tags=["rag"])
async def rag_stream(request: RAGRequest):
    """
    Stream a RAG response using Server-Sent Events.

    Retrieves context using advanced retrieval (RAG-Fusion + cross-encoder reranking)
    and streams the LLM response token by token.

    Args:
        request: RAG request with query and options

    Returns:
        StreamingResponse with SSE events
    """
    async def generate_stream():
        tracker = TokenRateTracker()

        try:
            # Use advanced retrieval with cross-encoder reranking for better relevance
            retrieval_options = request.retrieval_options or {}
            max_documents = retrieval_options.get("max_documents", 5)
            # Use very low default threshold - cross-encoder will handle relevance ranking
            # Short queries like "What is EMAP?" need low thresholds to find relevant docs
            min_similarity = retrieval_options.get("min_similarity", 0.01)

            # Configure advanced retrieval
            config = RetrievalConfig(
                use_rag_fusion=True,  # Multi-query + Reciprocal Rank Fusion
                use_reranking=True,   # Cross-encoder attention for precision
                use_hyde=False,       # HyDE adds latency, skip for streaming
                final_k=max_documents,
                min_score=-100.0,     # Cross-encoder uses logit scores (can be negative)
                initial_k=max_documents * 4  # Get more initially for fusion/reranking
            )

            # Create retriever with base Qdrant search
            from app.qdrant_client import get_qdrant_client
            from app.embeddings import get_embedding

            qdrant = get_qdrant_client()

            def base_retriever(query, collection=None, org_id=None, limit=10, **kwargs):
                """Base retriever that calls Qdrant."""
                query_embedding = get_embedding(query)
                # Use low threshold for initial retrieval - cross-encoder will rerank
                results = qdrant.search(
                    org_id=org_id,
                    query_vector=query_embedding,
                    limit=limit,
                    score_threshold=0.01,  # Very low for broad recall, reranker filters
                    collection=collection or "org_documents"
                )
                # Convert SearchResult dataclass objects to RetrievalResult format
                # Note: qdrant.search() returns SearchResult objects with attributes, not dicts
                return [
                    RetrievalResult(
                        id=str(r.id),
                        content=r.content,
                        score=r.score,
                        metadata=r.metadata,
                        collection=r.collection
                    )
                    for r in results
                ]

            retriever = AdvancedRetriever(base_retriever=base_retriever, config=config)

            # Execute advanced retrieval
            retrieval_results = await asyncio.to_thread(
                retriever.retrieve,
                request.query,
                collection="org_documents",
                org_id=request.org_id,
                config=config
            )

            # Convert to dict format for downstream processing
            context_docs = [
                {
                    "id": r.id,
                    "document_id": r.id,
                    "title": r.metadata.get("title", ""),
                    "source": r.metadata.get("source", r.collection),
                    "content": r.content,
                    "text": r.content,
                    "score": r.score
                }
                for r in retrieval_results
            ]

            # Send context event
            context_data = {
                "type": "context",
                "documents": [
                    {
                        "id": doc.get("id"),
                        "title": doc.get("title"),
                        "score": doc.get("score", 0.0)
                    }
                    for doc in context_docs
                ]
            }
            yield f"data: {json.dumps(context_data)}\n\n"

            # Build context and prompt
            context_text = "\n\n".join([doc.get("content", "") for doc in context_docs])

            prompt = f"""Based on the following context, answer the question. If the answer cannot be found in the context, say so.

Context:
{context_text}

Question: {request.query}

Answer:"""

            # Get LLM and stream response
            provider = request.provider or "openai"
            llm = llm_registry.get_provider(provider)

            # Prepare context for LLM
            context_for_llm = [{"text": doc.get("content", ""), "title": doc.get("title"), "source": doc.get("source")} for doc in context_docs]

            # Stream tokens
            async for token in llm.generate_stream(request.query, context_for_llm, request.generation_options):
                tracker.add_token()
                token_data = {
                    "type": "token",
                    "content": token,
                    "index": tracker.tokens
                }
                yield f"data: {json.dumps(token_data)}\n\n"

            # Send completion event
            completion_data = {
                "type": "complete",
                "total_tokens": tracker.tokens,
                "tokens_per_second": tracker.get_rate()
            }
            yield f"data: {json.dumps(completion_data)}\n\n"

        except Exception as e:
            logger.error(f"RAG stream error: {e}")
            error_data = {"type": "error", "message": str(e)}
            yield f"data: {json.dumps(error_data)}\n\n"

    return StreamingResponse(
        generate_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )


@app.get("/rag/providers", response_model=List[LLMProviderInfo], tags=["rag"])
async def get_rag_providers():
    """
    Get list of available LLM providers for RAG.

    Returns:
        List of LLMProviderInfo with available providers
    """
    providers = []

    # Check which providers are available
    available = llm_registry.list_providers()
    default_provider = llm_registry._default_provider

    for name in available:
        providers.append(LLMProviderInfo(
            name=name,
            default=(name == default_provider)
        ))

    return providers


# =============================================================================
# AGENTIC RAG ENDPOINTS
# Multi-step reasoning with tool use
# =============================================================================

@app.post("/rag/agent/stream", tags=["agent"])
async def agent_rag_stream(request: AgentRAGRequest):
    """
    Stream an agentic RAG response using Server-Sent Events.

    Supports multiple agent modes:
    - auto: Automatically selects the best mode based on query analysis
    - react: Reason-Act-Observe loop with tool use
    - deep_research: Multi-source investigation with synthesis
    - plan_execute: Create and execute a step-by-step plan

    Args:
        request: AgentRAGRequest with query and agent options

    Returns:
        StreamingResponse with SSE events including thoughts, actions, and final answer
    """
    from app.agents import get_agent_orchestrator, AgentContext, AgentMode

    async def generate_stream():
        try:
            # Create agent context
            context = AgentContext(
                org_id=request.org_id,
                query=request.query,
                session_id=request.session_id,
                max_iterations=request.max_iterations,
                temperature=request.temperature,
                max_tokens=request.max_tokens,
                provider=request.provider,
                include_trace=request.include_trace,
                system_prompt=request.system_prompt,
                conversation_history=request.conversation_history
            )

            # Get query analysis for mode selection
            try:
                query_analysis = analyze_query(request.query)
                context.query_analysis = query_analysis
            except Exception as e:
                logger.warning(f"Query analysis failed: {e}")

            # Get orchestrator and select mode
            orchestrator = get_agent_orchestrator()

            # Parse mode
            mode = None
            if request.mode and request.mode != "auto":
                try:
                    mode = AgentMode(request.mode)
                except ValueError:
                    logger.warning(f"Invalid mode: {request.mode}, using auto")

            # Run the agent
            async for event in orchestrator.run(request.query, context, mode):
                yield event.to_sse()

        except Exception as e:
            logger.exception("Agent stream error")
            error_data = {"type": "error", "message": str(e)}
            yield f"data: {json.dumps(error_data)}\n\n"

    return StreamingResponse(
        generate_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )


@app.get("/rag/agent/modes", tags=["agent"])
async def get_agent_modes():
    """
    Get list of available agent modes.

    Returns:
        List of agent modes with descriptions
    """
    return [
        {
            "mode": "auto",
            "name": "Auto",
            "description": "Automatically selects the best mode based on query analysis"
        },
        {
            "mode": "react",
            "name": "ReAct",
            "description": "Reason-Act-Observe loop. Good for queries requiring tool use."
        },
        {
            "mode": "deep_research",
            "name": "Deep Research",
            "description": "Multi-source investigation with synthesis. Good for complex research queries."
        },
        {
            "mode": "plan_execute",
            "name": "Plan & Execute",
            "description": "Create and execute a step-by-step plan. Good for multi-step tasks."
        }
    ]


@app.get("/rag/agent/tools", tags=["agent"])
async def get_agent_tools():
    """
    Get list of available agent tools.

    Returns:
        List of tools with their schemas
    """
    from app.tools import get_tool_registry

    registry = get_tool_registry()
    tools = []

    for name in registry.list_tools():
        tool = registry.get(name)
        if tool:
            tools.append({
                "name": tool.name,
                "description": tool.description,
                "category": tool.category,
                "parameters": {
                    param_name: {
                        "type": param.type.value,
                        "description": param.description,
                        "required": param.required
                    }
                    for param_name, param in tool.parameters.items()
                }
            })

    return tools


# =============================================================================
# QUERY PARSING ENDPOINTS
# Query analysis and optimization
# =============================================================================

@app.post("/parse-query", response_model=ParseQueryResponse, tags=["query"])
async def parse_query(request: ParseQueryRequest):
    """
    Parse and analyze a search query.

    Extracts keywords, phrases, and determines optimal search strategy.

    Args:
        request: Parse query request with query text

    Returns:
        ParseQueryResponse with parsed query components
    """
    try:
        parser = QueryParser()
        result = parser.parse_query(request.query)

        return ParseQueryResponse(
            vector_query=result.get("vector_query", request.query),
            keyword_query=result.get("keyword_query", request.query),
            exact_phrases=result.get("exact_phrases", []),
            required_terms=result.get("required_terms", []),
            excluded_terms=result.get("excluded_terms", []),
            boosted_terms=result.get("boosted_terms", {}),
            keywords=result.get("keywords", []),
            complexity=result.get("complexity", "simple"),
            weights=result.get("weights", {"vector": 0.5, "keyword": 0.5})
        )

    except Exception as e:
        logger.error(f"Query parsing failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Query parsing failed: {str(e)}"
        )


# =============================================================================
# DOMAIN DETECTION ENDPOINTS
# Domain-aware search and embedding
# =============================================================================

@app.post("/domains/detect", response_model=DomainDetectionResponse, tags=["domains"])
async def detect_domain(request: DomainDetectionRequest):
    """
    Detect the domain of a query for domain-aware search.

    Args:
        request: Domain detection request with query text

    Returns:
        DomainDetectionResponse with detected domain and confidence
    """
    start_time = time.time()

    try:
        result = detect_query_domain(
            query=request.query,
            organization_id=request.organization_id
        )

        processing_time = time.time() - start_time

        return DomainDetectionResponse(
            domain=result.get("domain", DEFAULT_DOMAIN),
            confidence=result.get("confidence", 0.0),
            alternatives=result.get("alternatives"),
            processing_time=processing_time
        )

    except Exception as e:
        logger.error(f"Domain detection failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Domain detection failed: {str(e)}"
        )


@app.get("/domains", response_model=List[DomainInfo], tags=["domains"])
async def list_domains():
    """
    List available domains for domain-aware search.

    Returns:
        List of DomainInfo with available domains
    """
    try:
        domains = get_available_domains()

        return [
            DomainInfo(
                domain=d.get("domain", "general"),
                description=d.get("description"),
                model_count=d.get("model_count", 0)
            )
            for d in domains
        ]

    except Exception as e:
        logger.error(f"Failed to list domains: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to list domains: {str(e)}"
        )


# =============================================================================
# VISUALIZATION ENDPOINTS
# Dimension reduction and clustering for document visualization
# =============================================================================

@app.post("/visualization/dimension-reduction", response_model=DimensionReductionResponse, tags=["visualization"])
async def dimension_reduction(request: DimensionReductionRequest):
    """
    Reduce dimensions of vectors for visualization.

    Supports t-SNE and UMAP algorithms.

    Args:
        request: Dimension reduction request with vectors and algorithm

    Returns:
        DimensionReductionResponse with reduced vectors
    """
    start_time = time.time()

    try:
        # Convert to numpy array
        vectors = np.array(request.vectors)

        # Get dimension reducer
        reducer = DimensionReduction(algorithm=request.algorithm)

        # Reduce dimensions
        reduced = reducer.reduce(vectors, **request.params)

        processing_time = time.time() - start_time

        return DimensionReductionResponse(
            reduced_vectors=reduced.tolist(),
            algorithm=request.algorithm,
            dimensions=reduced.shape[1] if len(reduced.shape) > 1 else 1,
            processing_time=processing_time
        )

    except Exception as e:
        logger.error(f"Dimension reduction failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Dimension reduction failed: {str(e)}"
        )


@app.post("/visualization/clustering", response_model=ClusteringResponse, tags=["visualization"])
async def cluster_documents(request: ClusteringRequest):
    """
    Cluster documents based on vector similarity.

    Supports k-means, hierarchical, and DBSCAN algorithms.

    Args:
        request: Clustering request with vectors and algorithm

    Returns:
        ClusteringResponse with cluster assignments
    """
    start_time = time.time()

    try:
        # Convert to numpy array
        vectors = np.array(request.vectors)

        # Get cluster analyzer
        analyzer = ClusterAnalysis(algorithm=request.algorithm)

        # Perform clustering
        result = analyzer.cluster(
            vectors=vectors,
            document_ids=request.document_ids,
            **request.params
        )

        processing_time = time.time() - start_time

        return ClusteringResponse(
            clusters=result.get("clusters", []),
            num_clusters=result.get("num_clusters", 0),
            algorithm=request.algorithm,
            parameters=request.params,
            processing_time=processing_time
        )

    except Exception as e:
        logger.error(f"Clustering failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Clustering failed: {str(e)}"
        )


@app.get("/visualization/gpu-capabilities", response_model=GPUCapabilitiesResponse, tags=["visualization"])
async def get_gpu_capabilities():
    """
    Get GPU capabilities for visualization algorithms.

    Returns:
        GPUCapabilitiesResponse with GPU status and supported algorithms
    """
    try:
        import torch
        gpu_available = torch.cuda.is_available()

        supported = ["tsne", "umap", "kmeans", "hierarchical", "dbscan"]
        gpu_accelerated = ["tsne", "umap"] if gpu_available else None

        return GPUCapabilitiesResponse(
            gpu_available=gpu_available,
            supported_algorithms=supported,
            gpu_accelerated=gpu_accelerated
        )

    except ImportError:
        return GPUCapabilitiesResponse(
            gpu_available=False,
            supported_algorithms=["tsne", "umap", "kmeans", "hierarchical", "dbscan"],
            gpu_accelerated=None
        )


if __name__ == "__main__":
    import uvicorn
    from config.settings import API_HOST, API_PORT

    uvicorn.run("app.main:app", host=API_HOST, port=API_PORT, reload=DEBUG)
