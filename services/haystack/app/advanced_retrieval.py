"""
Advanced Retrieval Techniques for Elite RAG.

Implements state-of-the-art retrieval strategies:
- RAG-Fusion: Multi-query generation + Reciprocal Rank Fusion
- HyDE: Hypothetical Document Embeddings
- Cross-encoder reranking: Pairwise relevance scoring
- Multi-hop retrieval: Iterative reasoning chains

These techniques significantly improve retrieval quality over naive
single-query semantic search.
"""

import logging
import time
import numpy as np
from typing import Dict, List, Optional, Any, Tuple, Union
from dataclasses import dataclass, field
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed

logger = logging.getLogger(__name__)


# =============================================================================
# DATA CLASSES
# =============================================================================

@dataclass
class RetrievalResult:
    """Unified retrieval result with scoring metadata."""
    id: str
    content: str
    score: float
    metadata: Dict[str, Any] = field(default_factory=dict)

    # Multi-stage scoring
    initial_score: Optional[float] = None
    fusion_score: Optional[float] = None
    rerank_score: Optional[float] = None

    # Source tracking
    collection: str = ""
    query_variant: Optional[str] = None
    retrieval_method: str = "semantic"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "content": self.content,
            "score": self.score,
            "metadata": self.metadata,
            "collection": self.collection,
            "retrieval_method": self.retrieval_method,
        }


@dataclass
class RetrievalConfig:
    """Configuration for retrieval pipeline."""
    # RAG-Fusion settings
    num_query_variants: int = 5
    fusion_k: int = 60  # RRF constant

    # Retrieval limits
    initial_k: int = 20  # Per query variant
    rerank_k: int = 50   # Before reranking
    final_k: int = 5     # Final results

    # Score thresholds
    min_score: float = 0.0

    # Feature flags
    use_rag_fusion: bool = True
    use_hyde: bool = False
    use_reranking: bool = True
    use_multi_hop: bool = False
    max_hops: int = 3


# =============================================================================
# RAG-FUSION: Multi-Query + Reciprocal Rank Fusion
# =============================================================================

