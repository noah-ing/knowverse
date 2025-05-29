import logging
import re
from typing import Dict, List, Tuple, Any
import numpy as np
from haystack.nodes import PreProcessor

logger = logging.getLogger(__name__)

class QueryParser:
    """
    Query parser for hybrid search that analyzes queries and extracts relevant components
    for different search methods.
    """
    
    # Common stop words to filter out for keyword extraction
    STOP_WORDS = set([
        "a", "an", "the", "and", "or", "but", "if", "then", "else", "when",
        "at", "from", "by", "for", "with", "about", "against", "between", "into",
        "through", "during", "before", "after", "above", "below", "to", "from",
        "up", "down", "in", "out", "on", "off", "over", "under", "again", "further",
        "then", "once", "here", "there", "when", "where", "why", "how", "all", "any",
        "both", "each", "few", "more", "most", "other", "some", "such", "no", "nor",
        "not", "only", "own", "same", "so", "than", "too", "very", "s", "t", "can",
        "will", "just", "don", "should", "now"
    ])
    
    # Patterns for query analysis
    EXACT_MATCH_PATTERN = re.compile(r'"([^"]*)"')
    REQUIRED_TERM_PATTERN = re.compile(r'\+(\w+)')
    EXCLUDED_TERM_PATTERN = re.compile(r'-(\w+)')
    BOOST_TERM_PATTERN = re.compile(r'(\w+)\^(\d+(?:\.\d+)?)')
    
    def __init__(self):
        self.preprocessor = PreProcessor(
            clean_empty_lines=True,
            clean_whitespace=True,
            clean_header_footer=False,
            split_by="word",
            split_length=200,
            split_respect_sentence_boundary=True
        )
    
    def parse_query(self, query_text: str) -> Dict[str, Any]:
        """
        Parse a query string into components for different search methods.
        
        Args:
            query_text: The search query to parse
            
        Returns:
            Dict containing parsed components:
                - vector_query: Full query text optimized for vector search
                - keyword_query: Query optimized for keyword search
                - exact_phrases: Phrases that should be matched exactly
                - required_terms: Terms that must be present
                - excluded_terms: Terms that must not be present
                - boosted_terms: Terms with importance boost
                - complexity: Estimated query complexity (simple, medium, complex)
                - weights: Suggested weights for hybrid search components
        """
        if not query_text or not query_text.strip():
            return {
                "vector_query": "",
                "keyword_query": "",
                "exact_phrases": [],
                "required_terms": [],
                "excluded_terms": [],
                "boosted_terms": {},
                "complexity": "simple",
                "weights": {"vector": 0.9, "keyword": 0.1}
            }
        
        # Extract exact phrases (in quotes)
        exact_phrases = self.EXACT_MATCH_PATTERN.findall(query_text)
        
        # Remove exact phrases from query for further processing
        working_query = self.EXACT_MATCH_PATTERN.sub('', query_text)
        
        # Extract required terms (+term)
        required_terms = self.REQUIRED_TERM_PATTERN.findall(working_query)
        working_query = self.REQUIRED_TERM_PATTERN.sub('', working_query)
        
        # Extract excluded terms (-term)
        excluded_terms = self.EXCLUDED_TERM_PATTERN.findall(working_query)
        working_query = self.EXCLUDED_TERM_PATTERN.sub('', working_query)
        
        # Extract boosted terms (term^2)
        boosted_matches = self.BOOST_TERM_PATTERN.findall(working_query)
        boosted_terms = {term: float(boost) for term, boost in boosted_matches}
        working_query = self.BOOST_TERM_PATTERN.sub(r'\1', working_query)
        
        # Clean the working query
        clean_query = working_query.strip()
        
        # Extract important keywords (removing stop words)
        keywords = [word.lower() for word in re.findall(r'\b\w+\b', clean_query) 
                   if word.lower() not in self.STOP_WORDS]
        
        # For vector search, use the full original query
        # For keyword search, optimize based on extracted terms
        vector_query = query_text
        
        # Build keyword query
        keyword_components = []
        
        # Add exact phrases with quotes
        for phrase in exact_phrases:
            keyword_components.append(f'"{phrase}"')
        
        # Add required terms with + prefix
        for term in required_terms:
            keyword_components.append(f'+{term}')
        
        # Add excluded terms with - prefix
        for term in excluded_terms:
            keyword_components.append(f'-{term}')
        
        # Add boosted terms with ^ suffix
        for term, boost in boosted_terms.items():
            keyword_components.append(f'{term}^{boost}')
        
        # Add remaining keywords
        keyword_components.extend(keywords)
        
        # Join all components
        keyword_query = ' '.join(keyword_components)
        
        # Determine query complexity
        complexity = self._determine_complexity(
            query_text, 
            exact_phrases, 
            required_terms, 
            excluded_terms, 
            boosted_terms, 
            keywords
        )
        
        # Determine weights based on complexity
        weights = self._calculate_weights(
            complexity,
            exact_phrases, 
            required_terms, 
            excluded_terms, 
            boosted_terms
        )
        
        return {
            "vector_query": vector_query,
            "keyword_query": keyword_query,
            "exact_phrases": exact_phrases,
            "required_terms": required_terms,
            "excluded_terms": excluded_terms,
            "boosted_terms": boosted_terms,
            "keywords": keywords,
            "complexity": complexity,
            "weights": weights
        }
    
    def _determine_complexity(
        self,
        query_text: str,
        exact_phrases: List[str],
        required_terms: List[str],
        excluded_terms: List[str],
        boosted_terms: Dict[str, float],
        keywords: List[str]
    ) -> str:
        """Determine the complexity of a query based on its components"""
        
        # Count words in the query
        word_count = len(re.findall(r'\b\w+\b', query_text))
        
        # Check for advanced search operators
        has_boolean = ' AND ' in query_text or ' OR ' in query_text or ' NOT ' in query_text
        has_advanced_operators = bool(exact_phrases or required_terms or excluded_terms or boosted_terms)
        
        if has_boolean or (has_advanced_operators and word_count > 5) or word_count > 15:
            return "complex"
        elif has_advanced_operators or word_count > 7:
            return "medium"
        else:
            return "simple"
    
    def _calculate_weights(
        self,
        complexity: str,
        exact_phrases: List[str],
        required_terms: List[str],
        excluded_terms: List[str],
        boosted_terms: Dict[str, float]
    ) -> Dict[str, float]:
        """Calculate the weights for vector vs keyword search based on query characteristics"""
        
        # Default weights based on complexity
        if complexity == "simple":
            vector_weight = 0.8
            keyword_weight = 0.2
        elif complexity == "medium":
            vector_weight = 0.6
            keyword_weight = 0.4
        else:  # complex
            vector_weight = 0.4
            keyword_weight = 0.6
        
        # Adjust weights based on presence of exact phrases
        if exact_phrases:
            keyword_weight += 0.1 * min(len(exact_phrases), 3)
            vector_weight -= 0.1 * min(len(exact_phrases), 3)
        
        # Adjust weights based on required/excluded terms
        if required_terms or excluded_terms:
            keyword_weight += 0.1
            vector_weight -= 0.1
        
        # Normalize weights to ensure they sum to 1.0
        total = vector_weight + keyword_weight
        vector_weight = vector_weight / total
        keyword_weight = keyword_weight / total
        
        return {
            "vector": round(vector_weight, 2),
            "keyword": round(keyword_weight, 2)
        }
    
    def split_into_chunks(self, text: str, chunk_size: int = 100) -> List[str]:
        """Split text into smaller chunks for processing"""
        result = self.preprocessor.process({"content": text})
        return [doc.content for doc in result]
