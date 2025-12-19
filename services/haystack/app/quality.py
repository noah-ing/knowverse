"""
Quality Assurance Module for Elite RAG.

Ensures response quality and factual accuracy:
- Hallucination Detection: Verify claims against sources
- Citation Verification: Check quotes and references
- Confidence Scoring: Multi-factor response reliability
- Source Attribution: Track provenance of information

Critical for enterprise use where accuracy is paramount.
"""

import re
import logging
from typing import Dict, List, Optional, Any, Tuple, Set
from dataclasses import dataclass, field
from enum import Enum
from difflib import SequenceMatcher

logger = logging.getLogger(__name__)


# =============================================================================
# DATA STRUCTURES
# =============================================================================

class ClaimType(Enum):
    """Types of claims that can be verified."""
    FACTUAL = "factual"           # Verifiable facts
    NUMERICAL = "numerical"        # Numbers and statistics
    TEMPORAL = "temporal"          # Dates and time references
    QUOTATION = "quotation"        # Direct quotes
    ATTRIBUTION = "attribution"    # Attributed statements
    COMPARATIVE = "comparative"    # Comparisons between entities


class VerificationStatus(Enum):
    """Status of claim verification."""
    VERIFIED = "verified"          # Claim supported by sources
    UNVERIFIED = "unverified"      # Claim not found in sources
    CONTRADICTED = "contradicted"  # Sources contradict claim
    PARTIAL = "partial"            # Partially supported
    UNCERTAIN = "uncertain"        # Cannot determine


@dataclass
class Claim:
    """A verifiable claim extracted from response."""
    text: str
    claim_type: ClaimType
    confidence: float = 0.5

    # Extracted components
    subject: Optional[str] = None
    predicate: Optional[str] = None
    object: Optional[str] = None

    # For numerical claims
    value: Optional[float] = None
    unit: Optional[str] = None

    # Verification results
    status: VerificationStatus = VerificationStatus.UNCERTAIN
    supporting_evidence: List[str] = field(default_factory=list)
    contradicting_evidence: List[str] = field(default_factory=list)


@dataclass
class Citation:
    """A citation to verify."""
    text: str
    source_id: Optional[str] = None
    source_title: Optional[str] = None

    # Verification
    verified: bool = False
    match_score: float = 0.0
    matched_text: Optional[str] = None


@dataclass
class QualityReport:
    """Complete quality assessment of a response."""
    response: str
    sources: List[Dict[str, Any]]

    # Claims analysis
    total_claims: int = 0
    verified_claims: int = 0
    unverified_claims: int = 0
    contradicted_claims: int = 0
    claims: List[Claim] = field(default_factory=list)

    # Citations analysis
    total_citations: int = 0
    verified_citations: int = 0
    citations: List[Citation] = field(default_factory=list)

    # Overall scores
    factual_score: float = 0.0      # 0-1, how factual is response
    source_coverage: float = 0.0    # 0-1, how well sources cover claims
    confidence_score: float = 0.0   # 0-1, overall confidence
    hallucination_risk: float = 0.0  # 0-1, risk of hallucination

    # Warnings
    warnings: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "total_claims": self.total_claims,
            "verified_claims": self.verified_claims,
            "unverified_claims": self.unverified_claims,
            "factual_score": self.factual_score,
            "source_coverage": self.source_coverage,
            "confidence_score": self.confidence_score,
            "hallucination_risk": self.hallucination_risk,
            "warnings": self.warnings,
        }


# =============================================================================
# CLAIM EXTRACTOR
# =============================================================================

