"""
Query Understanding Module for Elite RAG.

Provides intelligent query analysis:
- Intent Classification: Understand what the user wants
- Entity Extraction: Identify key entities in queries
- Domain Routing: Route to appropriate collections
- Query Decomposition: Break complex queries into sub-queries

This enables smarter retrieval and better response generation.
"""

import re
import logging
from typing import Dict, List, Optional, Any, Tuple, Set
from dataclasses import dataclass, field
from enum import Enum
from collections import defaultdict

logger = logging.getLogger(__name__)


# =============================================================================
# ENUMS AND DATA CLASSES
# =============================================================================

class QueryIntent(Enum):
    """Classification of query intent."""
    FACTUAL = "factual"           # What is X? Who did Y?
    ANALYTICAL = "analytical"      # Why did X happen? How does Y work?
    COMPARATIVE = "comparative"    # Compare X and Y, differences between
    PROCEDURAL = "procedural"      # How to do X? Steps to accomplish Y
    NAVIGATIONAL = "navigational"  # Find X, locate Y
    OPINION = "opinion"            # What do you think about X?
    CLARIFICATION = "clarification"  # Follow-up, can you explain more?


class EntityType(Enum):
    """Types of entities we extract."""
    COMPANY = "company"
    PERSON = "person"
    DATE = "date"
    LOCATION = "location"
    PRODUCT = "product"
    METRIC = "metric"
    MONEY = "money"
    PERCENT = "percent"
    TICKER = "ticker"
    FILING = "filing"
    TOPIC = "topic"


class Domain(Enum):
    """Knowledge domains for routing."""
    FINANCE = "finance"
    SCIENCE = "science"
    TECHNICAL = "technical"
    GENERAL = "general"
    CUSTOM = "custom"


@dataclass
class Entity:
    """Extracted entity."""
    text: str
    type: EntityType
    confidence: float = 1.0
    normalized: Optional[str] = None  # Normalized form
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class QueryAnalysis:
    """Complete query analysis result."""
    original_query: str
    cleaned_query: str

    # Intent
    intent: QueryIntent
    intent_confidence: float
    sub_intents: List[QueryIntent] = field(default_factory=list)

    # Entities
    entities: List[Entity] = field(default_factory=list)
    entity_focus: Optional[str] = None  # Main entity being asked about

    # Domain
    domain: Domain = Domain.GENERAL
    domain_confidence: float = 0.5
    suggested_collections: List[str] = field(default_factory=list)

    # Query structure
    is_question: bool = True
    is_complex: bool = False
    sub_queries: List[str] = field(default_factory=list)

    # Keywords for retrieval
    keywords: List[str] = field(default_factory=list)
    key_phrases: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "original_query": self.original_query,
            "intent": self.intent.value,
            "intent_confidence": self.intent_confidence,
            "entities": [
                {"text": e.text, "type": e.type.value, "confidence": e.confidence}
                for e in self.entities
            ],
            "domain": self.domain.value,
            "domain_confidence": self.domain_confidence,
            "suggested_collections": self.suggested_collections,
            "is_complex": self.is_complex,
            "keywords": self.keywords,
        }


# =============================================================================
# INTENT CLASSIFIER
# =============================================================================

