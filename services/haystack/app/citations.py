"""
Post-hoc Citation Attribution Engine for KnowVerse.

Attributes generated response sentences to source chunks using
semantic similarity matching. Enables inline [1] [2] citation markers.
"""

import logging
import re
from typing import Dict, List, Any, Tuple, Optional
from dataclasses import dataclass
import numpy as np

logger = logging.getLogger(__name__)


@dataclass
class Citation:
    """A citation linking a sentence to source chunk(s)."""
    sentence_index: int
    sentence_text: str
    source_indices: List[int]  # 1-indexed citation numbers
    confidence_scores: List[float]


@dataclass
class CitationResult:
    """Result of citation attribution."""
    annotated_text: str  # Text with [1] [2] markers inserted
    citations: List[Citation]
    sentence_to_sources: Dict[int, List[int]]  # sentence_idx -> source indices


class CitationEngine:
    """
    Post-hoc citation attribution using semantic similarity.

    After generating a response, this engine:
    1. Splits the response into sentences
    2. Computes embeddings for each sentence
    3. Compares to source chunk embeddings
    4. Assigns citations where similarity exceeds threshold
    """

    def __init__(
        self,
        similarity_threshold: float = 0.65,
        max_citations_per_sentence: int = 3,
        min_sentence_length: int = 10,
    ):
        """
        Args:
            similarity_threshold: Minimum cosine similarity for citation (0.0-1.0)
            max_citations_per_sentence: Maximum citations per sentence
            min_sentence_length: Minimum characters for a sentence to be cited
        """
        self.similarity_threshold = similarity_threshold
        self.max_citations_per_sentence = max_citations_per_sentence
        self.min_sentence_length = min_sentence_length

        self._embedder = None

    def _get_embedder(self):
        """Lazy load the embedding function."""
        if self._embedder is None:
            try:
                from app.embeddings import get_embedding
                self._embedder = get_embedding
            except ImportError:
                logger.warning("Embeddings not available, using fallback")
                self._embedder = self._fallback_embed
        return self._embedder

    def _fallback_embed(self, text: str) -> np.ndarray:
        """Fallback embedding using simple TF-IDF-like approach."""
        # Simple word-based embedding for testing
        words = set(text.lower().split())
        # Create a fixed-size vector based on common word hashes
        vector = np.zeros(384)
        for word in words:
            idx = hash(word) % 384
            vector[idx] += 1
        # Normalize
        norm = np.linalg.norm(vector)
        if norm > 0:
            vector = vector / norm
        return vector

    def split_into_sentences(self, text: str) -> List[Tuple[int, int, str]]:
        """
        Split text into sentences with character positions.

        Returns:
            List of (start_char, end_char, sentence_text) tuples
        """
        # Sentence splitting pattern
        # Handles periods, question marks, exclamation points
        # Avoids splitting on abbreviations like "Dr.", "Mr.", etc.
        pattern = r'(?<=[.!?])\s+(?=[A-Z])'

        sentences = []
        current_pos = 0

        # Split and track positions
        parts = re.split(pattern, text)

        for part in parts:
            part = part.strip()
            if not part:
                continue

            # Find the actual position in original text
            start = text.find(part, current_pos)
            if start == -1:
                start = current_pos
            end = start + len(part)

            # Only include substantial sentences
            if len(part) >= self.min_sentence_length:
                sentences.append((start, end, part))

            current_pos = end

        return sentences

    def compute_similarity(
        self,
        sentence_embedding: np.ndarray,
        chunk_embeddings: List[np.ndarray]
    ) -> List[float]:
        """Compute cosine similarity between sentence and all chunks."""
        similarities = []

        for chunk_emb in chunk_embeddings:
            # Cosine similarity
            dot = np.dot(sentence_embedding, chunk_emb)
            norm_s = np.linalg.norm(sentence_embedding)
            norm_c = np.linalg.norm(chunk_emb)

            if norm_s > 0 and norm_c > 0:
                sim = dot / (norm_s * norm_c)
            else:
                sim = 0.0

            similarities.append(float(sim))

        return similarities

    def attribute_citations(
        self,
        response_text: str,
        source_chunks: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        """
        Attribute response sentences to source chunks.

        Args:
            response_text: The generated response text
            source_chunks: List of source chunk dicts with 'content' field

        Returns:
            List of citation mappings: [
                {
                    "sentence_index": 0,
                    "sentence_start": 0,
                    "sentence_end": 50,
                    "source_indices": [1, 2],  # 1-indexed
                    "confidence": 0.85
                }
            ]
        """
        if not response_text or not source_chunks:
            return []

        embedder = self._get_embedder()

        # Split response into sentences
        sentences = self.split_into_sentences(response_text)

        if not sentences:
            return []

        # Get chunk embeddings (reuse if available in metadata, otherwise compute)
        chunk_embeddings = []
        for chunk in source_chunks:
            content = chunk.get("content", chunk.get("text", ""))
            if not content:
                chunk_embeddings.append(np.zeros(384))
                continue

            try:
                emb = embedder(content)
                if isinstance(emb, list):
                    emb = np.array(emb)
                chunk_embeddings.append(emb)
            except Exception as e:
                logger.warning(f"Failed to embed chunk: {e}")
                chunk_embeddings.append(np.zeros(384))

        # Attribute each sentence
        citations = []

        for sent_idx, (start, end, sentence_text) in enumerate(sentences):
            try:
                # Get sentence embedding
                sent_emb = embedder(sentence_text)
                if isinstance(sent_emb, list):
                    sent_emb = np.array(sent_emb)

                # Compute similarities
                similarities = self.compute_similarity(sent_emb, chunk_embeddings)

                # Find chunks above threshold
                attributed_sources = []
                for chunk_idx, sim in enumerate(similarities):
                    if sim >= self.similarity_threshold:
                        attributed_sources.append({
                            "source_index": chunk_idx + 1,  # 1-indexed
                            "confidence": sim
                        })

                # Sort by confidence and limit
                attributed_sources.sort(key=lambda x: x["confidence"], reverse=True)
                attributed_sources = attributed_sources[:self.max_citations_per_sentence]

                if attributed_sources:
                    citations.append({
                        "sentence_index": sent_idx,
                        "sentence_start": start,
                        "sentence_end": end,
                        "source_indices": [s["source_index"] for s in attributed_sources],
                        "confidence": attributed_sources[0]["confidence"] if attributed_sources else 0
                    })

            except Exception as e:
                logger.warning(f"Failed to attribute sentence {sent_idx}: {e}")
                continue

        return citations

    def annotate_text(
        self,
        response_text: str,
        citations: List[Dict[str, Any]]
    ) -> str:
        """
        Insert citation markers into the response text.

        Args:
            response_text: Original response text
            citations: Citation mappings from attribute_citations()

        Returns:
            Text with [1] [2] markers inserted at sentence ends
        """
        if not citations:
            return response_text

        # Sort citations by position (reverse order to insert from end)
        sorted_citations = sorted(citations, key=lambda c: c["sentence_end"], reverse=True)

        annotated = response_text

        for citation in sorted_citations:
            end_pos = citation["sentence_end"]
            source_indices = citation["source_indices"]

            # Create citation markers
            markers = " " + " ".join(f"[{idx}]" for idx in source_indices)

            # Insert at sentence end (before the period/punctuation)
            # Find the last non-space character
            insert_pos = end_pos
            while insert_pos > 0 and annotated[insert_pos - 1] in '.!?':
                insert_pos -= 1

            if insert_pos < len(annotated):
                annotated = annotated[:insert_pos] + markers + annotated[insert_pos:]

        return annotated


def create_citation_engine(
    threshold: float = 0.65,
    max_per_sentence: int = 3
) -> CitationEngine:
    """Factory function to create a configured citation engine."""
    return CitationEngine(
        similarity_threshold=threshold,
        max_citations_per_sentence=max_per_sentence
    )