class ClaimExtractor:
    """
    Extract verifiable claims from text.

    Identifies statements that can be fact-checked against sources.
    """

    # Patterns for different claim types
    NUMERICAL_PATTERNS = [
        r"(\$[\d,]+(?:\.\d+)?(?:\s*(?:million|billion|trillion|M|B|T))?)",
        r"(\d+(?:\.\d+)?%)",
        r"(\d+(?:\.\d+)?\s*(?:million|billion|trillion))",
        r"([\d,]+(?:\.\d+)?)\s*(dollars|USD|revenue|profit|income)",
    ]

    TEMPORAL_PATTERNS = [
        r"(in|since|during|as of)\s+(Q[1-4]\s*\d{4}|\d{4}|January|February|March|April|May|June|July|August|September|October|November|December\s*\d{4})",
        r"(last|this|next)\s+(year|quarter|month|week)",
    ]

    ATTRIBUTION_PATTERNS = [
        r"(according to|per|as stated by|as reported by)\s+([^,.]+)",
        r"([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+(said|stated|reported|announced)",
    ]

    QUOTATION_PATTERNS = [
        r'"([^"]+)"',
        r"'([^']+)'",
    ]

    def __init__(self):
        self._numerical_patterns = [re.compile(p, re.IGNORECASE) for p in self.NUMERICAL_PATTERNS]
        self._temporal_patterns = [re.compile(p, re.IGNORECASE) for p in self.TEMPORAL_PATTERNS]
        self._attribution_patterns = [re.compile(p, re.IGNORECASE) for p in self.ATTRIBUTION_PATTERNS]
        self._quotation_patterns = [re.compile(p) for p in self.QUOTATION_PATTERNS]

    def extract_claims(self, text: str) -> List[Claim]:
        """
        Extract all verifiable claims from text.

        Args:
            text: Response text to analyze

        Returns:
            List of extracted claims
        """
        claims = []

        # Split into sentences for context
        sentences = re.split(r'(?<=[.!?])\s+', text)

        for sentence in sentences:
            # Extract numerical claims
            for pattern in self._numerical_patterns:
                for match in pattern.finditer(sentence):
                    claims.append(Claim(
                        text=sentence,
                        claim_type=ClaimType.NUMERICAL,
                        confidence=0.8,
                        value=self._parse_number(match.group()),
                    ))

            # Extract temporal claims
            for pattern in self._temporal_patterns:
                for match in pattern.finditer(sentence):
                    claims.append(Claim(
                        text=sentence,
                        claim_type=ClaimType.TEMPORAL,
                        confidence=0.7,
                    ))

            # Extract attributed claims
            for pattern in self._attribution_patterns:
                for match in pattern.finditer(sentence):
                    claims.append(Claim(
                        text=sentence,
                        claim_type=ClaimType.ATTRIBUTION,
                        confidence=0.85,
                    ))

            # Extract quotations
            for pattern in self._quotation_patterns:
                for match in pattern.finditer(sentence):
                    claims.append(Claim(
                        text=match.group(1),
                        claim_type=ClaimType.QUOTATION,
                        confidence=0.9,
                    ))

        # Deduplicate by text
        seen = set()
        unique_claims = []
        for claim in claims:
            key = (claim.text[:100], claim.claim_type)
            if key not in seen:
                seen.add(key)
                unique_claims.append(claim)

        return unique_claims

    def _parse_number(self, text: str) -> Optional[float]:
        """Parse a number from text."""
        # Remove formatting
        clean = re.sub(r'[$,]', '', text)

        # Handle multipliers
        multipliers = {
            'million': 1_000_000, 'm': 1_000_000,
            'billion': 1_000_000_000, 'b': 1_000_000_000,
            'trillion': 1_000_000_000_000, 't': 1_000_000_000_000,
        }

        for mult_name, mult_value in multipliers.items():
            if mult_name in clean.lower():
                clean = re.sub(rf'\s*{mult_name}\s*', '', clean, flags=re.IGNORECASE)
                try:
                    return float(clean) * mult_value
                except ValueError:
                    pass

        try:
            return float(clean)
        except ValueError:
            return None


# =============================================================================
# CLAIM VERIFIER
# =============================================================================