class RAGFusion:
    """
    RAG-Fusion: Generate query variants and fuse results with RRF.

    Technique: Instead of single-query search, generate 5 variations
    of the query, retrieve for each, and fuse results using Reciprocal
    Rank Fusion (RRF) which is proven to outperform single-query search.

    Paper: "RAG-Fusion: A New Take on Retrieval Augmented Generation"
    """

    def __init__(self, llm_client=None):
        """
        Args:
            llm_client: LLM client for query generation (optional, uses default if None)
        """
        self.llm_client = llm_client
        self._query_cache: Dict[str, List[str]] = {}

    def generate_query_variants(
        self,
        query: str,
        num_variants: int = 5,
        context: Optional[str] = None
    ) -> List[str]:
        """
        Generate semantically diverse query variants.

        Args:
            query: Original user query
            num_variants: Number of variants to generate
            context: Optional conversation context

        Returns:
            List of query variants (includes original)
        """
        # Check cache
        cache_key = f"{query}:{num_variants}"
        if cache_key in self._query_cache:
            return self._query_cache[cache_key]

        variants = [query]  # Always include original

        # Try LLM-based generation
        if self.llm_client:
            try:
                generated = self._generate_with_llm(query, num_variants - 1, context)
                variants.extend(generated)
            except Exception as e:
                logger.warning(f"LLM query generation failed: {e}")
                variants.extend(self._generate_heuristic(query, num_variants - 1))
        else:
            # Fallback to heuristic generation
            variants.extend(self._generate_heuristic(query, num_variants - 1))

        # Cache and return
        self._query_cache[cache_key] = variants[:num_variants]
        return variants[:num_variants]

    def _generate_with_llm(
        self,
        query: str,
        num_variants: int,
        context: Optional[str] = None
    ) -> List[str]:
        """Generate variants using LLM."""
        prompt = f"""Generate {num_variants} alternative search queries for the following question.
Each variant should capture a different aspect or phrasing while maintaining the same intent.
Return only the queries, one per line.

Original question: {query}
{f'Context: {context}' if context else ''}

Alternative queries:"""

        try:
            from app.generation import get_llm_response
            response = get_llm_response(prompt, max_tokens=200)

            # Parse response into queries
            lines = response.strip().split('\n')
            variants = []
            for line in lines:
                line = line.strip()
                # Remove numbering and clean
                if line and not line.startswith('#'):
                    # Remove "1.", "2.", etc.
                    cleaned = line.lstrip('0123456789.-) ').strip()
                    if cleaned and len(cleaned) > 5:
                        variants.append(cleaned)

            return variants[:num_variants]
        except Exception as e:
            logger.warning(f"LLM generation failed: {e}")
            return []

    def _generate_heuristic(self, query: str, num_variants: int) -> List[str]:
        """Generate variants using heuristic rules."""
        variants = []

        # Question format variations
        question_starters = [
            "What is", "How does", "Why is", "When did",
            "Where is", "Who", "Which", "Can you explain"
        ]

        # Check if query is a question
        is_question = query.strip().endswith('?') or any(
            query.lower().startswith(s.lower()) for s in question_starters
        )

        # Generate variations based on query type
        words = query.split()

        if is_question:
            # Convert question to statement-like search
            for starter in question_starters:
                if query.lower().startswith(starter.lower()):
                    remainder = query[len(starter):].strip(' ?')
                    variants.append(remainder)
                    break

            # Add "explain" variant
            variants.append(f"explain {query.rstrip('?')}")

            # Add definition variant
            if 'what is' in query.lower():
                term = query.lower().replace('what is', '').strip(' ?')
                variants.append(f"{term} definition meaning")
        else:
            # Add question variants for statement
            variants.append(f"What is {query}?")
            variants.append(f"How does {query} work?")
            variants.append(f"explain {query}")

        # Add keyword-focused variant
        if len(words) > 3:
            # Extract likely important terms (longer words)
            important = [w for w in words if len(w) > 4]
            if important:
                variants.append(' '.join(important[:5]))

        # Deduplicate and limit
        seen = set()
        unique_variants = []
        for v in variants:
            v_lower = v.lower()
            if v_lower not in seen and v_lower != query.lower():
                seen.add(v_lower)
                unique_variants.append(v)

        return unique_variants[:num_variants]

    def reciprocal_rank_fusion(
        self,
        result_lists: List[Tuple[str, List[RetrievalResult]]],
        k: int = 60,
        weights: Optional[Dict[str, float]] = None
    ) -> List[RetrievalResult]:
        """
        Fuse multiple result lists using Reciprocal Rank Fusion.

        RRF Score = sum(weight / (k + rank)) for each list containing the doc

        Args:
            result_lists: List of (query_variant, results) tuples
            k: RRF constant (higher = more weight to lower ranks)
            weights: Optional weights per query variant

        Returns:
            Fused and sorted results
        """
        scores: Dict[str, float] = defaultdict(float)
        result_map: Dict[str, RetrievalResult] = {}

        for variant_name, results in result_lists:
            weight = weights.get(variant_name, 1.0) if weights else 1.0

            for rank, result in enumerate(results):
                # Create unique key
                key = f"{result.collection}:{result.id}"

                # RRF formula
                rrf_score = weight / (k + rank + 1)
                scores[key] += rrf_score

                # Store result (keep highest initial score)
                if key not in result_map or result.score > result_map[key].score:
                    result_map[key] = result

        # Apply fusion scores
        for key, result in result_map.items():
            result.initial_score = result.score
            result.fusion_score = scores[key]
            result.score = scores[key]  # Use fusion score as primary

        # Sort by fusion score
        fused = list(result_map.values())
        fused.sort(key=lambda r: r.score, reverse=True)

        return fused


# =============================================================================
# HyDE: Hypothetical Document Embeddings
# =============================================================================

