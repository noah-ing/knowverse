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

# Domain-specific endpoints
@app.get("/domains/available", response_model=List[DomainInfo])
def list_available_domains(organization_id: int):
    """
    List all available domains for an organization
    """
    try:
        domains = get_available_domains(organization_id)
        
        # Format response
        domain_info = []
        for domain in domains:
            # In a full implementation, we'd get more details from the database
            info = {
                "domain": domain,
                "description": f"Domain for {domain} content",
                "model_count": 1 if domain == DEFAULT_DOMAIN else 0  # Default has at least one model
            }
            domain_info.append(info)
        
        return domain_info
    except Exception as e:
        logger.error(f"Error listing domains: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to list domains: {str(e)}"
        )

@app.post("/domains/detect", response_model=DomainDetectionResponse)
def detect_domain(request: DomainDetectionRequest):
    """
    Detect the appropriate domain for a query
    """
    start_time = time.time()
    
    try:
        domain, confidence = detect_query_domain(request.query, request.organization_id)
        
        # In a full implementation, we'd also return alternative domains with scores
        return {
            "domain": domain,
            "confidence": confidence,
            "alternatives": None,  # Would include alternatives in full implementation
            "processing_time": time.time() - start_time
        }
    except Exception as e:
        logger.error(f"Error detecting domain: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Domain detection failed: {str(e)}"
        )

@app.post("/domains/embedding/generate", response_model=EmbeddingResponse)
def generate_domain_embedding(request: DomainEmbeddingRequest):
    """
    Generate embeddings using a domain-specific model
    """
    start_time = time.time()
    
    try:
        # Generate embedding with domain-specific model
        embedding = generate_embeddings(
            texts=[request.text],
            model_name=request.model_name,
            domain=request.domain,
            organization_id=request.organization_id
        )[0]  # Get first element since we only have one text
        
        # Convert to list for JSON serialization
        embedding_list = embedding.tolist()
        
        return {
            "embedding": embedding_list,
            "dimension": len(embedding_list),
            "processing_time": time.time() - start_time
        }
    except Exception as e:
        logger.error(f"Error generating domain embeddings: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate domain embeddings: {str(e)}"
        )

@app.post("/domains/models/fine-tune", response_model=DomainModelFineTuneResponse)
def fine_tune_domain_embedding_model(request: DomainModelFineTuneRequest):
    """
    Fine-tune a domain-specific embedding model
    """
    start_time = time.time()
    
    try:
        # Perform fine-tuning
        result = fine_tune_domain_model(
            base_model_name=request.base_model,
            domain=request.domain,
            training_data=request.training_data,
            organization_id=request.organization_id
        )
        
        # Add processing time
        result["processing_time"] = time.time() - start_time
        
        return result
    except Exception as e:
        logger.error(f"Error fine-tuning domain model: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Domain model fine-tuning failed: {str(e)}"
        )

@app.get("/domains/models", response_model=List[DomainEmbeddingModel])
def list_domain_models(domain: str, organization_id: int):
    """
    List all models for a specific domain
    """
    try:
        # Get domain models from the registry
        models_info = model_registry.get_domain_model_info(domain, organization_id)
        
        # Format response
        domain_models = []
        for name, info in models_info.items():
            domain_models.append({
                "name": name,
                "domain": domain,
                "base_model": info.get("base_model"),
                "dimension": info.get("dimension"),
                "version": info.get("version"),
                "performance_metrics": info.get("performance_metrics")
            })
        
        # If no domain-specific models, return base models
        if not domain_models and domain == DEFAULT_DOMAIN:
            for model_name, dimension in EMBEDDING_MODELS.items():
                domain_models.append({
                    "name": model_name,
                    "domain": DEFAULT_DOMAIN,
                    "base_model": model_name,
                    "dimension": dimension,
                    "version": "1.0",
                    "performance_metrics": None
                })
        
        return domain_models
    except Exception as e:
        logger.error(f"Error listing domain models: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to list domain models: {str(e)}"
        )

@app.post("/embeddings/generate", response_model=EmbeddingResponse)
def generate_embedding(request: EmbeddingRequest):
    """Generate embeddings for a given text"""
    start_time = time.time()
    
    try:
        embedding_model = get_embedding_model(request.model_name)
        embedding = embedding_model.encode(request.text)
        
        # Convert to list for JSON serialization
        embedding_list = embedding.tolist()
        
        return {
            "embedding": embedding_list,
            "dimension": len(embedding_list),
            "processing_time": time.time() - start_time
        }
    except Exception as e:
        logger.error(f"Error generating embeddings: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate embeddings: {str(e)}"
        )