class ClaimVerifier:
    """
    Verify claims against source documents.

    Uses text matching and semantic similarity to check claims.
    """

    def __init__(self, similarity_threshold: float = 0.6):
        self.similarity_threshold = similarity_threshold

    def verify_claim(
        self,
        claim: Claim,
        sources: List[Dict[str, Any]]
    ) -> Claim:
        """
        Verify a single claim against sources.

        Args:
            claim: Claim to verify
            sources: List of source documents

        Returns:
            Claim with updated verification status
        """
        if not sources:
            claim.status = VerificationStatus.UNCERTAIN
            return claim

        # Combine all source text
        source_texts = []
        for source in sources:
            content = source.get("content", source.get("text", ""))
            if content:
                source_texts.append(content)

        all_source_text = " ".join(source_texts).lower()

        # Verification strategy depends on claim type
        if claim.claim_type == ClaimType.NUMERICAL:
            return self._verify_numerical(claim, sources, all_source_text)
        elif claim.claim_type == ClaimType.QUOTATION:
            return self._verify_quotation(claim, source_texts)
        else:
            return self._verify_general(claim, all_source_text)

    def _verify_numerical(
        self,
        claim: Claim,
        sources: List[Dict[str, Any]],
        source_text: str
    ) -> Claim:
        """Verify numerical claims."""
        if claim.value is None:
            claim.status = VerificationStatus.UNCERTAIN
            return claim

        # Look for similar numbers in sources
        # Allow for some variance (10%)
        target = claim.value
        tolerance = target * 0.1

        # Find all numbers in sources
        numbers = re.findall(r'[\d,]+(?:\.\d+)?', source_text)

        for num_str in numbers:
            try:
                num = float(num_str.replace(',', ''))
                # Check various scales
                for scale in [1, 1e6, 1e9, 1e12]:
                    scaled_num = num * scale
                    if abs(scaled_num - target) <= tolerance:
                        claim.status = VerificationStatus.VERIFIED
                        claim.supporting_evidence.append(f"Found: {num_str}")
                        return claim
            except ValueError:
                continue

        # Not found - check if contradicting number exists
        claim.status = VerificationStatus.UNVERIFIED
        return claim

    def _verify_quotation(
        self,
        claim: Claim,
        source_texts: List[str]
    ) -> Claim:
        """Verify quoted text exists in sources."""
        quote = claim.text.lower()

        best_match = 0.0
        for source in source_texts:
            source_lower = source.lower()

            # Exact match
            if quote in source_lower:
                claim.status = VerificationStatus.VERIFIED
                claim.supporting_evidence.append("Exact match found")
                return claim

            # Fuzzy match
            ratio = SequenceMatcher(None, quote, source_lower).ratio()
            if ratio > best_match:
                best_match = ratio

        if best_match > 0.8:
            claim.status = VerificationStatus.PARTIAL
            claim.supporting_evidence.append(f"Similar text found ({best_match:.0%} match)")
        else:
            claim.status = VerificationStatus.UNVERIFIED

        return claim

    def _verify_general(
        self,
        claim: Claim,
        source_text: str
    ) -> Claim:
        """General verification using text matching."""
        claim_lower = claim.text.lower()

        # Extract key terms from claim
        words = set(re.findall(r'\b\w{4,}\b', claim_lower))

        # Count how many key terms appear in sources
        matches = sum(1 for word in words if word in source_text)
        coverage = matches / max(len(words), 1)

        if coverage > 0.7:
            claim.status = VerificationStatus.VERIFIED
        elif coverage > 0.4:
            claim.status = VerificationStatus.PARTIAL
        else:
            claim.status = VerificationStatus.UNVERIFIED

        return claim

    def verify_all_claims(
        self,
        claims: List[Claim],
        sources: List[Dict[str, Any]]
    ) -> List[Claim]:
        """Verify all claims against sources."""
        return [self.verify_claim(claim, sources) for claim in claims]


# =============================================================================
# CITATION VERIFIER
# =============================================================================

