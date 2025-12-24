"""
Deep Research Agent implementation.

This agent performs comprehensive multi-source investigation by:
1. Decomposing complex queries into sub-questions
2. Searching multiple sources for each sub-question
3. Cross-referencing and verifying findings
4. Synthesizing a comprehensive answer with citations
"""

import logging
import time
import asyncio
from typing import AsyncGenerator, Optional, List, Dict, Any

from .base import BaseAgent, AgentState, AgentStep, AgentContext, AgentConfig
from .events import AgentEvent, AgentEventType
from app.tools import ToolRegistry, get_tool_registry

logger = logging.getLogger(__name__)


DECOMPOSITION_PROMPT = """Break down the following complex question into 2-5 specific sub-questions that need to be answered.

Question: {query}

Output the sub-questions as a JSON array of strings. Each sub-question should:
1. Be specific and answerable
2. Cover a distinct aspect of the main question
3. Together, the sub-questions should fully address the main question

Example format:
["What is X?", "How does X relate to Y?", "What are the implications of Z?"]

Sub-questions:"""


SYNTHESIS_PROMPT = """Synthesize a comprehensive answer to the following question based on the research findings.

Original Question: {query}

Research Findings:
{findings}

Instructions:
1. Integrate information from all sources
2. Highlight key insights and patterns
3. Note any conflicting information
4. Cite sources where appropriate
5. Acknowledge any gaps in the available information

Provide a well-structured, comprehensive answer:"""