class HyDE:
    """
    HyDE: Hypothetical Document Embeddings.

    Technique: Generate a hypothetical answer to the query using an LLM,
    then embed that hypothetical document and search for similar real
    documents. Often retrieves more relevant docs than query embedding.

    Paper: "Precise Zero-Shot Dense Retrieval without Relevance Labels"
    """

    def __init__(self, llm_client=None, embedder=None):
        """
        Args:
            llm_client: LLM client for hypothesis generation
            embedder: Embedding model
        """
        self.llm_client = llm_client
        self.embedder = embedder
        self._hypothesis_cache: Dict[str, str] = {}

    def generate_hypothesis(
        self,
        query: str,
        domain: Optional[str] = None,
        style: str = "informative"
    ) -> str:
        """
        Generate a hypothetical document that would answer the query.

        Args:
            query: User query
            domain: Optional domain hint (finance, science, etc.)
            style: Writing style (informative, technical, casual)

        Returns:
            Hypothetical document text
        """
        cache_key = f"{query}:{domain}:{style}"
        if cache_key in self._hypothesis_cache:
            return self._hypothesis_cache[cache_key]

        # Build prompt based on domain
        domain_context = ""
        if domain == "finance":
            domain_context = "You are a financial analyst writing about SEC filings and financial data. "
        elif domain == "science":
            domain_context = "You are a scientist writing a research paper abstract. "
        elif domain == "technical":
            domain_context = "You are a software engineer writing technical documentation. "

        prompt = f"""{domain_context}Write a short, factual paragraph that directly answers the following question.
Be specific and informative. Write as if this is from a real document.

Question: {query}

Answer:"""

        try:
            from app.generation import get_llm_response
            hypothesis = get_llm_response(prompt, max_tokens=300)

            # Clean up
            hypothesis = hypothesis.strip()

            # Cache and return
            self._hypothesis_cache[cache_key] = hypothesis
            return hypothesis

        except Exception as e:
            logger.warning(f"Hypothesis generation failed: {e}")
            # Fallback: expand query
            return f"This document discusses {query}. It provides detailed information about the topic."

    def embed_hypothesis(
        self,
        hypothesis: str,
        model_name: str = "base"
    ) -> np.ndarray:
        """
        Embed the hypothetical document.

        Args:
            hypothesis: Hypothetical document text
            model_name: Embedding model to use

        Returns:
            Embedding vector
        """
        if self.embedder:
            return self.embedder.embed(hypothesis)
        else:
            from app.embeddings import get_embedding
            return get_embedding(hypothesis, model_name=model_name)

    def generate_and_embed(
        self,
        query: str,
        domain: Optional[str] = None,
        model_name: str = "base"
    ) -> Tuple[str, np.ndarray]:
        """
        Generate hypothesis and return both text and embedding.

        Returns:
            (hypothesis_text, embedding_vector)
        """
        hypothesis = self.generate_hypothesis(query, domain)
        embedding = self.embed_hypothesis(hypothesis, model_name)
        return hypothesis, embedding


# =============================================================================
# CROSS-ENCODER RERANKING
# =============================================================================

class CrossEncoderReranker:
    """
    Cross-encoder reranking for precision improvement.

    Technique: Use a cross-encoder model that takes (query, document) pairs
    and produces a relevance score. More accurate than bi-encoder similarity
    but slower, so used to rerank top-N results.

    Uses: sentence-transformers/ms-marco-MiniLM-L-6-v2 (or similar)
    """

    def __init__(self, model_name: str = "cross-encoder/ms-marco-MiniLM-L-6-v2"):
        """
        Args:
            model_name: Cross-encoder model name
        """
        self.model_name = model_name
        self.model = None

    def _load_model(self):
        """Lazy load the cross-encoder model."""
        if self.model is None:
            try:
                from sentence_transformers import CrossEncoder
                logger.info(f"Loading cross-encoder: {self.model_name}")
                self.model = CrossEncoder(self.model_name)
                logger.info("Cross-encoder loaded")
            except ImportError:
                logger.warning("sentence-transformers not available for cross-encoder")
                self.model = "unavailable"

    def rerank(
        self,
        query: str,
        results: List[RetrievalResult],
        top_k: Optional[int] = None
    ) -> List[RetrievalResult]:
        """
        Rerank results using cross-encoder.

        Args:
            query: Original query
            results: Results to rerank
            top_k: Return top K results after reranking

        Returns:
            Reranked results
        """
        if not results:
            return []

        self._load_model()

        if self.model == "unavailable":
            logger.warning("Cross-encoder unavailable, returning original order")
            return results[:top_k] if top_k else results

        # Prepare pairs
        pairs = [(query, r.content) for r in results]

        try:
            # Score all pairs
            scores = self.model.predict(pairs)

            # Apply scores
            for result, score in zip(results, scores):
                result.rerank_score = float(score)
                result.score = float(score)  # Use rerank as primary

            # Sort by rerank score
            results.sort(key=lambda r: r.score, reverse=True)

            return results[:top_k] if top_k else results

        except Exception as e:
            logger.error(f"Reranking failed: {e}")
            return results[:top_k] if top_k else results


# =============================================================================
# MULTI-HOP RETRIEVAL
# =============================================================================

