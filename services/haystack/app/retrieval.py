"""
Context-aware document retrieval module for KnowVerse RAG implementation.
Responsible for retrieving relevant documents based on query intent and context.
"""

import logging
import time
from typing import Dict, List, Optional, Any, Union, Tuple
import re

from app.document_store import get_document_store
from app.query_parser import QueryParser
from app.search import search_documents, hybrid_search_documents
from app.embeddings import get_embedding, get_openai_embedding
from app.qdrant_client import get_qdrant_client

# Setup logging
logger = logging.getLogger(__name__)

class ContextRetriever:
    """
    Retrieves and formats context for RAG from the document store.
    Uses query analysis to determine the best retrieval strategy.
    """
    
    def __init__(self, document_store=None, query_parser=None, embedding_service=None):
        """
        Initialize the context retriever.
        
        Args:
            document_store: Document store instance or None to use default
            query_parser: Query parser instance or None to create new
            embedding_service: Embedding service or None to use default
        """
        self.document_store = document_store if document_store else get_document_store()
        self.query_parser = query_parser if query_parser else QueryParser()
        self.embedding_service = embedding_service
    
    def retrieve_context(self, query: str, org_id: int, options: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        """
        Retrieve context documents for a query.
        
        Args:
            query: User query
            org_id: Organization ID
            options: Retrieval options
            
        Returns:
            List of context documents with text and metadata
        """
        options = options or {}
        start_time = time.time()
        
        # Extract retrieval options
        max_documents = options.get("max_documents", 5)
        # Use very low threshold - cross-encoder reranking handles relevance filtering
        min_similarity = options.get("min_similarity")
        if min_similarity is None or min_similarity > 0.5:
            min_similarity = 0.01  # Very low for broad recall, reranker filters for precision
        strategy = options.get("strategy", "auto")
        
        # Parse query to understand intent and complexity
        parsed_query = self.query_parser.parse_query(query)
        logger.info(f"Query parsed with complexity: {parsed_query.get('complexity', 'unknown')}")
        
        # Choose retrieval strategy
        if strategy == "auto":
            # Auto-select strategy based on query characteristics
            complexity = parsed_query.get('complexity', 'simple')
            use_hybrid = complexity in ['complex', 'medium'] or len(parsed_query.get('exact_phrases', [])) > 0
        else:
            # Use explicit strategy
            use_hybrid = strategy.lower() in ["hybrid", "both"]
        
        # Determine collection and embedding type
        # Default to organization's documents (uses local embeddings)
        collection = options.get("collection", "org_documents")
        embedding_type = options.get("embedding_type", "local")

        # Get query embedding based on collection type
        if collection == "sec_edgar":
            # SEC EDGAR uses OpenAI ada-002 embeddings (1536d)
            query_embedding = get_openai_embedding(query, model='ada002')
            logger.info(f"Using OpenAI ada-002 embeddings (1536d) for SEC EDGAR")
        else:
            # Organization documents use local embeddings (768d)
            query_embedding = get_embedding(query)
            logger.info(f"Using local embeddings (768d) for {collection}")

        top_k = max_documents * 2  # Get more results initially for filtering

        # Search Qdrant directly (where actual documents are stored)
        logger.info(f"Searching Qdrant collection '{collection}' for org {org_id}: '{query}'")
        try:
            qdrant = get_qdrant_client()
            results = qdrant.search(
                org_id=org_id,
                query_vector=query_embedding,
                limit=top_k,
                score_threshold=min_similarity,
                collection=collection
            )
            logger.info(f"Qdrant returned {len(results)} results")
        except Exception as e:
            logger.error(f"Qdrant search failed: {e}")
            # Fallback to local search (will likely return empty)
            if use_hybrid:
                logger.info(f"Falling back to local hybrid search")
                results = hybrid_search_documents(query=query, filters=None, top_k=top_k)
            else:
                results = search_documents(query=query, filters=None, top_k=top_k)
        
        # Process and format results
        context = self._process_results(results, query, max_documents)
        
        logger.info(f"Retrieved {len(context)} context items in {time.time() - start_time:.2f}s")
        return context
    
    def _process_results(self, results: List[Any], query: str, max_documents: int) -> List[Dict[str, Any]]:
        """
        Process search results into context documents.

        Args:
            results: Search results (Haystack Document objects or dicts)
            query: Original query
            max_documents: Maximum number of documents to include

        Returns:
            Processed context documents
        """
        # Extract key terms from query for highlighting
        query_terms = self._extract_key_terms(query)

        # Process each result
        processed_results = []
        logger.info(f"Processing {len(results)} raw results")
        for i, result in enumerate(results[:max_documents * 2]):  # Process more than we need for better selection
            # Debug: log raw result
            if i == 0:
                logger.info(f"Sample result keys: {result.keys() if isinstance(result, dict) else 'not a dict'}")
                if isinstance(result, dict):
                    logger.info(f"Sample content length: {len(result.get('content', '') or '')}")

            # Handle both Haystack Document objects and dicts
            if hasattr(result, 'id'):
                # Haystack Document object
                document_id = result.id
                meta = getattr(result, 'meta', {}) or {}
                title = meta.get("title", "")
                source = meta.get("source") or meta.get("filename", "")
                text = getattr(result, 'content', "") or ""
                score = getattr(result, 'score', 0) or 0
            else:
                # Dict format
                document_id = result.get("id") or result.get("document_id")
                title = result.get("title", "")
                source = result.get("source") or result.get("filename", "")
                text = result.get("content") or result.get("text", "")
                score = result.get("score", 0)
            
            # For short texts, use directly; for longer texts, extract relevant passage
            if len(text) < 500:
                passage = text
                passage_score = 0.5
            else:
                passage, passage_score = self._extract_relevant_passage(text, query, query_terms)

            # Combine document and passage score
            combined_score = (score + passage_score) / 2

            final_text = passage if passage else text[:500]
            if i == 0:
                logger.info(f"Final text for first result: '{final_text[:100]}...' (len={len(final_text)})")

            processed_results.append({
                "document_id": document_id,
                "title": title,
                "source": source,
                "text": final_text,
                "score": combined_score,
                "full_text": text
            })
        
        # Sort by combined score and take top documents
        processed_results.sort(key=lambda x: x["score"], reverse=True)
        return processed_results[:max_documents]
    
    def _extract_key_terms(self, query: str) -> List[str]:
        """
        Extract key terms from a query for highlighting.
        
        Args:
            query: User query
            
        Returns:
            List of key terms
        """
        # Remove stop words and extract key terms
        stop_words = {'a', 'an', 'the', 'and', 'or', 'but', 'is', 'are', 'was', 'were', 
                     'be', 'been', 'being', 'in', 'on', 'at', 'to', 'for', 'with', 
                     'by', 'about', 'against', 'between', 'into', 'through', 'during', 
                     'before', 'after', 'above', 'below', 'from', 'up', 'down', 'of', 
                     'off', 'over', 'under', 'again', 'further', 'then', 'once', 'here', 
                     'there', 'when', 'where', 'why', 'how', 'all', 'any', 'both', 'each', 
                     'few', 'more', 'most', 'other', 'some', 'such', 'no', 'nor', 'not', 
                     'only', 'own', 'same', 'so', 'than', 'too', 'very', 's', 't', 'can', 
                     'will', 'just', 'don', 'should', 'now'}
        
        # Tokenize and filter
        tokens = re.findall(r'\b\w+\b', query.lower())
        key_terms = [term for term in tokens if term not in stop_words and len(term) > 2]
        
        # Add any exact phrases
        phrases = re.findall(r'"([^"]+)"', query)
        key_terms.extend(phrases)
        
        return key_terms
    
    def _extract_relevant_passage(self, text: str, query: str, key_terms: List[str]) -> Tuple[str, float]:
        """
        Extract the most relevant passage from text based on query.
        
        Args:
            text: Document text
            query: User query
            key_terms: Key terms from the query
            
        Returns:
            Tuple of (relevant_passage, relevance_score)
        """
        if not text:
            return "", 0.0
            
        # Split text into paragraphs
        paragraphs = re.split(r'\n\s*\n', text)
        
        # Compute term frequency for each paragraph
        scored_paragraphs = []
        for para in paragraphs:
            if len(para.strip()) < 10:  # Skip very short paragraphs
                continue
                
            para_lower = para.lower()
            term_count = sum(1 for term in key_terms if term.lower() in para_lower)
            # Include exact query match as a bonus
            exact_match = 3 if query.lower() in para_lower else 0
            
            # Score is a combination of term frequency and paragraph length
            # Prefer paragraphs with more key terms but penalize very long paragraphs
            score = (term_count + exact_match) / max(1, len(para) / 100)
            scored_paragraphs.append((para, score))
        
        # If no valid paragraphs, return a truncated version of the text
        if not scored_paragraphs:
            return text[:1000] + "..." if len(text) > 1000 else text, 0.1
        
        # Sort by score and select best
        scored_paragraphs.sort(key=lambda x: x[1], reverse=True)
        best_paragraph, score = scored_paragraphs[0]
        
        # If the best paragraph is too short, try to expand context
        if len(best_paragraph) < 200 and len(scored_paragraphs) > 1:
            # Find index of the best paragraph in original list
            try:
                best_idx = paragraphs.index(best_paragraph)
                context = []
                
                # Add preceding paragraph if available
                if best_idx > 0:
                    context.append(paragraphs[best_idx - 1])
                
                # Add best paragraph
                context.append(best_paragraph)
                
                # Add following paragraph if available
                if best_idx < len(paragraphs) - 1:
                    context.append(paragraphs[best_idx + 1])
                
                # Join with newlines
                expanded = "\n\n".join(context)
                # If the expanded context is too long, truncate
                if len(expanded) > 1500:
                    expanded = expanded[:1500] + "..."
                return expanded, score
            except ValueError:
                # Fall back to just the best paragraph if there was an issue
                pass
        
        # For very long paragraphs, truncate
        if len(best_paragraph) > 1500:
            return best_paragraph[:1500] + "...", score
            
        return best_paragraph, score


class DocumentRanker:
    """
    Ranks and filters documents for RAG based on relevance to query.
    """
    
    def rank_documents(self, documents: List[Dict[str, Any]], query: str) -> List[Dict[str, Any]]:
        """
        Rank documents based on their relevance to the query.
        
        Args:
            documents: List of documents to rank
            query: User query
            
        Returns:
            Ranked document list
        """
        # Documents are already ranked by the retriever
        # This method can be extended with more sophisticated ranking
        return documents
    
    def deduplicate_information(self, documents: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Remove redundant information from the document set.
        
        Args:
            documents: List of documents to deduplicate
            
        Returns:
            Deduplicated document list
        """
        if not documents:
            return []
            
        unique_documents = [documents[0]]
        
        # Simple n^2 deduplication based on content similarity
        for doc in documents[1:]:
            is_duplicate = False
            doc_text = doc.get("text", "").lower()
            
            for unique_doc in unique_documents:
                unique_text = unique_doc.get("text", "").lower()
                
                # Skip if same document ID
                if doc.get("document_id") == unique_doc.get("document_id"):
                    is_duplicate = True
                    break
                
                # Check text similarity (simple approach)
                if self._text_similarity(doc_text, unique_text) > 0.8:
                    is_duplicate = True
                    break
            
            if not is_duplicate:
                unique_documents.append(doc)
        
        return unique_documents
    
    def _text_similarity(self, text1: str, text2: str) -> float:
        """
        Calculate similarity between two text snippets.
        
        Args:
            text1: First text
            text2: Second text
            
        Returns:
            Similarity score (0-1)
        """
        # Simple Jaccard similarity on word sets
        if not text1 or not text2:
            return 0.0
            
        words1 = set(re.findall(r'\b\w+\b', text1.lower()))
        words2 = set(re.findall(r'\b\w+\b', text2.lower()))
        
        intersection = len(words1.intersection(words2))
        union = len(words1.union(words2))
        
        return intersection / max(1, union)


# Singleton instance
_context_retriever = None
_document_ranker = None

def get_context_retriever() -> ContextRetriever:
    """Get or create the singleton context retriever instance."""
    global _context_retriever
    if _context_retriever is None:
        _context_retriever = ContextRetriever()
    return _context_retriever

def get_document_ranker() -> DocumentRanker:
    """Get or create the singleton document ranker instance."""
    global _document_ranker
    if _document_ranker is None:
        _document_ranker = DocumentRanker()
    return _document_ranker

def retrieve_and_rank(query: str, org_id: int, options: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
    """
    Convenience function to retrieve and rank documents in one step.
    
    Args:
        query: User query
        org_id: Organization ID
        options: Retrieval and ranking options
        
    Returns:
        Ranked and processed context documents
    """
    retriever = get_context_retriever()
    ranker = get_document_ranker()
    
    # Retrieve initial context
    documents = retriever.retrieve_context(query, org_id, options)
    
    # Rank documents
    ranked_documents = ranker.rank_documents(documents, query)
    
    # Deduplicate if requested
    if options and options.get("deduplicate", True):
        ranked_documents = ranker.deduplicate_information(ranked_documents)
    
    return ranked_documents
