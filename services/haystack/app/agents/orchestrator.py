"""
Agent Orchestrator for routing queries to appropriate agent modes.

The orchestrator analyzes queries and selects the best agent mode:
- Basic RAG: Simple factual queries
- ReAct: Tool-requiring queries
- Deep Research: Complex research queries
- Plan-Execute: Multi-step tasks
"""

import logging
import re
from enum import Enum
from typing import Optional, AsyncGenerator, Dict, Any, List

from .base import AgentContext, AgentConfig
from .events import AgentEvent
from .react import ReActAgent
from .deep_research import DeepResearchAgent
from .plan_execute import PlanExecuteAgent
from app.tools import get_tool_registry

logger = logging.getLogger(__name__)


class AgentMode(str, Enum):
    """Available agent modes."""
    BASIC_RAG = "basic"           # Existing simple RAG
    REACT = "react"               # ReAct agent
    DEEP_RESEARCH = "deep_research"  # Multi-source investigation
    PLAN_EXECUTE = "plan_execute"    # Plan then execute


class ModeClassifier:
    """
    Classifies queries to determine the appropriate agent mode.

    Uses pattern matching and query analysis to select the best agent.
    """

    # Patterns indicating research queries
    RESEARCH_PATTERNS = [
        r'\bcompare\b.*\b(and|with|to|vs)\b',
        r'\banalyze\b.*\btrends?\b',
        r'\bresearch\b',
        r'\bin-depth\b',
        r'\bcomprehensive\b',
        r'\bmultiple\s+sources\b',
        r'\bthorough(ly)?\b',
        r'\bdetailed\s+analysis\b',
        r'\binvestigate\b',
        r'\bexplore\b.*\brelationship\b',
    ]

    # Patterns indicating multi-step tasks
    MULTI_STEP_PATTERNS = [
        r'\bthen\b.*\bthen\b',
        r'\bfirst\b.*\bnext\b',
        r'\bstep\s+by\s+step\b',
        r'\bsequence\b',
        r'\bworkflow\b',
        r'\bprocess\b.*\b(steps?|stages?)\b',
        r'\bprocedure\b',
        r'(\d+\.|\bstep\s+\d+)',
    ]

    # Patterns indicating tool-requiring queries
    TOOL_PATTERNS = [
        r'\bcalculate\b',
        r'\bcompute\b',
        r'\bsum\s+of\b',
        r'\bdifference\s+between\b',
        r'\bpercentage\b',
        r'\bsearch\s+for\b',
        r'\bfind\b.*\b(that|where|when)\b',
        r'\blook\s+up\b',
        r'\bwhat\s+is\s+the\b.*\b(price|value|amount|number)\b',
    ]

    # Simple query patterns (use basic RAG)
    SIMPLE_PATTERNS = [
        r'^what\s+is\s+\w+\??$',
        r'^who\s+is\s+\w+\??$',
        r'^define\s+\w+\??$',
        r'^when\s+was\b',
        r'^where\s+is\b',
    ]

    def classify(
        self,
        query: str,
        query_analysis: Optional[Dict[str, Any]] = None
    ) -> AgentMode:
        """
        Classify a query to determine the best agent mode.

        Args:
            query: The user's query
            query_analysis: Optional analysis from query_understanding module

        Returns:
            The recommended AgentMode
        """
        query_lower = query.lower()

        # Check for simple patterns first (basic RAG)
        for pattern in self.SIMPLE_PATTERNS:
            if re.search(pattern, query_lower, re.IGNORECASE):
                return AgentMode.BASIC_RAG

        # Use query analysis if available
        if query_analysis:
            intent = query_analysis.get("intent", "")
            is_complex = query_analysis.get("is_complex", False)
            entity_count = len(query_analysis.get("entities", []))

            # Comparative queries with multiple entities -> deep research
            if intent == "comparative" and entity_count >= 2:
                return AgentMode.DEEP_RESEARCH

            # Simple factual query -> basic RAG
            if intent == "factual" and not is_complex:
                return AgentMode.BASIC_RAG

        # Check for research patterns
        for pattern in self.RESEARCH_PATTERNS:
            if re.search(pattern, query_lower, re.IGNORECASE):
                return AgentMode.DEEP_RESEARCH

        # Check for multi-step patterns
        for pattern in self.MULTI_STEP_PATTERNS:
            if re.search(pattern, query_lower, re.IGNORECASE):
                return AgentMode.PLAN_EXECUTE

        # Check for tool-requiring patterns
        for pattern in self.TOOL_PATTERNS:
            if re.search(pattern, query_lower, re.IGNORECASE):
                return AgentMode.REACT

        # Check query length and complexity
        word_count = len(query.split())
        sentence_count = len(re.split(r'[.!?]', query))

        # Long, complex queries -> consider deep research
        if word_count > 30 or sentence_count > 2:
            return AgentMode.DEEP_RESEARCH

        # Default to ReAct for most queries
        return AgentMode.REACT