class MultiHopRetriever:
    """
    Multi-hop retrieval for complex reasoning queries.

    Technique: For queries requiring information from multiple sources,
    iteratively retrieve, extract entities/facts, and generate follow-up
    queries until sufficient information is gathered.

    Example: "Compare Apple and Microsoft's revenue growth over the last 3 years"
    - Hop 1: Get Apple revenue data
    - Hop 2: Get Microsoft revenue data
    - Hop 3: Synthesize comparison
    """

    def __init__(self, llm_client=None, retriever=None):
        """
        Args:
            llm_client: LLM for query decomposition
            retriever: Base retriever for each hop
        """
        self.llm_client = llm_client
        self.retriever = retriever

    def decompose_query(self, query: str) -> List[str]:
        """
        Decompose complex query into sub-queries.

        Args:
            query: Complex user query

        Returns:
            List of sub-queries
        """
        # Simple heuristic decomposition
        sub_queries = [query]

        # Check for comparison patterns
        comparison_words = ["compare", "vs", "versus", "difference between", "compared to"]
        for word in comparison_words:
            if word in query.lower():
                # Try to extract entities
                parts = query.lower().split(word)
                if len(parts) >= 2:
                    entity1 = parts[0].strip()
                    entity2 = parts[1].strip()

                    # Create focused queries
                    base_topic = self._extract_topic(query)
                    if entity1 and entity2:
                        sub_queries = [
                            f"{entity1} {base_topic}",
                            f"{entity2} {base_topic}",
                            query  # Original for context
                        ]
                break

        # Check for multi-part questions
        if " and " in query and any(q in query.lower() for q in ["how", "what", "why"]):
            parts = query.split(" and ")
            if len(parts) == 2:
                sub_queries = [parts[0].strip() + "?", "and " + parts[1].strip()]

        return sub_queries

    def _extract_topic(self, query: str) -> str:
        """Extract the main topic from a comparison query."""
        topic_words = ["revenue", "profit", "growth", "performance", "sales",
                       "stock", "market", "earnings", "income"]

        query_lower = query.lower()
        for word in topic_words:
            if word in query_lower:
                return word

        return ""

    def retrieve_multi_hop(
        self,
        query: str,
        max_hops: int = 3,
        results_per_hop: int = 5
    ) -> Tuple[List[RetrievalResult], List[Dict]]:
        """
        Perform multi-hop retrieval.

        Args:
            query: Original complex query
            max_hops: Maximum retrieval hops
            results_per_hop: Results to keep per hop

        Returns:
            (all_results, hop_trace)
        """
        all_results = []
        hop_trace = []
        sub_queries = self.decompose_query(query)

        for hop, sub_query in enumerate(sub_queries[:max_hops]):
            hop_info = {
                "hop": hop + 1,
                "query": sub_query,
                "num_results": 0
            }

            if self.retriever:
                try:
                    results = self.retriever(sub_query, limit=results_per_hop)
                    all_results.extend(results)
                    hop_info["num_results"] = len(results)
                except Exception as e:
                    logger.warning(f"Hop {hop+1} retrieval failed: {e}")

            hop_trace.append(hop_info)

        # Deduplicate by ID
        seen = set()
        unique_results = []
        for r in all_results:
            if r.id not in seen:
                seen.add(r.id)
                unique_results.append(r)

        return unique_results, hop_trace


# =============================================================================
# UNIFIED ADVANCED RETRIEVER
# =============================================================================