@app.post("/documents/index", response_model=DocumentResponse)
def index_document(request: DocumentRequest):
    """Index a document in the document store"""
    start_time = time.time()
    
    try:
        document_store = get_document_store()
        embedding_model = get_embedding_model()
        
        # Generate embedding for the document
        embedding = embedding_model.encode(request.content)
        
        # Create document dict
        doc = {
            "content": request.content,
            "embedding": embedding,
            "metadata": request.metadata
        }
        
        # Write to document store
        document_id = document_store.write_documents([doc])
        
        return {
            "document_id": str(document_id[0]),
            "status": "indexed",
            "processing_time": time.time() - start_time
        }
    except Exception as e:
        logger.error(f"Error indexing document: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to index document: {str(e)}"
        )

@app.post("/search", response_model=SearchResponse)
def search(request: SearchRequest):
    """Perform semantic search on indexed documents"""
    start_time = time.time()
    
    try:
        search_pipeline = get_search_pipeline()
        
        # Execute search
        result = search_pipeline.run(
            query=request.query,
            params={"Retriever": {"top_k": request.top_k, "filters": request.filters}}
        )
        
        # Format results
        search_results = []
        for doc in result["documents"]:
            search_results.append({
                "content": doc.content,
                "score": float(doc.score) if doc.score is not None else 0.0,
                "metadata": doc.metadata
            })
        
        return {
            "query": request.query,
            "results": search_results,
            "processing_time": time.time() - start_time
        }
    except Exception as e:
        logger.error(f"Error performing search: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Search failed: {str(e)}"
        )

@app.post("/hybrid-search", response_model=HybridSearchResponse)
def hybrid_search(request: HybridSearchRequest):
    """Perform hybrid search combining vector and keyword approaches"""
    start_time = time.time()
    
    try:
        # Get hybrid searcher
        hybrid_searcher = get_hybrid_searcher()
        
        # Execute hybrid search
        results, metadata = hybrid_searcher.search(
            query=request.query,
            filters=request.filters,
            top_k=request.top_k,
            early_termination=request.early_termination,
            vector_weight=request.vector_weight,
            keyword_weight=request.keyword_weight
        )
        
        # Format results
        search_results = []
        for doc in results:
            search_results.append({
                "content": doc.content,
                "score": float(doc.score) if hasattr(doc, 'score') and doc.score is not None else 0.0,
                "metadata": doc.meta
            })
        
        # Remove large parsed_query from metadata to keep response size reasonable
        if "parsed_query" in metadata:
            del metadata["parsed_query"]
        
        return {
            "query": request.query,
            "results": search_results,
            "processing_time": time.time() - start_time,
            "metadata": metadata
        }
    except Exception as e:
        logger.error(f"Error performing hybrid search: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Hybrid search failed: {str(e)}"
        )

@app.post("/parse-query", response_model=ParseQueryResponse)
def parse_query(request: ParseQueryRequest):
    """Parse a query string into components for different search methods"""
    try:
        query_parser = QueryParser()
        parsed = query_parser.parse_query(request.query)
        return parsed
    except Exception as e:
        logger.error(f"Error parsing query: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Query parsing failed: {str(e)}"
        )

@app.post("/question-answering", response_model=AnswerResponse)
def answer_question(request: QuestionRequest):
    """Answer a question based on the indexed documents"""
    start_time = time.time()
    
    try:
        qa_pipeline = get_qa_pipeline()
        
        # Execute QA pipeline
        result = qa_pipeline.run(
            query=request.question,
            params={"Retriever": {"filters": request.filters}}
        )
        
        # Get best answer
        if not result["answers"]:
            return {
                "question": request.question,
                "answer": "No answer found",
                "context": "",
                "score": 0.0,
                "processing_time": time.time() - start_time
            }
        
        best_answer = result["answers"][0]
        
        return {
            "question": request.question,
            "answer": best_answer.answer,
            "context": best_answer.context,
            "score": float(best_answer.score) if best_answer.score is not None else 0.0,
            "processing_time": time.time() - start_time
        }
    except Exception as e:
        logger.error(f"Error answering question: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Question answering failed: {str(e)}"
        )