class IntentClassifier:
    """
    Classify query intent using pattern matching and heuristics.

    In production, this could be enhanced with a trained classifier.
    """

    # Pattern-based intent detection
    INTENT_PATTERNS = {
        QueryIntent.FACTUAL: [
            r"^what (is|are|was|were)\b",
            r"^who (is|are|was|were)\b",
            r"^when (did|was|were|is)\b",
            r"^where (is|are|was|were)\b",
            r"^which\b",
            r"\bdefine\b",
            r"\bdefinition of\b",
            r"^name\b",
            r"^list\b",
        ],
        QueryIntent.ANALYTICAL: [
            r"^why\b",
            r"^how does\b",
            r"^how did\b",
            r"\bexplain\b",
            r"\banalyze\b",
            r"\breason(s)?\b",
            r"\bcause(s)?\b",
            r"\bimpact\b",
            r"\beffect(s)?\b",
        ],
        QueryIntent.COMPARATIVE: [
            r"\bcompare\b",
            r"\bcomparison\b",
            r"\bvs\.?\b",
            r"\bversus\b",
            r"\bdifference(s)? between\b",
            r"\bsimilarit(y|ies)\b",
            r"\bbetter than\b",
            r"\bworse than\b",
            r"\bor\b.*\?$",  # X or Y?
        ],
        QueryIntent.PROCEDURAL: [
            r"^how (to|do|can|should)\b",
            r"\bsteps to\b",
            r"\bprocess (for|of)\b",
            r"\btutorial\b",
            r"\bguide\b",
            r"\binstructions?\b",
            r"\bprocedure\b",
        ],
        QueryIntent.NAVIGATIONAL: [
            r"^find\b",
            r"^locate\b",
            r"^search for\b",
            r"^show me\b",
            r"^get\b",
            r"\bwhere can i find\b",
        ],
        QueryIntent.CLARIFICATION: [
            r"^can you (explain|clarify|elaborate)\b",
            r"^what do you mean\b",
            r"^i don'?t understand\b",
            r"\bmore detail\b",
            r"\bmore about\b",
            r"^tell me more\b",
        ],
        QueryIntent.OPINION: [
            r"^what do you think\b",
            r"^should i\b",
            r"^would you recommend\b",
            r"\byour opinion\b",
            r"\bbest\b.*\?$",
        ],
    }

    def __init__(self):
        # Compile patterns
        self._compiled_patterns: Dict[QueryIntent, List[re.Pattern]] = {}
        for intent, patterns in self.INTENT_PATTERNS.items():
            self._compiled_patterns[intent] = [
                re.compile(p, re.IGNORECASE) for p in patterns
            ]

    def classify(self, query: str) -> Tuple[QueryIntent, float]:
        """
        Classify query intent.

        Returns:
            (intent, confidence)
        """
        query_lower = query.lower().strip()

        # Score each intent
        scores: Dict[QueryIntent, float] = defaultdict(float)

        for intent, patterns in self._compiled_patterns.items():
            for pattern in patterns:
                if pattern.search(query_lower):
                    scores[intent] += 1.0

        # Normalize scores
        total = sum(scores.values())
        if total > 0:
            for intent in scores:
                scores[intent] /= total

        # Get best intent
        if scores:
            best_intent = max(scores.items(), key=lambda x: x[1])
            return best_intent[0], min(best_intent[1] + 0.3, 1.0)

        # Default to factual for questions
        if query.strip().endswith("?"):
            return QueryIntent.FACTUAL, 0.6

        # Default to navigational for statements
        return QueryIntent.NAVIGATIONAL, 0.5


# =============================================================================
# ENTITY EXTRACTOR
# =============================================================================

