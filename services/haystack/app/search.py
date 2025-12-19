import logging
import time
from functools import lru_cache
from typing import Dict, List, Any, Optional, Union, Tuple
import numpy as np

# Haystack 2.x Core imports - Official API structure
from haystack import Pipeline, Document
from haystack.document_stores.in_memory import InMemoryDocumentStore
from haystack.components.retrievers.in_memory import InMemoryBM25Retriever, InMemoryEmbeddingRetriever
from haystack.components.readers import ExtractiveReader
from haystack.components.builders import PromptBuilder
from haystack.components.generators import OpenAIGenerator

from config.settings import RETRIEVER_TOP_K, MAX_SEARCH_TIME_MS
from app.document_store import get_document_store
from app.embeddings import get_embedding_model, get_embedding_dimension
from app.query_parser import QueryParser

logger = logging.getLogger(__name__)

class HybridSearcher:
    """
    Hybrid search implementation that combines vector search with keyword search
    for more accurate results. Uses Haystack 2.x API with pipeline architecture.
    """
    
    def __init__(self, document_store=None, embedding_model=None):
        """
        Initialize the hybrid searcher with document store and embedding model.
        
        Args:
            document_store: Haystack document store instance
            embedding_model: Sentence transformer model for embeddings
        """
        self.document_store = document_store or get_document_store()
        self.embedding_model = embedding_model or get_embedding_model()
        self.query_parser = QueryParser()

        # Default search settings (must be set before creating retrievers)
        self.default_top_k = RETRIEVER_TOP_K
        self.max_search_time_ms = MAX_SEARCH_TIME_MS

        # Initialize retrievers with new Haystack 2.x API
        self.vector_retriever = self._create_vector_retriever()
        self.keyword_retriever = self._create_keyword_retriever()
        
    def _create_vector_retriever(self):
        """Create vector retriever using embedding model with Haystack 2.x API"""
        try:
            retriever = InMemoryEmbeddingRetriever(
                document_store=self.document_store,
                top_k=self.default_top_k
            )
            return retriever
        except Exception as e:
            logger.error(f"Error initializing vector retriever: {str(e)}")
            raise RuntimeError(f"Failed to initialize vector retriever: {str(e)}")
    
    def _create_keyword_retriever(self):
        """Create keyword retriever using BM25 with Haystack 2.x API"""
        try:
            retriever = InMemoryBM25Retriever(
                document_store=self.document_store,
                top_k=self.default_top_k
            )
            return retriever
        except Exception as e:
            logger.error(f"Error initializing keyword retriever: {str(e)}")
            raise RuntimeError(f"Failed to initialize keyword retriever: {str(e)}")
    
    def search(self, query: str, filters: Optional[Dict[str, Any]] = None, 
               top_k: int = None, early_termination: bool = True,
               vector_weight: float = None, keyword_weight: float = None) -> Tuple[List[Document], Dict[str, Any]]:
        """
        Perform hybrid search combining vector and keyword approaches.
        
        Args:
            query: The search query string
            filters: Optional filters to apply to the search
            top_k: Number of results to return (default: class default)
            early_termination: Whether to apply early termination for performance
            vector_weight: Optional override for vector search weight (0.0-1.0)
            keyword_weight: Optional override for keyword search weight (0.0-1.0)
            
        Returns:
            Tuple containing (results, metadata):
                - results: List of Document objects
                - metadata: Dictionary with search metadata
        """
        start_time = time.time()
        top_k = top_k or self.default_top_k
        
        # Parse the query
        parsed = self.query_parser.parse_query(query)
        query_complexity = parsed["complexity"]
        
        # Use provided weights or parser-suggested weights
        if vector_weight is None or keyword_weight is None:
            weights = parsed["weights"]
            vector_weight = weights["vector"]
            keyword_weight = weights["keyword"]
        
        # Normalize weights
        total_weight = vector_weight + keyword_weight
        if total_weight != 1.0:
            vector_weight = vector_weight / total_weight
            keyword_weight = keyword_weight / total_weight
        
        # Prepare metadata
        metadata = {
            "query": query,
            "parsed_query": parsed,
            "complexity": query_complexity,
            "vector_weight": vector_weight,
            "keyword_weight": keyword_weight,
            "early_termination": early_termination
        }
        
        # Fast path for simple queries: try vector search first
        if early_termination and query_complexity == "simple" and vector_weight > 0.7:
            try:
                vector_results = self._vector_search(
                    parsed["vector_query"], filters=filters, top_k=top_k*2
                )
                
                # If we got enough good results and are under time budget, return early
                current_time = time.time()
                elapsed_ms = (current_time - start_time) * 1000
                
                if len(vector_results) >= top_k and elapsed_ms < (self.max_search_time_ms * 0.5):
                    execution_time = (time.time() - start_time) * 1000
                    metadata.update({
                        "execution_time_ms": execution_time,
                        "method": "vector_only",
                        "early_terminated": True
                    })
                    
                    return vector_results[:top_k], metadata
            except Exception as e:
                logger.warning(f"Early vector search failed, continuing with hybrid: {str(e)}")
        
        # Run both search methods
        vector_results = []
        keyword_results = []
        vector_time_ms = 0
        keyword_time_ms = 0
        
        # Perform vector search if weight > 0
        if vector_weight > 0:
            vector_start = time.time()
            try:
                scaled_top_k = min(int(top_k * (1.5 / vector_weight)), top_k * 4)
                vector_results = self._vector_search(
                    parsed["vector_query"], filters=filters, top_k=scaled_top_k
                )
                vector_time_ms = (time.time() - vector_start) * 1000
            except Exception as e:
                logger.error(f"Vector search failed: {str(e)}")
                if keyword_weight > 0:
                    keyword_weight = 1.0
        
        # Perform keyword search if weight > 0
        if keyword_weight > 0:
            keyword_start = time.time()
            try:
                scaled_top_k = min(int(top_k * (1.5 / keyword_weight)), top_k * 4)
                keyword_results = self._keyword_search(
                    parsed["keyword_query"], filters=filters, top_k=scaled_top_k
                )
                keyword_time_ms = (time.time() - keyword_start) * 1000
            except Exception as e:
                logger.error(f"Keyword search failed: {str(e)}")
                if not vector_results:
                    raise RuntimeError("Both search methods failed") from e
        
        # Merge results with weighted scoring
        merged_results = self._merge_results(
            vector_results, keyword_results, 
            vector_weight, keyword_weight, 
            top_k
        )
        
        # Update metadata
        execution_time = (time.time() - start_time) * 1000
        metadata.update({
            "execution_time_ms": execution_time,
            "vector_time_ms": vector_time_ms,
            "keyword_time_ms": keyword_time_ms,
            "method": "hybrid",
            "vector_results_count": len(vector_results),
            "keyword_results_count": len(keyword_results),
            "merged_results_count": len(merged_results)
        })
        
        return merged_results, metadata
    
    def _vector_search(self, query: str, filters: Optional[Dict[str, Any]] = None, 
                     top_k: int = None) -> List[Document]:
        """Perform vector search using the embedding retriever with Haystack 2.x API"""
        top_k = top_k or self.default_top_k
        try:
            # Haystack 2.x uses run() method
            result = self.vector_retriever.run(
                query=query, 
                top_k=top_k,
                filters=filters
            )
            return result.get("documents", [])
        except Exception as e:
            logger.error(f"Vector search error: {str(e)}")
            return []
    
    def _keyword_search(self, query: str, filters: Optional[Dict[str, Any]] = None, 
                       top_k: int = None) -> List[Document]:
        """Perform keyword search using the BM25 retriever with Haystack 2.x API"""
        top_k = top_k or self.default_top_k
        try:
            # Haystack 2.x uses run() method
            result = self.keyword_retriever.run(
                query=query, 
                top_k=top_k,
                filters=filters
            )
            return result.get("documents", [])
        except Exception as e:
            logger.error(f"Keyword search error: {str(e)}")
            return []
    
    def _merge_results(self, vector_results: List[Document], keyword_results: List[Document], 
                     vector_weight: float, keyword_weight: float, top_k: int) -> List[Document]:
        """
        Merge results from vector and keyword search with weighted scoring.
        """
        # Create dictionaries for O(1) lookups
        vector_dict = {doc.id: doc for doc in vector_results}
        keyword_dict = {doc.id: doc for doc in keyword_results}
        
        # Get all unique document IDs
        all_doc_ids = set(vector_dict.keys()) | set(keyword_dict.keys())
        
        # Calculate merged scores
        merged_docs = []
        for doc_id in all_doc_ids:
            vector_doc = vector_dict.get(doc_id)
            keyword_doc = keyword_dict.get(doc_id)
            
            # Calculate weighted score
            if vector_doc and keyword_doc:
                # We have both scores, apply weights
                vector_score = vector_doc.score if hasattr(vector_doc, 'score') else 0
                keyword_score = keyword_doc.score if hasattr(keyword_doc, 'score') else 0
                weighted_score = (vector_score * vector_weight) + (keyword_score * keyword_weight)
                
                # Use the document from vector search as the base
                merged_doc = vector_doc
                merged_doc.score = weighted_score
                # Add a flag to indicate it was found by both methods
                if not hasattr(merged_doc, 'meta'):
                    merged_doc.meta = {}
                merged_doc.meta["search_method"] = "hybrid"
                
            elif vector_doc:
                # Only found by vector search
                merged_doc = vector_doc
                # If only from one source, reduce score slightly to prefer matches from both
                if hasattr(merged_doc, 'score'):
                    merged_doc.score = merged_doc.score * vector_weight * 0.95
                if not hasattr(merged_doc, 'meta'):
                    merged_doc.meta = {}
                merged_doc.meta["search_method"] = "vector_only"
                
            else:
                # Only found by keyword search
                merged_doc = keyword_doc
                # If only from one source, reduce score slightly to prefer matches from both
                if hasattr(merged_doc, 'score'):
                    merged_doc.score = merged_doc.score * keyword_weight * 0.95
                if not hasattr(merged_doc, 'meta'):
                    merged_doc.meta = {}
                merged_doc.meta["search_method"] = "keyword_only"
            
            merged_docs.append(merged_doc)
        
        # Sort merged results by score (descending) and take top_k
        merged_docs.sort(key=lambda doc: doc.score if hasattr(doc, 'score') else 0, reverse=True)
        return merged_docs[:top_k]

