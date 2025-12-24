"""
Base agent framework for Agentic RAG.

This module provides the abstract base class and core data structures
for all agent implementations.
"""

import logging
import time
import json
import re
import asyncio
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any, Tuple, AsyncGenerator, Union
from enum import Enum

from .events import AgentEvent, AgentEventType, EventStream
from app.tools import ToolRegistry, ToolResult, ClarificationNeeded, get_tool_registry

logger = logging.getLogger(__name__)


class AgentState(str, Enum):
    """States an agent can be in during execution."""
    INITIALIZING = "initializing"
    REASONING = "reasoning"
    ACTING = "acting"
    OBSERVING = "observing"
    PLANNING = "planning"
    EXECUTING = "executing"
    SYNTHESIZING = "synthesizing"
    WAITING_USER = "waiting_user"
    COMPLETE = "complete"
    ERROR = "error"


@dataclass
class AgentStep:
    """Record of a single step in the agent's execution."""
    step_id: int
    state: AgentState
    thought: Optional[str] = None
    action: Optional[str] = None
    action_input: Optional[Dict[str, Any]] = None
    observation: Optional[Any] = None
    error: Optional[str] = None
    timestamp: float = field(default_factory=time.time)
    duration: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        """Convert step to dictionary."""
        return {
            "step_id": self.step_id,
            "state": self.state.value,
            "thought": self.thought,
            "action": self.action,
            "action_input": self.action_input,
            "observation": self._serialize_observation(),
            "error": self.error,
            "timestamp": self.timestamp,
            "duration": self.duration
        }

    def _serialize_observation(self) -> Any:
        """Serialize observation for JSON output."""
        if self.observation is None:
            return None
        if isinstance(self.observation, (dict, list, str, int, float, bool)):
            return self.observation
        if hasattr(self.observation, 'to_dict'):
            return self.observation.to_dict()
        return str(self.observation)


@dataclass
class AgentContext:
    """Context passed to agents during execution."""
    org_id: int
    query: str
    session_id: Optional[str] = None
    user_id: Optional[int] = None
    query_analysis: Optional[Any] = None
    memory_context: Optional[Dict[str, Any]] = None
    conversation_history: Optional[List[Dict[str, str]]] = None
    system_prompt: Optional[str] = None
    max_iterations: int = 10
    temperature: float = 0.7
    max_tokens: int = 1000
    provider: Optional[str] = None
    include_trace: bool = True

    def to_tool_context(self) -> Dict[str, Any]:
        """Create context dict for tool execution."""
        return {
            "org_id": self.org_id,
            "session_id": self.session_id,
            "user_id": self.user_id,
            "query": self.query
        }


@dataclass
class AgentConfig:
    """Configuration for agent behavior."""
    max_iterations: int = 10
    max_tool_retries: int = 2
    thinking_budget: int = 5000  # tokens for reasoning
    allow_clarification: bool = True
    allow_replan: bool = True
    quality_threshold: float = 0.7
    timeout_seconds: float = 120.0
    use_native_tools: bool = True  # Use function calling if available