class CitationVerifier:
    """
    Verify citations and references in responses.

    Ensures quoted content actually comes from cited sources.
    """

    def __init__(self, match_threshold: float = 0.7):
        self.match_threshold = match_threshold

    def extract_citations(self, text: str) -> List[Citation]:
        """Extract citations from response text."""
        citations = []

        # Pattern: "text" (Source) or "text" [Source]
        patterns = [
            r'"([^"]+)"\s*\(([^)]+)\)',
            r'"([^"]+)"\s*\[([^\]]+)\]',
            r"'([^']+)'\s*-\s*([^,.]+)",
        ]

        for pattern in patterns:
            for match in re.finditer(pattern, text):
                citations.append(Citation(
                    text=match.group(1),
                    source_title=match.group(2).strip()
                ))

        return citations

    def verify_citation(
        self,
        citation: Citation,
        sources: List[Dict[str, Any]]
    ) -> Citation:
        """
        Verify a citation against sources.

        Args:
            citation: Citation to verify
            sources: Available source documents

        Returns:
            Citation with verification results
        """
        cited_text = citation.text.lower()

        best_match = 0.0
        best_source = None
        matched_text = None

        for source in sources:
            content = source.get("content", source.get("text", ""))
            if not content:
                continue

            content_lower = content.lower()

            # Check for exact match
            if cited_text in content_lower:
                citation.verified = True
                citation.match_score = 1.0
                citation.matched_text = citation.text
                citation.source_id = source.get("id", source.get("document_id"))
                return citation

            # Fuzzy match
            ratio = SequenceMatcher(None, cited_text, content_lower).ratio()
            if ratio > best_match:
                best_match = ratio
                best_source = source

                # Find the best matching substring
                if ratio > 0.5:
                    matched_text = self._find_best_match(cited_text, content)

        if best_match >= self.match_threshold:
            citation.verified = True
            citation.match_score = best_match
            citation.matched_text = matched_text
            if best_source:
                citation.source_id = best_source.get("id", best_source.get("document_id"))
        else:
            citation.verified = False
            citation.match_score = best_match

        return citation

    def _find_best_match(
        self,
        target: str,
        source: str,
        window_size: int = 200
    ) -> Optional[str]:
        """Find the best matching substring in source."""
        target_lower = target.lower()
        source_lower = source.lower()

        best_ratio = 0.0
        best_match = None

        # Sliding window
        for i in range(0, len(source_lower) - len(target_lower), 50):
            window = source_lower[i:i + len(target_lower) + window_size]
            ratio = SequenceMatcher(None, target_lower, window).ratio()

            if ratio > best_ratio:
                best_ratio = ratio
                best_match = source[i:i + len(target) + window_size]

        return best_match


# =============================================================================
# HALLUCINATION DETECTOR
# =============================================================================