class DeepResearchAgent(BaseAgent):
    """
    Deep Research Agent: Multi-source investigation with synthesis.

    This agent performs thorough research by:
    1. Decomposing the query into sub-questions
    2. Researching each sub-question independently
    3. Cross-referencing findings
    4. Synthesizing a comprehensive answer
    """

    def __init__(
        self,
        tools: Optional[ToolRegistry] = None,
        config: Optional[AgentConfig] = None,
        max_sources_per_question: int = 5
    ):
        super().__init__(tools, config)
        self.max_sources_per_question = max_sources_per_question

    @property
    def name(self) -> str:
        return "DeepResearchAgent"

    async def run(
        self,
        query: str,
        context: AgentContext
    ) -> AsyncGenerator[AgentEvent, None]:
        """
        Execute the deep research process.

        Args:
            query: The user's question
            context: Execution context

        Yields:
            AgentEvent objects as the agent researches
        """
        self.reset()
        start_time = time.time()
        all_findings: List[Dict[str, Any]] = []

        logger.info(f"DeepResearchAgent starting for query: {query[:100]}...")

        try:
            # Phase 1: Query Decomposition
            yield AgentEvent.phase("decomposition", "Breaking down the question into sub-questions")

            sub_questions = await self._decompose_query(query, context)

            if not sub_questions:
                # Fallback to treating the original query as the only question
                sub_questions = [query]
                yield AgentEvent.warning("Could not decompose query, using original question")

            logger.info(f"Decomposed into {len(sub_questions)} sub-questions")

            # Emit sub-questions
            for i, sq in enumerate(sub_questions):
                yield AgentEvent.sub_question(sq, i + 1, len(sub_questions))

            # Phase 2: Research each sub-question
            yield AgentEvent.phase("research", f"Researching {len(sub_questions)} sub-questions")

            for i, sub_question in enumerate(sub_questions):
                step = self.create_step(AgentState.ACTING)
                step.thought = f"Researching: {sub_question}"

                yield AgentEvent.researching(sub_question, 0)

                # Search for this sub-question
                findings = await self._research_question(sub_question, context)

                # Emit sources found
                for finding in findings:
                    yield AgentEvent.source_found(finding, finding.get("score", 0.5))

                step.observation = findings
                step.state = AgentState.OBSERVING
                self.update_step(step)

                all_findings.append({
                    "question": sub_question,
                    "sources": findings
                })

            # Phase 3: Cross-reference and verify
            yield AgentEvent.phase("verification", "Cross-referencing findings")

            verified_findings = await self._cross_reference(all_findings, context)

            # Phase 4: Synthesis
            yield AgentEvent.phase("synthesis", "Synthesizing comprehensive answer")

            final_answer = await self._synthesize_answer(query, verified_findings, context)

            # Extract all sources
            all_sources = []
            for finding in all_findings:
                for source in finding.get("sources", []):
                    if source not in all_sources:
                        all_sources.append(source)

            # Run quality check
            quality_result = await self.run_quality_check(final_answer, all_sources, query)
            if quality_result:
                yield AgentEvent.quality_check(
                    score=quality_result.get("confidence_score", 0.0),
                    hallucination_risk=quality_result.get("hallucination_risk", 0.0),
                    warnings=quality_result.get("warnings", [])
                )

            # Emit final answer
            yield AgentEvent.final_answer(
                answer=final_answer,
                sources=all_sources if context.include_trace else None,
                trace=self.get_trace() if context.include_trace else None,
                confidence=quality_result.get("confidence_score") if quality_result else None
            )

            # Emit completion
            duration = time.time() - start_time
            yield AgentEvent.complete(
                total_steps=len(self.steps),
                mode="deep_research",
                duration=duration
            )

        except Exception as e:
            logger.exception("DeepResearchAgent execution failed")
            yield AgentEvent.error(str(e), recoverable=False)

    async def _decompose_query(
        self,
        query: str,
        context: AgentContext
    ) -> List[str]:
        """Decompose a complex query into sub-questions."""
        import json

        prompt = DECOMPOSITION_PROMPT.format(query=query)

        try:
            response = await self.generate_llm_response(prompt, context)

            # Parse JSON array from response
            # Try to find JSON array in the response
            import re
            json_match = re.search(r'\[.+?\]', response, re.DOTALL)
            if json_match:
                return json.loads(json_match.group())

            # Fallback: split by newlines and clean up
            lines = [line.strip() for line in response.split('\n') if line.strip()]
            questions = []
            for line in lines:
                # Remove numbering, bullets, quotes
                cleaned = re.sub(r'^[\d\.\)\-\*]+\s*', '', line)
                cleaned = cleaned.strip('"\'')
                if cleaned and len(cleaned) > 10:
                    questions.append(cleaned)

            return questions[:5]  # Limit to 5 sub-questions

        except Exception as e:
            logger.error(f"Query decomposition failed: {e}")
            return []

    async def _research_question(
        self,
        question: str,
        context: AgentContext
    ) -> List[Dict[str, Any]]:
        """Research a single sub-question."""
        try:
            result = await self.tools.execute(
                "search_knowledge_base",
                {
                    "query": question,
                    "top_k": self.max_sources_per_question
                },
                context.to_tool_context()
            )

            if result.success and result.data:
                return result.data.get("documents", [])

            return []

        except Exception as e:
            logger.error(f"Research failed for question: {question}: {e}")
            return []

    async def _cross_reference(
        self,
        findings: List[Dict[str, Any]],
        context: AgentContext
    ) -> List[Dict[str, Any]]:
        """Cross-reference findings to identify consistent information."""
        # For now, simple deduplication and scoring
        # Could be enhanced with more sophisticated verification

        seen_content = set()
        verified = []

        for finding in findings:
            question = finding.get("question", "")
            sources = finding.get("sources", [])

            verified_sources = []
            for source in sources:
                content = source.get("content", "")
                content_hash = hash(content[:500])  # First 500 chars

                if content_hash not in seen_content:
                    seen_content.add(content_hash)
                    # Add verification metadata
                    source["verified"] = True
                    source["related_question"] = question
                    verified_sources.append(source)

            verified.append({
                "question": question,
                "sources": verified_sources
            })

        return verified

    async def _synthesize_answer(
        self,
        query: str,
        findings: List[Dict[str, Any]],
        context: AgentContext
    ) -> str:
        """Synthesize findings into a comprehensive answer."""
        # Format findings for synthesis
        findings_text = ""
        for i, finding in enumerate(findings):
            question = finding.get("question", f"Research area {i + 1}")
            sources = finding.get("sources", [])

            findings_text += f"\n## {question}\n"
            for j, source in enumerate(sources):
                title = source.get("title", "Untitled")
                content = source.get("content", "")[:1000]  # Limit content length
                findings_text += f"\n### Source {j + 1}: {title}\n{content}\n"

        prompt = SYNTHESIS_PROMPT.format(
            query=query,
            findings=findings_text
        )

        try:
            return await self.generate_llm_response(prompt, context)
        except Exception as e:
            logger.error(f"Synthesis failed: {e}")
            return f"I researched your question across multiple sources but encountered an error during synthesis: {str(e)}"