class EntityExtractor:
    """
    Extract named entities from queries.

    Uses pattern matching for finance-specific entities.
    Could be enhanced with spaCy NER or LLM extraction.
    """

    # Company name patterns
    COMPANY_PATTERNS = [
        r"\b(Apple|Microsoft|Google|Alphabet|Amazon|Meta|Facebook|NVIDIA|Tesla)\b",
        r"\b(IBM|Intel|AMD|Oracle|Salesforce|Adobe|Netflix|Uber|Airbnb)\b",
        r"\b(JPMorgan|Goldman Sachs|Morgan Stanley|Bank of America|Wells Fargo)\b",
        r"\b(Pfizer|Johnson & Johnson|Merck|AbbVie|Bristol-Myers)\b",
        r"\b(ExxonMobil|Chevron|Shell|BP|ConocoPhillips)\b",
    ]

    # Ticker patterns
    TICKER_PATTERN = r"\b([A-Z]{1,5})\b"  # 1-5 uppercase letters

    # Known tickers
    KNOWN_TICKERS = {
        "AAPL", "MSFT", "GOOGL", "GOOG", "AMZN", "META", "NVDA", "TSLA",
        "IBM", "INTC", "AMD", "ORCL", "CRM", "ADBE", "NFLX",
        "JPM", "GS", "MS", "BAC", "WFC", "C", "BRK", "V", "MA",
    }

    # Date patterns
    DATE_PATTERNS = [
        r"\b(Q[1-4])\s*(20\d{2})\b",  # Q1 2024
        r"\b(FY|fiscal year)\s*(20\d{2})\b",  # FY 2024
        r"\b(20\d{2})\b",  # Year
        r"\b(January|February|March|April|May|June|July|August|September|October|November|December)\s*(20\d{2})?\b",
        r"\b(last|this|next)\s*(year|quarter|month)\b",
    ]

    # Money patterns
    MONEY_PATTERNS = [
        r"\$[\d,]+(\.\d+)?\s*(million|billion|trillion|M|B|T)?\b",
        r"\b[\d,]+(\.\d+)?\s*(dollars|USD)\b",
    ]

    # Percent patterns
    PERCENT_PATTERN = r"\b[\d.]+\s*(%|percent|percentage)\b"

    # Filing type patterns
    FILING_PATTERNS = [
        r"\b(10-K|10-Q|8-K|S-1|DEF 14A|13F|Form\s*\d+[A-Z]*)\b",
    ]

    # Metric patterns (finance)
    METRIC_PATTERNS = [
        r"\b(revenue|income|profit|earnings|EBITDA|margin)\b",
        r"\b(EPS|P/E|ROE|ROA|debt-to-equity)\b",
        r"\b(market cap|valuation|growth)\b",
        r"\b(assets|liabilities|equity|cash flow)\b",
    ]

    def __init__(self):
        # Compile all patterns
        self._company_patterns = [re.compile(p, re.IGNORECASE) for p in self.COMPANY_PATTERNS]
        self._date_patterns = [re.compile(p, re.IGNORECASE) for p in self.DATE_PATTERNS]
        self._money_patterns = [re.compile(p, re.IGNORECASE) for p in self.MONEY_PATTERNS]
        self._percent_pattern = re.compile(self.PERCENT_PATTERN, re.IGNORECASE)
        self._filing_patterns = [re.compile(p, re.IGNORECASE) for p in self.FILING_PATTERNS]
        self._metric_patterns = [re.compile(p, re.IGNORECASE) for p in self.METRIC_PATTERNS]
        self._ticker_pattern = re.compile(self.TICKER_PATTERN)

    def extract(self, query: str) -> List[Entity]:
        """Extract all entities from a query."""
        entities = []

        # Extract companies
        for pattern in self._company_patterns:
            for match in pattern.finditer(query):
                entities.append(Entity(
                    text=match.group(),
                    type=EntityType.COMPANY,
                    confidence=0.95
                ))

        # Extract tickers
        for match in self._ticker_pattern.finditer(query):
            ticker = match.group(1)
            if ticker in self.KNOWN_TICKERS:
                entities.append(Entity(
                    text=ticker,
                    type=EntityType.TICKER,
                    confidence=0.9
                ))

        # Extract dates
        for pattern in self._date_patterns:
            for match in pattern.finditer(query):
                entities.append(Entity(
                    text=match.group(),
                    type=EntityType.DATE,
                    confidence=0.85
                ))

        # Extract money
        for pattern in self._money_patterns:
            for match in pattern.finditer(query):
                entities.append(Entity(
                    text=match.group(),
                    type=EntityType.MONEY,
                    confidence=0.9
                ))

        # Extract percentages
        for match in self._percent_pattern.finditer(query):
            entities.append(Entity(
                text=match.group(),
                type=EntityType.PERCENT,
                confidence=0.9
            ))

        # Extract filing types
        for pattern in self._filing_patterns:
            for match in pattern.finditer(query):
                entities.append(Entity(
                    text=match.group(),
                    type=EntityType.FILING,
                    confidence=0.95
                ))

        # Extract metrics
        for pattern in self._metric_patterns:
            for match in pattern.finditer(query):
                entities.append(Entity(
                    text=match.group(),
                    type=EntityType.METRIC,
                    confidence=0.85
                ))

        # Deduplicate by text
        seen = set()
        unique_entities = []
        for e in entities:
            key = (e.text.lower(), e.type)
            if key not in seen:
                seen.add(key)
                unique_entities.append(e)

        return unique_entities