class AdvancedRetriever:
    """
    Unified advanced retrieval pipeline.

    Orchestrates RAG-Fusion, HyDE, cross-encoder reranking, and multi-hop
    retrieval based on query characteristics and configuration.
    """

    def __init__(
        self,
        base_retriever=None,
        llm_client=None,
        embedder=None,
        config: Optional[RetrievalConfig] = None
    ):
        """
        Args:
            base_retriever: Base semantic retrieval function
            llm_client: LLM for query generation and HyDE
            embedder: Embedding function
            config: Retrieval configuration
        """
        self.base_retriever = base_retriever
        self.llm_client = llm_client
        self.embedder = embedder
        self.config = config or RetrievalConfig()

        # Initialize components
        self.rag_fusion = RAGFusion(llm_client)
        self.hyde = HyDE(llm_client, embedder)
        self.reranker = CrossEncoderReranker()
        self.multi_hop = MultiHopRetriever(llm_client)

    def retrieve(
        self,
        query: str,
        collection: str = None,
        org_id: int = None,
        config: Optional[RetrievalConfig] = None,
        **kwargs
    ) -> List[RetrievalResult]:
        """
        Perform advanced retrieval using configured techniques.

        Args:
            query: User query
            collection: Target collection
            org_id: Organization ID
            config: Override default config
            **kwargs: Additional retriever parameters

        Returns:
            List of retrieval results
        """
        start_time = time.time()
        cfg = config or self.config

        # Check for multi-hop trigger
        if cfg.use_multi_hop and self._needs_multi_hop(query):
            results, trace = self.multi_hop.retrieve_multi_hop(
                query,
                max_hops=cfg.max_hops,
                results_per_hop=cfg.initial_k
            )
            logger.info(f"Multi-hop retrieval: {len(trace)} hops, {len(results)} results")

            # Apply reranking
            if cfg.use_reranking and results:
                results = self.reranker.rerank(query, results, top_k=cfg.final_k)

            return results[:cfg.final_k]

        # RAG-Fusion retrieval
        if cfg.use_rag_fusion:
            results = self._rag_fusion_retrieve(query, collection, org_id, cfg, **kwargs)
        else:
            results = self._single_query_retrieve(query, collection, org_id, cfg, **kwargs)

        # Apply reranking
        if cfg.use_reranking and results:
            results = self.reranker.rerank(query, results, top_k=cfg.rerank_k)

        elapsed = time.time() - start_time
        logger.info(f"Advanced retrieval: {len(results)} results in {elapsed:.2f}s")

        return results[:cfg.final_k]

    def _rag_fusion_retrieve(
        self,
        query: str,
        collection: str,
        org_id: int,
        cfg: RetrievalConfig,
        **kwargs
    ) -> List[RetrievalResult]:
        """Execute RAG-Fusion retrieval."""
        # Generate query variants
        variants = self.rag_fusion.generate_query_variants(
            query,
            num_variants=cfg.num_query_variants
        )

        logger.info(f"RAG-Fusion with {len(variants)} query variants")

        # Retrieve for each variant
        result_lists = []

        for variant in variants:
            try:
                if self.base_retriever:
                    results = self.base_retriever(
                        variant,
                        collection=collection,
                        org_id=org_id,
                        limit=cfg.initial_k,
                        **kwargs
                    )

                    # Convert to RetrievalResult if needed
                    retrieval_results = []
                    for r in results:
                        if isinstance(r, RetrievalResult):
                            r.query_variant = variant
                            retrieval_results.append(r)
                        elif isinstance(r, dict):
                            retrieval_results.append(RetrievalResult(
                                id=r.get("id", ""),
                                content=r.get("content", r.get("text", "")),
                                score=r.get("score", 0.0),
                                metadata=r.get("metadata", {}),
                                collection=collection or "",
                                query_variant=variant,
                            ))

                    result_lists.append((variant, retrieval_results))

            except Exception as e:
                logger.warning(f"Retrieval failed for variant '{variant[:50]}...': {e}")

        # Fuse results
        if result_lists:
            fused = self.rag_fusion.reciprocal_rank_fusion(
                result_lists,
                k=cfg.fusion_k
            )
            return fused

        return []

    def _single_query_retrieve(
        self,
        query: str,
        collection: str,
        org_id: int,
        cfg: RetrievalConfig,
        **kwargs
    ) -> List[RetrievalResult]:
        """Execute single-query retrieval."""
        # Optional HyDE
        if cfg.use_hyde:
            hypothesis, embedding = self.hyde.generate_and_embed(query)
            kwargs["query_embedding"] = embedding
            logger.info("Using HyDE for retrieval")

        if self.base_retriever:
            results = self.base_retriever(
                query,
                collection=collection,
                org_id=org_id,
                limit=cfg.rerank_k,
                **kwargs
            )

            # Convert to RetrievalResult if needed
            retrieval_results = []
            for r in results:
                if isinstance(r, RetrievalResult):
                    retrieval_results.append(r)
                elif isinstance(r, dict):
                    retrieval_results.append(RetrievalResult(
                        id=r.get("id", ""),
                        content=r.get("content", r.get("text", "")),
                        score=r.get("score", 0.0),
                        metadata=r.get("metadata", {}),
                        collection=collection or "",
                    ))

            return retrieval_results

        return []

    def _needs_multi_hop(self, query: str) -> bool:
        """Detect if query requires multi-hop retrieval."""
        triggers = [
            "compare", "vs", "versus", "difference",
            "relationship between", "how does .* relate to",
            "and also", "as well as", "in addition to"
        ]

        query_lower = query.lower()
        return any(t in query_lower for t in triggers)


# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

def create_advanced_retriever(
    base_retriever=None,
    use_rag_fusion: bool = True,
    use_hyde: bool = False,
    use_reranking: bool = True
) -> AdvancedRetriever:
    """
    Factory function to create configured advanced retriever.

    Args:
        base_retriever: Base retrieval function
        use_rag_fusion: Enable RAG-Fusion
        use_hyde: Enable HyDE
        use_reranking: Enable cross-encoder reranking

    Returns:
        Configured AdvancedRetriever
    """
    config = RetrievalConfig(
        use_rag_fusion=use_rag_fusion,
        use_hyde=use_hyde,
        use_reranking=use_reranking
    )

    return AdvancedRetriever(
        base_retriever=base_retriever,
        config=config
    )