class BaseAgent(ABC):
    """
    Abstract base class for all agents.

    Agents implement multi-step reasoning with tool use.
    Subclasses must implement the `run` method.
    """

    def __init__(
        self,
        tools: Optional[ToolRegistry] = None,
        config: Optional[AgentConfig] = None
    ):
        self.tools = tools or get_tool_registry()
        self.config = config or AgentConfig()
        self.steps: List[AgentStep] = []
        self.event_stream = EventStream()
        self._step_counter = 0
        self._llm_provider = None

    @property
    def name(self) -> str:
        """Return the agent's name."""
        return self.__class__.__name__

    @abstractmethod
    async def run(
        self,
        query: str,
        context: AgentContext
    ) -> AsyncGenerator[AgentEvent, None]:
        """
        Run the agent and stream events.

        Args:
            query: The user's question or request
            context: Execution context with org_id, session, etc.

        Yields:
            AgentEvent objects as the agent reasons and acts
        """
        pass

    def get_llm_provider(self, provider_name: Optional[str] = None):
        """Get an LLM provider instance."""
        if self._llm_provider is None:
            from app.generation import llm_registry
            self._llm_provider = llm_registry.get_provider(provider_name)
        return self._llm_provider

    async def generate_llm_response(
        self,
        prompt: str,
        context: AgentContext,
        with_tools: bool = False
    ) -> str:
        """Generate a response from the LLM."""
        provider = self.get_llm_provider(context.provider)

        options = {
            "temperature": context.temperature,
            "max_tokens": context.max_tokens
        }

        if with_tools and self.config.use_native_tools:
            # Check if provider supports function calling
            if hasattr(provider, 'generate_with_tools'):
                tool_schemas = self.tools.get_schemas_openai()
                return await asyncio.to_thread(
                    provider.generate_with_tools,
                    prompt,
                    tool_schemas,
                    options
                )

        # Regular generation
        return await asyncio.to_thread(
            provider.generate,
            prompt,
            context.conversation_history or [],
            options
        )

    async def stream_llm_response(
        self,
        prompt: str,
        context: AgentContext
    ) -> AsyncGenerator[str, None]:
        """Stream a response from the LLM token by token."""
        provider = self.get_llm_provider(context.provider)

        options = {
            "temperature": context.temperature,
            "max_tokens": context.max_tokens
        }

        async for token in provider.generate_stream(
            prompt,
            context.conversation_history or [],
            options
        ):
            yield token

    def create_step(self, state: AgentState) -> AgentStep:
        """Create a new step record."""
        self._step_counter += 1
        step = AgentStep(
            step_id=self._step_counter,
            state=state
        )
        self.steps.append(step)
        return step

    def update_step(self, step: AgentStep, **kwargs) -> None:
        """Update a step with new data."""
        for key, value in kwargs.items():
            if hasattr(step, key):
                setattr(step, key, value)
        step.duration = time.time() - step.timestamp

    async def execute_tool(
        self,
        tool_name: str,
        parameters: Dict[str, Any],
        context: AgentContext
    ) -> ToolResult:
        """Execute a tool with retry logic."""
        last_error = None

        for attempt in range(self.config.max_tool_retries + 1):
            try:
                result = await self.tools.execute(
                    tool_name,
                    parameters,
                    context.to_tool_context()
                )

                if result.success:
                    return result

                last_error = result.error

                # Don't retry non-recoverable errors
                if result.metadata.get("recoverable") is False:
                    break

            except ClarificationNeeded:
                raise  # Let the agent handle this
            except Exception as e:
                last_error = str(e)
                logger.warning(f"Tool {tool_name} attempt {attempt + 1} failed: {e}")

        return ToolResult(
            success=False,
            data=None,
            error=last_error or "Tool execution failed after retries"
        )

    def parse_llm_response(
        self,
        response: str
    ) -> Tuple[Optional[str], Optional[str], Optional[Dict[str, Any]]]:
        """
        Parse LLM response for thought, action, and action_input.

        Supports both structured (function calling) and text-based formats.

        Returns:
            Tuple of (thought, action, action_input)
            action will be "FINAL_ANSWER" if the agent is done
        """
        # Try to parse as JSON first (structured response)
        try:
            data = json.loads(response)
            if isinstance(data, dict):
                if "tool_calls" in data:
                    # OpenAI function calling format
                    tool_call = data["tool_calls"][0]
                    return (
                        data.get("content", ""),
                        tool_call["function"]["name"],
                        json.loads(tool_call["function"]["arguments"])
                    )
                elif "action" in data:
                    return (
                        data.get("thought", ""),
                        data.get("action"),
                        data.get("action_input", {})
                    )
        except (json.JSONDecodeError, KeyError, IndexError):
            pass

        # Parse text-based format
        thought = ""
        action = None
        action_input = {}

        # Extract THOUGHT
        thought_match = re.search(
            r'THOUGHT:\s*(.+?)(?=ACTION:|FINAL_ANSWER:|$)',
            response,
            re.DOTALL | re.IGNORECASE
        )
        if thought_match:
            thought = thought_match.group(1).strip()

        # Check for FINAL_ANSWER
        final_match = re.search(
            r'FINAL_ANSWER:\s*(.+?)$',
            response,
            re.DOTALL | re.IGNORECASE
        )
        if final_match:
            return thought, "FINAL_ANSWER", {"answer": final_match.group(1).strip()}

        # Extract ACTION
        action_match = re.search(
            r'ACTION:\s*(\w+)',
            response,
            re.IGNORECASE
        )
        if action_match:
            action = action_match.group(1)

        # Extract ACTION_INPUT
        input_match = re.search(
            r'ACTION_INPUT:\s*(\{.+?\}|\[.+?\])',
            response,
            re.DOTALL | re.IGNORECASE
        )
        if input_match:
            try:
                action_input = json.loads(input_match.group(1))
            except json.JSONDecodeError:
                # Try to extract key-value pairs
                input_text = input_match.group(1)
                pairs = re.findall(r'"?(\w+)"?\s*:\s*"?([^",}]+)"?', input_text)
                action_input = dict(pairs)

        return thought, action, action_input

    def build_scratchpad(self) -> str:
        """Build a scratchpad from previous steps for context."""
        lines = []

        for step in self.steps:
            if step.thought:
                lines.append(f"THOUGHT: {step.thought}")
            if step.action and step.action != "FINAL_ANSWER":
                lines.append(f"ACTION: {step.action}")
                if step.action_input:
                    lines.append(f"ACTION_INPUT: {json.dumps(step.action_input)}")
            if step.observation is not None:
                obs_str = json.dumps(step.observation) if isinstance(step.observation, (dict, list)) else str(step.observation)
                # Truncate long observations
                if len(obs_str) > 2000:
                    obs_str = obs_str[:2000] + "... [truncated]"
                lines.append(f"OBSERVATION: {obs_str}")
            lines.append("")

        return "\n".join(lines)

    async def run_quality_check(
        self,
        answer: str,
        sources: List[Dict[str, Any]],
        query: str
    ) -> Optional[Dict[str, Any]]:
        """Run quality check on the final answer."""
        try:
            from app.quality import check_response_quality
            result = await asyncio.to_thread(
                check_response_quality,
                answer,
                sources,
                query
            )
            return result.to_dict() if hasattr(result, 'to_dict') else result
        except Exception as e:
            logger.warning(f"Quality check failed: {e}")
            return None

    def get_sources_from_steps(self) -> List[Dict[str, Any]]:
        """Extract source documents from observation steps."""
        sources = []

        for step in self.steps:
            if step.observation and isinstance(step.observation, dict):
                docs = step.observation.get("documents", [])
                for doc in docs:
                    if isinstance(doc, dict) and doc not in sources:
                        sources.append(doc)

        return sources

    def get_trace(self) -> List[Dict[str, Any]]:
        """Get the execution trace for debugging."""
        return [step.to_dict() for step in self.steps]

    def reset(self) -> None:
        """Reset the agent state for a new execution."""
        self.steps = []
        self.event_stream = EventStream()
        self._step_counter = 0