class AgentOrchestrator:
    """
    Orchestrator that routes queries to appropriate agents.

    Responsibilities:
    - Analyze queries and select agent mode
    - Create and run the appropriate agent
    - Handle fallback between modes
    """

    def __init__(self, config: Optional[AgentConfig] = None):
        self.config = config or AgentConfig()
        self.classifier = ModeClassifier()
        self.tools = get_tool_registry()

        # Initialize agents lazily
        self._agents: Dict[AgentMode, Any] = {}

    def get_agent(self, mode: AgentMode):
        """Get or create an agent for the given mode."""
        if mode not in self._agents:
            if mode == AgentMode.REACT:
                self._agents[mode] = ReActAgent(self.tools, self.config)
            elif mode == AgentMode.DEEP_RESEARCH:
                self._agents[mode] = DeepResearchAgent(self.tools, self.config)
            elif mode == AgentMode.PLAN_EXECUTE:
                self._agents[mode] = PlanExecuteAgent(self.tools, self.config)
            else:
                # Basic RAG doesn't need an agent
                self._agents[mode] = None

        return self._agents[mode]

    def select_mode(
        self,
        query: str,
        query_analysis: Optional[Dict[str, Any]] = None,
        user_override: Optional[str] = None
    ) -> AgentMode:
        """
        Select the appropriate agent mode for a query.

        Args:
            query: The user's query
            query_analysis: Optional analysis from query_understanding
            user_override: Optional explicit mode selection

        Returns:
            The selected AgentMode
        """
        # User can force a specific mode
        if user_override and user_override != "auto":
            try:
                return AgentMode(user_override)
            except ValueError:
                logger.warning(f"Invalid mode override: {user_override}, using auto")

        # Auto-detect mode
        mode = self.classifier.classify(query, query_analysis)
        logger.info(f"Selected mode '{mode.value}' for query: {query[:50]}...")

        return mode

    async def run(
        self,
        query: str,
        context: AgentContext,
        mode: Optional[AgentMode] = None
    ) -> AsyncGenerator[AgentEvent, None]:
        """
        Run the appropriate agent for the query.

        Args:
            query: The user's query
            context: Execution context
            mode: Optional explicit mode (auto-detected if not provided)

        Yields:
            AgentEvent objects from the agent
        """
        # Select mode if not provided
        if mode is None or mode == AgentMode.BASIC_RAG:
            # Get query analysis if available
            query_analysis = None
            if hasattr(context, 'query_analysis') and context.query_analysis:
                query_analysis = context.query_analysis

            mode = self.select_mode(query, query_analysis)

        # Emit mode selection event
        yield AgentEvent.mode_selected(mode.value, self._get_mode_reason(mode))

        # Handle basic RAG separately
        if mode == AgentMode.BASIC_RAG:
            async for event in self._run_basic_rag(query, context):
                yield event
            return

        # Get the agent
        agent = self.get_agent(mode)
        if agent is None:
            yield AgentEvent.error(f"No agent available for mode: {mode.value}")
            return

        # Run the agent
        try:
            async for event in agent.run(query, context):
                yield event
        except Exception as e:
            logger.exception(f"Agent execution failed, mode: {mode.value}")
            yield AgentEvent.error(str(e), recoverable=True)

            # Fallback to basic RAG
            if mode != AgentMode.REACT:
                logger.info("Falling back to ReAct agent")
                yield AgentEvent.mode_selected("react", "Fallback after error")
                react_agent = self.get_agent(AgentMode.REACT)
                async for event in react_agent.run(query, context):
                    yield event

    async def _run_basic_rag(
        self,
        query: str,
        context: AgentContext
    ) -> AsyncGenerator[AgentEvent, None]:
        """
        Run basic RAG without agentic behavior.

        This is a passthrough to the existing RAG pipeline.
        """
        from app.advanced_retrieval import AdvancedRetriever, RetrievalConfig
        from app.generation import llm_registry
        import asyncio
        import time

        start_time = time.time()

        try:
            # Retrieve context
            yield AgentEvent.phase("retrieval", "Searching knowledge base")

            retriever = AdvancedRetriever()
            config = RetrievalConfig(use_rag_fusion=True, use_reranking=True, final_k=5)

            results = await asyncio.to_thread(
                retriever.retrieve,
                query,
                org_id=context.org_id,
                config=config
            )

            # Format results
            documents = []
            for r in results:
                doc = {
                    "content": getattr(r, 'content', getattr(r, 'text', '')),
                    "title": getattr(r, 'title', 'Untitled'),
                    "score": getattr(r, 'score', 0.0)
                }
                documents.append(doc)

            yield AgentEvent.context(documents)

            # Generate response
            yield AgentEvent.phase("generation", "Generating response")

            provider = llm_registry.get_provider(context.provider)
            context_str = "\n\n".join(
                f"Document: {d['title']}\n{d['content']}"
                for d in documents[:5]
            )

            prompt = f"""Answer the following question based on the provided context.

Context:
{context_str}

Question: {query}

Answer:"""

            response = await asyncio.to_thread(
                provider.generate,
                prompt,
                context.conversation_history or [],
                {"temperature": context.temperature, "max_tokens": context.max_tokens}
            )

            yield AgentEvent.final_answer(
                answer=response,
                sources=documents if context.include_trace else None
            )

            duration = time.time() - start_time
            yield AgentEvent.complete(
                total_steps=1,
                mode="basic",
                duration=duration
            )

        except Exception as e:
            logger.exception("Basic RAG failed")
            yield AgentEvent.error(str(e))

    def _get_mode_reason(self, mode: AgentMode) -> str:
        """Get a human-readable reason for mode selection."""
        reasons = {
            AgentMode.BASIC_RAG: "Simple factual query",
            AgentMode.REACT: "Query may require tool use",
            AgentMode.DEEP_RESEARCH: "Complex query requiring multi-source research",
            AgentMode.PLAN_EXECUTE: "Multi-step task requiring planning"
        }
        return reasons.get(mode, "Auto-detected")


# Global orchestrator instance
_orchestrator: Optional[AgentOrchestrator] = None


def get_agent_orchestrator(config: Optional[AgentConfig] = None) -> AgentOrchestrator:
    """Get or create the global agent orchestrator."""
    global _orchestrator
    if _orchestrator is None:
        _orchestrator = AgentOrchestrator(config)
    return _orchestrator