# Visualization API endpoints
@app.post("/visualization/dimension-reduction", response_model=DimensionReductionResponse)
def reduce_dimensions(request: DimensionReductionRequest):
    """Reduce dimensions of vectors for visualization using t-SNE or UMAP"""
    start_time = time.time()
    
    try:
        # Extract parameters
        vectors = request.vectors
        algorithm = request.algorithm
        params = request.params
        
        # Validate input
        if not vectors:
            raise ValueError("Empty vector list provided")
        
        # Run dimension reduction
        reduced_vectors = DimensionReduction.reduce_dimensions(
            vectors=vectors,
            algorithm=algorithm,
            params=params
        )
        
        # Get output dimensions (default to 3 if not specified)
        dimensions = params.get("dimensions", 3)
        
        return {
            "reduced_vectors": reduced_vectors,
            "algorithm": algorithm,
            "dimensions": dimensions,
            "processing_time": time.time() - start_time
        }
    except Exception as e:
        logger.error(f"Error reducing dimensions: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Dimension reduction failed: {str(e)}"
        )

@app.post("/visualization/clustering", response_model=ClusteringResponse)
def cluster_vectors(request: ClusteringRequest):
    """Cluster vectors using various clustering algorithms"""
    start_time = time.time()
    
    try:
        # Extract parameters
        vectors = request.vectors
        document_ids = request.document_ids
        algorithm = request.algorithm
        params = request.params
        
        # Validate input
        if not vectors:
            raise ValueError("Empty vector list provided")
        
        if len(vectors) != len(document_ids):
            raise ValueError(f"Vector count ({len(vectors)}) and document ID count ({len(document_ids)}) must match")
        
        # Run clustering
        result = ClusterAnalysis.cluster_vectors(
            vectors=vectors,
            document_ids=document_ids,
            algorithm=algorithm,
            params=params
        )
        
        # Add processing time
        result["processing_time"] = time.time() - start_time
        
        return result
    except Exception as e:
        logger.error(f"Error clustering vectors: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Clustering failed: {str(e)}"
        )

@app.get("/visualization/gpu-capabilities", response_model=GPUCapabilitiesResponse)
def get_gpu_capabilities():
    """Check GPU acceleration capabilities"""
    try:
        capabilities = DimensionReduction.detect_gpu_availability()
        return capabilities
    except Exception as e:
        logger.error(f"Error detecting GPU capabilities: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"GPU detection failed: {str(e)}"
        )

@app.post("/rag/answer", response_model=RAGResponse)
async def generate_rag_answer(request: RAGRequest, background_tasks: BackgroundTasks):
    """
    Generate an answer to a query using Retrieval Augmented Generation (RAG).
    This combines document retrieval with LLM generation for context-aware responses.
    """
    start_time = time.time()
    
    try:
        # Validate tenant access (in a real implementation, this would check against a database)
        # In this example, we're just logging the organization ID
        logger.info(f"Processing RAG request for organization {request.org_id}")
        
        # Retrieve relevant documents
        context_documents = retrieve_and_rank(
            query=request.query,
            org_id=request.org_id,
            options=request.retrieval_options
        )
        
        # Get appropriate LLM provider
        provider = llm_registry.get_provider(request.provider)
        
        # Generate answer
        answer = provider.generate(
            prompt=request.query,
            context=context_documents,
            options=request.generation_options
        )
        
        # Format context for response
        context_items = []
        for doc in context_documents:
            context_items.append({
                "document_id": doc.get("document_id"),
                "title": doc.get("title", ""),
                "source": doc.get("source", ""),
                "text": doc.get("text", ""),
                "score": doc.get("score", 0.0)
            })
        
        # Calculate processing time
        processing_time = time.time() - start_time
        
        # Track metrics in background
        background_tasks.add_task(
            track_rag_metrics,
            org_id=request.org_id,
            query=request.query,
            response_time=processing_time,
            provider=request.provider
        )
        
        return {
            "answer": answer,
            "context": context_items,
            "metadata": {
                "provider": request.provider,
                "document_count": len(context_documents),
                "generation_options": request.generation_options
            },
            "query": request.query,
            "processing_time": processing_time
        }
    except Exception as e:
        logger.error(f"Error generating RAG answer: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"RAG generation failed: {str(e)}"
        )