# =============================================================================
# DOMAIN ROUTER
# =============================================================================

class DomainRouter:
    """
    Route queries to appropriate knowledge domains/collections.

    Uses keyword matching and entity signals.
    """

    # Domain keywords
    DOMAIN_KEYWORDS = {
        Domain.FINANCE: {
            "keywords": [
                "revenue", "profit", "earnings", "stock", "market", "quarterly",
                "fiscal", "dividend", "SEC", "10-K", "10-Q", "filing", "investor",
                "shareholder", "capital", "assets", "liabilities", "balance sheet",
                "income statement", "cash flow", "GAAP", "EPS", "P/E", "IPO",
                "merger", "acquisition", "hedge", "portfolio", "trading",
            ],
            "collections": ["sec_edgar"],
            "weight": 1.5,  # Boost for high-value domain
        },
        Domain.SCIENCE: {
            "keywords": [
                "research", "study", "experiment", "hypothesis", "theory",
                "analysis", "methodology", "results", "conclusion", "abstract",
                "peer-reviewed", "citation", "journal", "arxiv", "paper", "theorem",
                "proof", "equation", "model", "simulation", "quantum", "neural",
                "algorithm", "optimization", "machine learning", "AI", "physics",
            ],
            "collections": ["arxiv"],
            "weight": 1.3,
        },
        Domain.TECHNICAL: {
            "keywords": [
                "code", "programming", "error", "bug", "fix", "implementation",
                "function", "class", "method", "API", "library", "framework",
                "database", "server", "deploy", "docker", "kubernetes",
                "git", "python", "javascript", "java", "rust", "golang",
                "debug", "exception", "syntax", "compiler", "runtime",
            ],
            "collections": ["stackoverflow"],
            "weight": 1.2,
        },
        Domain.GENERAL: {
            "keywords": [],  # Fallback
            "collections": ["wikipedia"],
            "weight": 1.0,
        },
    }

    # Entity type to domain mapping
    ENTITY_DOMAIN_MAP = {
        EntityType.COMPANY: Domain.FINANCE,
        EntityType.TICKER: Domain.FINANCE,
        EntityType.FILING: Domain.FINANCE,
        EntityType.MONEY: Domain.FINANCE,
        EntityType.METRIC: Domain.FINANCE,
    }

    def __init__(self):
        # Build keyword lookup
        self._keyword_to_domain: Dict[str, Domain] = {}
        for domain, config in self.DOMAIN_KEYWORDS.items():
            for keyword in config["keywords"]:
                self._keyword_to_domain[keyword.lower()] = domain

    def route(
        self,
        query: str,
        entities: List[Entity] = None
    ) -> Tuple[Domain, float, List[str]]:
        """
        Route query to appropriate domain.

        Returns:
            (domain, confidence, suggested_collections)
        """
        query_lower = query.lower()
        entities = entities or []

        # Score each domain
        scores: Dict[Domain, float] = defaultdict(float)

        # Keyword matching
        words = set(re.findall(r'\b\w+\b', query_lower))
        for word in words:
            if word in self._keyword_to_domain:
                domain = self._keyword_to_domain[word]
                weight = self.DOMAIN_KEYWORDS[domain]["weight"]
                scores[domain] += weight

        # Entity-based routing
        for entity in entities:
            if entity.type in self.ENTITY_DOMAIN_MAP:
                domain = self.ENTITY_DOMAIN_MAP[entity.type]
                scores[domain] += 2.0 * entity.confidence

        # Normalize and find best
        total = sum(scores.values())
        if total > 0:
            for domain in scores:
                scores[domain] /= total

            best_domain = max(scores.items(), key=lambda x: x[1])
            collections = self.DOMAIN_KEYWORDS[best_domain[0]]["collections"]
            return best_domain[0], min(best_domain[1] + 0.2, 1.0), collections

        # Default to general
        return Domain.GENERAL, 0.5, self.DOMAIN_KEYWORDS[Domain.GENERAL]["collections"]


