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
        "status": "ok",
        "version": "1.0.0", 
        "environment": ENVIRONMENT
    }

# Simple test route for basic connectivity
@app.get("/")
def root():
    """Root endpoint for basic connectivity test"""
    return {"message": "KnowVerse Haystack Service is running", "status": "healthy"}


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


if __name__ == "__main__":
    import uvicorn
    from config.settings import API_HOST, API_PORT
    
    uvicorn.run("app.main:app", host=API_HOST, port=API_PORT, reload=DEBUG)