@app.post("/rag/stream")
async def stream_rag_answer(request: RAGRequest):
    """
    Stream-generate an answer to a query using Retrieval Augmented Generation (RAG).
    Uses Server-Sent Events (SSE) for streaming responses.
    """
    try:
        # Retrieve relevant documents
        context_documents = retrieve_and_rank(
            query=request.query,
            org_id=request.org_id,
            options=request.retrieval_options
        )
        
        logger.info(f"Retrieved {len(context_documents)} documents for streaming RAG")
        
        # Get appropriate LLM provider
        provider = llm_registry.get_provider(request.provider)
        
        # Use streaming response
        return StreamingResponse(
            _stream_rag_response(
                provider=provider,
                prompt=request.query,
                context=context_documents,
                options=request.generation_options
            ),
            media_type="text/event-stream"
        )
    except Exception as e:
        logger.error(f"Error initiating streaming RAG: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"RAG streaming failed: {str(e)}"
        )

async def _stream_rag_response(provider, prompt, context, options):
    """Helper function to format streamed tokens as SSE events"""
    # Send metadata event at start
    metadata = {
        "context_docs": len(context),
        "provider": provider.__class__.__name__
    }
    yield f"event: metadata\ndata: {json.dumps(metadata)}\n\n"
    
    # Track metrics for first token time
    start_time = time.time()
    first_token_sent = False
    token_tracker = TokenRateTracker()
    
    try:
        async for token in provider.generate_stream(prompt, context, options):
            if not first_token_sent:
                first_token_time = time.time() - start_time
                logger.info(f"First token time: {first_token_time*1000:.2f}ms")
                first_token_sent = True
                
                # Send first_token_time as an event
                yield f"event: metric\ndata: {json.dumps({'first_token_time_ms': first_token_time*1000})}\n\n"
            
            # Track token rate
            token_tracker.add_token()
            
            # Periodically report token rate
            if token_tracker.tokens % 10 == 0:
                token_rate = token_tracker.get_rate()
                yield f"event: metric\ndata: {json.dumps({'token_rate': token_rate})}\n\n"
            
            # Send token as a data event
            yield f"data: {json.dumps({'token': token})}\n\n"
        
        # Complete event at the end
        total_time = time.time() - start_time
        final_metrics = {
            'completed': True,
            'total_time_ms': total_time * 1000,
            'token_count': token_tracker.tokens,
            'tokens_per_second': token_tracker.get_rate()
        }
        yield f"event: complete\ndata: {json.dumps(final_metrics)}\n\n"
    
    except Exception as e:
        # Error event if something goes wrong mid-stream
        error_info = {
            'error': str(e),
            'error_type': e.__class__.__name__
        }
        logger.error(f"Error during RAG streaming: {str(e)}")
        yield f"event: error\ndata: {json.dumps(error_info)}\n\n"


# Helper function for tracking RAG metrics
def track_rag_metrics(org_id: int, query: str, response_time: float, provider: Optional[str] = None):
    """
    Track metrics for RAG requests in the background.
    This doesn't block the main request and can be expanded for monitoring.
    """
    try:
        # In a production environment, this would write to a metrics database
        # For now, we just log the metrics
        logger.info(f"RAG Metrics - org_id: {org_id}, query_length: {len(query)}, "
                   f"response_time: {response_time:.2f}s, provider: {provider}")
        
        # Additional metrics that could be implemented:
        # - Store in time-series database
        # - Update provider success/failure rate
        # - Track response times for different query lengths
        # - Analyze performance by organization
    except Exception as e:
        logger.error(f"Error tracking RAG metrics: {str(e)}")


@app.get("/rag/providers", response_model=List[LLMProviderInfo])
def list_llm_providers():
    """Get a list of available LLM providers for RAG"""
    try:
        # Get available providers from registry
        providers = llm_registry.list_providers()
        default_provider = None
        
        # Try to get the default provider
        try:
            # When None is passed to get_provider, it returns the default
            provider = llm_registry.get_provider()
            if provider:
                # Get the class name to match with our list
                default_provider = provider.__class__.__name__.lower().replace('provider', '')
        except:
            # If we can't get the default, just continue without it
            pass
            
        # Format provider info for response
        provider_info = []
        for name in providers:
            info = {
                "name": name,
                "default": (name == default_provider)
            }
            provider_info.append(info)
            
        return provider_info
    except Exception as e:
        logger.error(f"Error listing LLM providers: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to list LLM providers: {str(e)}"
        )


if __name__ == "__main__":
    import uvicorn
    from config.settings import API_HOST, API_PORT
    
    uvicorn.run("app.main:app", host=API_HOST, port=API_PORT, reload=DEBUG)