# =============================================================================
# QUERY DECOMPOSER
# =============================================================================

class QueryDecomposer:
    """
    Decompose complex queries into simpler sub-queries.

    Useful for multi-hop retrieval and complex reasoning.
    """

    # Complexity indicators
    COMPLEXITY_PATTERNS = [
        r"\band\b.*\band\b",  # Multiple "and"s
        r"\bcompare\b",
        r"\bdifference\b",
        r"\brelationship\b",
        r"\bbetween\b.*\band\b",
        r"\b(both|each|all)\b",
    ]

    def __init__(self):
        self._complexity_patterns = [
            re.compile(p, re.IGNORECASE) for p in self.COMPLEXITY_PATTERNS
        ]

    def is_complex(self, query: str) -> bool:
        """Check if query is complex enough to decompose."""
        # Check for complexity patterns
        for pattern in self._complexity_patterns:
            if pattern.search(query):
                return True

        # Check word count (long queries may need decomposition)
        word_count = len(query.split())
        return word_count > 15

    def decompose(self, query: str, entities: List[Entity] = None) -> List[str]:
        """
        Decompose query into sub-queries.

        Returns:
            List of sub-queries (includes original if not decomposable)
        """
        entities = entities or []

        # Always include original
        sub_queries = [query]

        # Check for comparison pattern
        comparison_match = re.search(
            r"(.+?)\s+(vs\.?|versus|compared to|and)\s+(.+)",
            query,
            re.IGNORECASE
        )
        if comparison_match:
            part1 = comparison_match.group(1).strip()
            part2 = comparison_match.group(3).strip()

            # Generate focused queries for each part
            if len(part1) > 5 and len(part2) > 5:
                sub_queries.append(part1)
                sub_queries.append(part2)

        # Check for multiple entities
        companies = [e for e in entities if e.type == EntityType.COMPANY]
        if len(companies) >= 2:
            # Create entity-focused queries
            base_topic = self._extract_topic(query)
            for company in companies[:3]:  # Limit to 3
                sub_queries.append(f"{company.text} {base_topic}")

        # Check for time-based queries
        dates = [e for e in entities if e.type == EntityType.DATE]
        if len(dates) >= 2:
            # Create time-focused queries
            for date in dates[:2]:
                sub_queries.append(f"{query.split(date.text)[0].strip()} {date.text}")

        # Deduplicate
        seen = set()
        unique = []
        for q in sub_queries:
            q_lower = q.lower().strip()
            if q_lower and q_lower not in seen:
                seen.add(q_lower)
                unique.append(q)

        return unique

    def _extract_topic(self, query: str) -> str:
        """Extract main topic from query."""
        topic_words = [
            "revenue", "profit", "growth", "performance", "sales",
            "stock", "market", "earnings", "income", "price",
        ]

        query_lower = query.lower()
        for word in topic_words:
            if word in query_lower:
                return word

        return ""


# =============================================================================
# UNIFIED QUERY ANALYZER
# =============================================================================