@lru_cache(maxsize=1)
def get_retriever():
    """
    Get a retriever instance (cached for efficiency).
    Uses InMemoryEmbeddingRetriever with Haystack 2.x API.
    """
    try:
        logger.info("Initializing retriever")
        document_store = get_document_store()
        
        retriever = InMemoryEmbeddingRetriever(
            document_store=document_store,
            top_k=RETRIEVER_TOP_K
        )
        
        logger.info("Retriever initialized successfully")
        return retriever
    except Exception as e:
        logger.error(f"Error initializing retriever: {str(e)}")
        raise RuntimeError(f"Failed to initialize retriever: {str(e)}")

@lru_cache(maxsize=1)
def get_reader():
    """
    Get a reader instance (cached for efficiency).
    Uses ExtractiveReader with Haystack 2.x API.
    """
    try:
        logger.info("Initializing reader")
        reader = ExtractiveReader(
            model="deepset/roberta-base-squad2",
            top_k=4
        )
        logger.info("Reader initialized successfully")
        return reader
    except Exception as e:
        logger.error(f"Error initializing reader: {str(e)}")
        raise RuntimeError(f"Failed to initialize reader: {str(e)}")

@lru_cache(maxsize=1)
def get_hybrid_searcher():
    """
    Get a hybrid searcher instance (cached for efficiency).
    """
    try:
        logger.info("Initializing hybrid searcher")
        document_store = get_document_store()
        embedding_model = get_embedding_model()
        
        searcher = HybridSearcher(
            document_store=document_store,
            embedding_model=embedding_model
        )
        
        logger.info("Hybrid searcher initialized successfully")
        return searcher
    except Exception as e:
        logger.error(f"Error initializing hybrid searcher: {str(e)}")
        raise RuntimeError(f"Failed to initialize hybrid searcher: {str(e)}")