class HallucinationDetector:
    """
    Detect potential hallucinations in LLM responses.

    Uses multiple signals:
    - Claim verification against sources
    - Specificity vs. source support ratio
    - Internal consistency
    """

    def __init__(self):
        self.claim_extractor = ClaimExtractor()
        self.claim_verifier = ClaimVerifier()
        self.citation_verifier = CitationVerifier()

    def analyze(
        self,
        response: str,
        sources: List[Dict[str, Any]],
        query: Optional[str] = None
    ) -> QualityReport:
        """
        Analyze response for hallucination risk.

        Args:
            response: LLM response text
            sources: Retrieved source documents
            query: Original query (for relevance check)

        Returns:
            QualityReport with detailed analysis
        """
        report = QualityReport(response=response, sources=sources)

        # Extract and verify claims
        claims = self.claim_extractor.extract_claims(response)
        verified_claims = self.claim_verifier.verify_all_claims(claims, sources)

        report.claims = verified_claims
        report.total_claims = len(verified_claims)
        report.verified_claims = sum(
            1 for c in verified_claims
            if c.status in [VerificationStatus.VERIFIED, VerificationStatus.PARTIAL]
        )
        report.unverified_claims = sum(
            1 for c in verified_claims
            if c.status == VerificationStatus.UNVERIFIED
        )
        report.contradicted_claims = sum(
            1 for c in verified_claims
            if c.status == VerificationStatus.CONTRADICTED
        )

        # Extract and verify citations
        citations = self.citation_verifier.extract_citations(response)
        for citation in citations:
            self.citation_verifier.verify_citation(citation, sources)

        report.citations = citations
        report.total_citations = len(citations)
        report.verified_citations = sum(1 for c in citations if c.verified)

        # Calculate scores
        report.factual_score = self._calculate_factual_score(report)
        report.source_coverage = self._calculate_source_coverage(response, sources)
        report.hallucination_risk = self._calculate_hallucination_risk(report)
        report.confidence_score = self._calculate_confidence(report)

        # Generate warnings
        report.warnings = self._generate_warnings(report)

        return report

    def _calculate_factual_score(self, report: QualityReport) -> float:
        """Calculate factual accuracy score."""
        if report.total_claims == 0:
            return 0.5  # Neutral if no claims

        verified_weight = report.verified_claims * 1.0
        partial_weight = 0  # Already included in verified
        unverified_weight = report.unverified_claims * -0.5
        contradicted_weight = report.contradicted_claims * -1.0

        score = (verified_weight + unverified_weight + contradicted_weight) / report.total_claims
        return max(0.0, min(1.0, 0.5 + score * 0.5))

    def _calculate_source_coverage(
        self,
        response: str,
        sources: List[Dict[str, Any]]
    ) -> float:
        """Calculate how well sources cover the response content."""
        if not sources:
            return 0.0

        response_words = set(re.findall(r'\b\w{4,}\b', response.lower()))
        if not response_words:
            return 0.0

        # Combine source text
        source_text = " ".join(
            s.get("content", s.get("text", ""))
            for s in sources
        ).lower()
        source_words = set(re.findall(r'\b\w{4,}\b', source_text))

        # Calculate coverage
        common = response_words.intersection(source_words)
        coverage = len(common) / len(response_words)

        return min(coverage * 1.2, 1.0)  # Slight boost, cap at 1.0

    def _calculate_hallucination_risk(self, report: QualityReport) -> float:
        """
        Calculate risk of hallucination.

        Higher score = higher risk
        """
        risk = 0.3  # Base risk

        # Increase risk for unverified claims
        if report.total_claims > 0:
            unverified_ratio = report.unverified_claims / report.total_claims
            risk += unverified_ratio * 0.4

        # Increase risk for contradicted claims
        if report.contradicted_claims > 0:
            risk += 0.2

        # Decrease risk for verified citations
        if report.total_citations > 0 and report.verified_citations > 0:
            risk -= (report.verified_citations / report.total_citations) * 0.2

        # Low source coverage increases risk
        if report.source_coverage < 0.3:
            risk += 0.2

        return max(0.0, min(1.0, risk))

    def _calculate_confidence(self, report: QualityReport) -> float:
        """Calculate overall confidence score."""
        # Combine multiple factors
        confidence = (
            report.factual_score * 0.4 +
            report.source_coverage * 0.3 +
            (1 - report.hallucination_risk) * 0.3
        )

        return max(0.0, min(1.0, confidence))

    def _generate_warnings(self, report: QualityReport) -> List[str]:
        """Generate warnings based on analysis."""
        warnings = []

        if report.hallucination_risk > 0.7:
            warnings.append("HIGH HALLUCINATION RISK: Response may contain unsupported claims")

        if report.contradicted_claims > 0:
            warnings.append(f"CONTRADICTIONS: {report.contradicted_claims} claims contradict sources")

        if report.unverified_claims > report.verified_claims:
            warnings.append("LOW VERIFICATION: Most claims could not be verified against sources")

        if report.source_coverage < 0.3:
            warnings.append("LOW COVERAGE: Response content poorly covered by retrieved sources")

        if report.total_citations > 0 and report.verified_citations == 0:
            warnings.append("CITATION WARNING: No citations could be verified")

        return warnings


# =============================================================================
# CONFIDENCE SCORER
# =============================================================================