class QueryAnalyzer:
    """
    Unified query analysis pipeline.

    Orchestrates intent classification, entity extraction,
    domain routing, and query decomposition.
    """

    def __init__(self):
        self.intent_classifier = IntentClassifier()
        self.entity_extractor = EntityExtractor()
        self.domain_router = DomainRouter()
        self.query_decomposer = QueryDecomposer()

    def analyze(self, query: str) -> QueryAnalysis:
        """
        Perform comprehensive query analysis.

        Args:
            query: User query string

        Returns:
            QueryAnalysis with all extracted information
        """
        # Clean query
        cleaned = self._clean_query(query)

        # Classify intent
        intent, intent_conf = self.intent_classifier.classify(cleaned)

        # Extract entities
        entities = self.entity_extractor.extract(cleaned)

        # Route to domain
        domain, domain_conf, collections = self.domain_router.route(cleaned, entities)

        # Check complexity and decompose
        is_complex = self.query_decomposer.is_complex(cleaned)
        sub_queries = []
        if is_complex:
            sub_queries = self.query_decomposer.decompose(cleaned, entities)

        # Extract keywords
        keywords = self._extract_keywords(cleaned)
        key_phrases = self._extract_key_phrases(cleaned)

        # Determine entity focus
        entity_focus = None
        if entities:
            # Prioritize companies, then other entities
            companies = [e for e in entities if e.type == EntityType.COMPANY]
            if companies:
                entity_focus = companies[0].text
            elif entities:
                entity_focus = entities[0].text

        return QueryAnalysis(
            original_query=query,
            cleaned_query=cleaned,
            intent=intent,
            intent_confidence=intent_conf,
            entities=entities,
            entity_focus=entity_focus,
            domain=domain,
            domain_confidence=domain_conf,
            suggested_collections=collections,
            is_question=query.strip().endswith("?"),
            is_complex=is_complex,
            sub_queries=sub_queries,
            keywords=keywords,
            key_phrases=key_phrases,
        )

    def _clean_query(self, query: str) -> str:
        """Clean and normalize query."""
        # Remove extra whitespace
        cleaned = " ".join(query.split())

        # Normalize punctuation
        cleaned = re.sub(r'\s+([?.!,])', r'\1', cleaned)

        return cleaned.strip()

    def _extract_keywords(self, query: str) -> List[str]:
        """Extract important keywords from query."""
        # Remove stop words
        stop_words = {
            'a', 'an', 'the', 'and', 'or', 'but', 'is', 'are', 'was', 'were',
            'be', 'been', 'being', 'in', 'on', 'at', 'to', 'for', 'with',
            'by', 'about', 'of', 'from', 'what', 'how', 'why', 'when', 'where',
            'who', 'which', 'this', 'that', 'these', 'those', 'can', 'could',
            'would', 'should', 'do', 'does', 'did', 'have', 'has', 'had',
            'will', 'would', 'shall', 'may', 'might', 'must', 'need',
        }

        words = re.findall(r'\b\w+\b', query.lower())
        keywords = [w for w in words if w not in stop_words and len(w) > 2]

        return keywords[:10]  # Limit to 10

    def _extract_key_phrases(self, query: str) -> List[str]:
        """Extract important phrases from query."""
        # Look for quoted phrases
        quoted = re.findall(r'"([^"]+)"', query)
        if quoted:
            return quoted[:5]

        # Look for noun phrase patterns (simple heuristic)
        phrases = re.findall(r'\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)+\b', query)
        return phrases[:5]


# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

_query_analyzer: Optional[QueryAnalyzer] = None


def get_query_analyzer() -> QueryAnalyzer:
    """Get or create singleton query analyzer."""
    global _query_analyzer
    if _query_analyzer is None:
        _query_analyzer = QueryAnalyzer()
    return _query_analyzer


def analyze_query(query: str) -> QueryAnalysis:
    """Convenience function for query analysis."""
    return get_query_analyzer().analyze(query)