@lru_cache(maxsize=1)
def get_search_pipeline():
    """
    Get a search pipeline instance using Haystack 2.x Pipeline API.
    """
    try:
        logger.info("Initializing search pipeline")
        retriever = get_retriever()
        
        # Haystack 2.x uses Pipeline class with add_component
        pipeline = Pipeline()
        pipeline.add_component("retriever", retriever)
        
        logger.info("Search pipeline initialized successfully")
        return pipeline
    except Exception as e:
        logger.error(f"Error initializing search pipeline: {str(e)}")
        raise RuntimeError(f"Failed to initialize search pipeline: {str(e)}")

@lru_cache(maxsize=1)
def get_qa_pipeline():
    """
    Get a question answering pipeline instance using Haystack 2.x Pipeline API.
    """
    try:
        logger.info("Initializing QA pipeline")
        retriever = get_retriever()
        reader = get_reader()
        
        # Haystack 2.x uses Pipeline class with add_component and connect
        pipeline = Pipeline()
        pipeline.add_component("retriever", retriever)
        pipeline.add_component("reader", reader)
        
        # Connect components
        pipeline.connect("retriever", "reader")
        
        logger.info("QA pipeline initialized successfully")
        return pipeline
    except Exception as e:
        logger.error(f"Error initializing QA pipeline: {str(e)}")
        raise RuntimeError(f"Failed to initialize QA pipeline: {str(e)}")

# Wrapper functions for compatibility with retrieval.py
def search_documents(query: str, filters: Optional[Dict[str, Any]] = None, top_k: int = None) -> List[Document]:
    """Simple document search wrapper using hybrid searcher"""
    searcher = get_hybrid_searcher()
    results, _ = searcher.search(query=query, filters=filters, top_k=top_k)
    return results

def hybrid_search_documents(query: str, filters: Optional[Dict[str, Any]] = None, top_k: int = None, 
                           vector_weight: float = 0.7, keyword_weight: float = 0.3) -> List[Document]:
    """Hybrid document search wrapper with configurable weights"""
    searcher = get_hybrid_searcher()
    results, _ = searcher.search(
        query=query, 
        filters=filters, 
        top_k=top_k,
        vector_weight=vector_weight,
        keyword_weight=keyword_weight
    )
    return results