class ConfidenceScorer:
    """
    Multi-factor confidence scoring for RAG responses.

    Considers:
    - Retrieval quality (source relevance)
    - Response-source alignment
    - Claim verification
    - Query coverage
    """

    def score(
        self,
        query: str,
        response: str,
        sources: List[Dict[str, Any]],
        quality_report: Optional[QualityReport] = None
    ) -> Dict[str, float]:
        """
        Calculate comprehensive confidence scores.

        Returns:
            Dict with various confidence metrics
        """
        scores = {
            "retrieval_confidence": self._score_retrieval(query, sources),
            "response_confidence": self._score_response(response, sources),
            "query_coverage": self._score_query_coverage(query, response),
        }

        # Include quality report scores if available
        if quality_report:
            scores["factual_confidence"] = quality_report.factual_score
            scores["source_coverage"] = quality_report.source_coverage
            scores["hallucination_risk"] = quality_report.hallucination_risk

        # Calculate overall confidence
        scores["overall_confidence"] = self._calculate_overall(scores)

        return scores

    def _score_retrieval(
        self,
        query: str,
        sources: List[Dict[str, Any]]
    ) -> float:
        """Score quality of retrieved sources."""
        if not sources:
            return 0.0

        query_terms = set(re.findall(r'\b\w{3,}\b', query.lower()))
        if not query_terms:
            return 0.5

        # Check how many sources contain query terms
        matching_sources = 0
        for source in sources:
            content = source.get("content", source.get("text", "")).lower()
            if any(term in content for term in query_terms):
                matching_sources += 1

        coverage = matching_sources / len(sources)
        return min(coverage * 1.2, 1.0)

    def _score_response(
        self,
        response: str,
        sources: List[Dict[str, Any]]
    ) -> float:
        """Score response alignment with sources."""
        if not sources or not response:
            return 0.0

        # Get response terms
        response_terms = set(re.findall(r'\b\w{4,}\b', response.lower()))

        # Get source terms
        source_text = " ".join(
            s.get("content", s.get("text", "")) for s in sources
        ).lower()
        source_terms = set(re.findall(r'\b\w{4,}\b', source_text))

        if not response_terms:
            return 0.5

        # Calculate overlap
        overlap = len(response_terms.intersection(source_terms))
        alignment = overlap / len(response_terms)

        return min(alignment * 1.3, 1.0)

    def _score_query_coverage(
        self,
        query: str,
        response: str
    ) -> float:
        """Score how well response addresses the query."""
        query_terms = set(re.findall(r'\b\w{3,}\b', query.lower()))
        response_lower = response.lower()

        if not query_terms:
            return 0.5

        # Check how many query terms appear in response
        covered = sum(1 for term in query_terms if term in response_lower)
        coverage = covered / len(query_terms)

        return min(coverage * 1.2, 1.0)

    def _calculate_overall(self, scores: Dict[str, float]) -> float:
        """Calculate weighted overall confidence."""
        weights = {
            "retrieval_confidence": 0.2,
            "response_confidence": 0.2,
            "query_coverage": 0.2,
            "factual_confidence": 0.2,
            "source_coverage": 0.1,
        }

        total_weight = 0.0
        weighted_sum = 0.0

        for key, weight in weights.items():
            if key in scores:
                weighted_sum += scores[key] * weight
                total_weight += weight

        if total_weight == 0:
            return 0.5

        return weighted_sum / total_weight


# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

_hallucination_detector: Optional[HallucinationDetector] = None
_confidence_scorer: Optional[ConfidenceScorer] = None


def get_hallucination_detector() -> HallucinationDetector:
    """Get or create singleton hallucination detector."""
    global _hallucination_detector
    if _hallucination_detector is None:
        _hallucination_detector = HallucinationDetector()
    return _hallucination_detector


def get_confidence_scorer() -> ConfidenceScorer:
    """Get or create singleton confidence scorer."""
    global _confidence_scorer
    if _confidence_scorer is None:
        _confidence_scorer = ConfidenceScorer()
    return _confidence_scorer


def check_response_quality(
    response: str,
    sources: List[Dict[str, Any]],
    query: Optional[str] = None
) -> QualityReport:
    """
    Convenience function to check response quality.

    Args:
        response: LLM response text
        sources: Retrieved source documents
        query: Original query

    Returns:
        QualityReport with analysis
    """
    detector = get_hallucination_detector()
    return detector.analyze(response, sources, query)
