import logging
from fastapi import FastAPI, Depends, HTTPException, status, BackgroundTasks
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

if __name__ == "__main__":
    import uvicorn
    from config.settings import API_HOST, API_PORT
    
    uvicorn.run("app.main:app", host=API_HOST, port=API_PORT, reload=DEBUG)
