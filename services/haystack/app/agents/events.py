"""
Streaming event types for Agentic RAG.

This module defines the event types that agents emit during their execution,
enabling real-time streaming of agent reasoning and actions.
"""

import json
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any, Union
from enum import Enum


class AgentEventType(str, Enum):
    """Types of events that agents can emit."""

    # Orchestration events
    MODE_SELECTED = "mode_selected"  # Agent mode was chosen
    PHASE = "phase"  # Major phase transition

    # ReAct agent events
    THINKING = "thinking"  # Agent is reasoning (iteration start)
    THOUGHT = "thought"  # Agent's reasoning output
    ACTION = "action"  # Tool invocation
    ACTION_INPUT = "action_input"  # Tool parameters (detailed)
    OBSERVATION = "observation"  # Tool result

    # Plan-and-Execute events
    PLAN = "plan"  # Execution plan created
    PLAN_STEP = "plan_step"  # Individual plan step detail
    EXECUTING_STEP = "executing_step"  # Step execution started
    STEP_COMPLETE = "step_complete"  # Step finished successfully
    STEP_FAILED = "step_failed"  # Step failed
    REPLAN = "replan"  # Plan was revised

    # Deep Research events
    DECOMPOSING = "decomposing"  # Breaking down query
    SUB_QUESTION = "sub_question"  # Individual research question
    RESEARCHING = "researching"  # Researching a sub-question
    SOURCE_FOUND = "source_found"  # Found a relevant source
    VERIFYING = "verifying"  # Cross-referencing findings
    SYNTHESIZING = "synthesizing"  # Combining findings

    # Common streaming events
    TOKEN = "token"  # Individual token for streaming text
    CONTEXT = "context"  # Retrieved context documents
    SOURCES = "sources"  # Source citations

    # Interaction events
    CLARIFY = "clarify"  # Needs user clarification
    USER_INPUT = "user_input"  # User provided input

    # Completion events
    FINAL_ANSWER = "final_answer"  # Complete answer generated
    QUALITY_CHECK = "quality_check"  # Quality verification result
    COMPLETE = "complete"  # Agent finished

    # Error events
    ERROR = "error"  # Error occurred
    WARNING = "warning"  # Non-fatal warning
    FALLBACK = "fallback"  # Fallback to alternative approach

    # Metrics events
    METRIC = "metric"  # Performance metric


@dataclass
class AgentEvent:
    """
    An event emitted by an agent during execution.

    Events are streamed to the client in real-time, enabling
    visibility into the agent's reasoning process.
    """
    type: AgentEventType
    data: Dict[str, Any] = field(default_factory=dict)
    timestamp: float = field(default_factory=time.time)
    event_id: Optional[str] = None

    def __post_init__(self):
        if self.event_id is None:
            self.event_id = f"{self.type.value}_{int(self.timestamp * 1000)}"

    def to_dict(self) -> Dict[str, Any]:
        """Convert event to dictionary."""
        return {
            "type": self.type.value,
            "data": self.data,
            "timestamp": self.timestamp,
            "event_id": self.event_id
        }

    def to_json(self) -> str:
        """Convert event to JSON string."""
        return json.dumps(self.to_dict())

    def to_sse(self) -> str:
        """Convert to Server-Sent Events format."""
        return f"data: {self.to_json()}\n\n"

    @classmethod
    def mode_selected(cls, mode: str, reason: Optional[str] = None) -> "AgentEvent":
        """Create a mode_selected event."""
        data = {"mode": mode}
        if reason:
            data["reason"] = reason
        return cls(type=AgentEventType.MODE_SELECTED, data=data)

    @classmethod
    def phase(cls, phase: str, description: Optional[str] = None) -> "AgentEvent":
        """Create a phase transition event."""
        data = {"phase": phase}
        if description:
            data["description"] = description
        return cls(type=AgentEventType.PHASE, data=data)

    @classmethod
    def thinking(cls, iteration: int, message: Optional[str] = None) -> "AgentEvent":
        """Create a thinking event."""
        data = {"iteration": iteration}
        if message:
            data["message"] = message
        return cls(type=AgentEventType.THINKING, data=data)

    @classmethod
    def thought(cls, thought: str, iteration: Optional[int] = None) -> "AgentEvent":
        """Create a thought event."""
        data = {"thought": thought}
        if iteration is not None:
            data["iteration"] = iteration
        return cls(type=AgentEventType.THOUGHT, data=data)

    @classmethod
    def action(cls, tool: str, input_data: Dict[str, Any]) -> "AgentEvent":
        """Create an action event."""
        return cls(type=AgentEventType.ACTION, data={
            "tool": tool,
            "input": input_data
        })

    @classmethod
    def observation(cls, result: Any, tool: Optional[str] = None, success: bool = True) -> "AgentEvent":
        """Create an observation event."""
        data = {"result": result, "success": success}
        if tool:
            data["tool"] = tool
        return cls(type=AgentEventType.OBSERVATION, data=data)

    @classmethod
    def plan(cls, steps: List[Dict[str, Any]], total_steps: Optional[int] = None) -> "AgentEvent":
        """Create a plan event."""
        return cls(type=AgentEventType.PLAN, data={
            "steps": steps,
            "total_steps": total_steps or len(steps)
        })

    @classmethod
    def executing_step(cls, step_number: int, description: str) -> "AgentEvent":
        """Create an executing_step event."""
        return cls(type=AgentEventType.EXECUTING_STEP, data={
            "step": step_number,
            "description": description
        })

    @classmethod
    def step_complete(cls, step_number: int, result: Any) -> "AgentEvent":
        """Create a step_complete event."""
        return cls(type=AgentEventType.STEP_COMPLETE, data={
            "step": step_number,
            "result": result
        })

    @classmethod
    def step_failed(cls, step_number: int, error: str) -> "AgentEvent":
        """Create a step_failed event."""
        return cls(type=AgentEventType.STEP_FAILED, data={
            "step": step_number,
            "error": error
        })

    @classmethod
    def sub_question(cls, question: str, index: int, total: int) -> "AgentEvent":
        """Create a sub_question event for deep research."""
        return cls(type=AgentEventType.SUB_QUESTION, data={
            "question": question,
            "index": index,
            "total": total
        })

    @classmethod
    def researching(cls, question: str, sources_found: int = 0) -> "AgentEvent":
        """Create a researching event."""
        return cls(type=AgentEventType.RESEARCHING, data={
            "question": question,
            "sources_found": sources_found
        })

    @classmethod
    def source_found(cls, source: Dict[str, Any], relevance: float) -> "AgentEvent":
        """Create a source_found event."""
        return cls(type=AgentEventType.SOURCE_FOUND, data={
            "source": source,
            "relevance": relevance
        })

    @classmethod
    def token(cls, content: str, index: Optional[int] = None) -> "AgentEvent":
        """Create a token event for streaming text."""
        data = {"content": content}
        if index is not None:
            data["index"] = index
        return cls(type=AgentEventType.TOKEN, data=data)

    @classmethod
    def context(cls, documents: List[Dict[str, Any]]) -> "AgentEvent":
        """Create a context event with retrieved documents."""
        return cls(type=AgentEventType.CONTEXT, data={
            "documents": documents,
            "count": len(documents)
        })

    @classmethod
    def clarify(cls, question: str, options: Optional[List[str]] = None) -> "AgentEvent":
        """Create a clarify event requesting user input."""
        data = {"question": question}
        if options:
            data["options"] = options
        return cls(type=AgentEventType.CLARIFY, data=data)

    @classmethod
    def final_answer(
        cls,
        answer: str,
        sources: Optional[List[Dict[str, Any]]] = None,
        trace: Optional[List[Dict[str, Any]]] = None,
        confidence: Optional[float] = None
    ) -> "AgentEvent":
        """Create a final_answer event."""
        data = {"answer": answer}
        if sources:
            data["sources"] = sources
        if trace:
            data["trace"] = trace
        if confidence is not None:
            data["confidence"] = confidence
        return cls(type=AgentEventType.FINAL_ANSWER, data=data)

    @classmethod
    def quality_check(
        cls,
        score: float,
        hallucination_risk: float,
        warnings: Optional[List[str]] = None
    ) -> "AgentEvent":
        """Create a quality_check event."""
        data = {
            "score": score,
            "hallucination_risk": hallucination_risk
        }
        if warnings:
            data["warnings"] = warnings
        return cls(type=AgentEventType.QUALITY_CHECK, data=data)

    @classmethod
    def complete(
        cls,
        total_steps: int,
        mode: str,
        duration: float,
        tokens_used: Optional[int] = None
    ) -> "AgentEvent":
        """Create a complete event."""
        data = {
            "total_steps": total_steps,
            "mode": mode,
            "duration": duration
        }
        if tokens_used is not None:
            data["tokens_used"] = tokens_used
        return cls(type=AgentEventType.COMPLETE, data=data)

    @classmethod
    def error(cls, message: str, code: Optional[str] = None, recoverable: bool = False) -> "AgentEvent":
        """Create an error event."""
        data = {"message": message, "recoverable": recoverable}
        if code:
            data["code"] = code
        return cls(type=AgentEventType.ERROR, data=data)

    @classmethod
    def warning(cls, message: str) -> "AgentEvent":
        """Create a warning event."""
        return cls(type=AgentEventType.WARNING, data={"message": message})

    @classmethod
    def metric(cls, name: str, value: Union[int, float], unit: Optional[str] = None) -> "AgentEvent":
        """Create a metric event."""
        data = {"name": name, "value": value}
        if unit:
            data["unit"] = unit
        return cls(type=AgentEventType.METRIC, data=data)


class EventStream:
    """
    Helper class for managing a stream of agent events.
    """

    def __init__(self):
        self.events: List[AgentEvent] = []
        self.start_time: float = time.time()

    def add(self, event: AgentEvent) -> None:
        """Add an event to the stream."""
        self.events.append(event)

    def get_duration(self) -> float:
        """Get the duration since stream started."""
        return time.time() - self.start_time

    def get_thoughts(self) -> List[str]:
        """Extract all thoughts from the stream."""
        return [
            e.data.get("thought", "")
            for e in self.events
            if e.type == AgentEventType.THOUGHT
        ]

    def get_actions(self) -> List[Dict[str, Any]]:
        """Extract all actions from the stream."""
        return [
            {"tool": e.data.get("tool"), "input": e.data.get("input")}
            for e in self.events
            if e.type == AgentEventType.ACTION
        ]

    def get_final_answer(self) -> Optional[str]:
        """Get the final answer if present."""
        for e in reversed(self.events):
            if e.type == AgentEventType.FINAL_ANSWER:
                return e.data.get("answer")
        return None

    def to_trace(self) -> List[Dict[str, Any]]:
        """Convert the stream to a trace for debugging."""
        return [e.to_dict() for e in self.events]

    def has_error(self) -> bool:
        """Check if the stream contains any errors."""
        return any(e.type == AgentEventType.ERROR for e in self.events)

    def get_errors(self) -> List[str]:
        """Get all error messages."""
        return [
            e.data.get("message", "Unknown error")
            for e in self.events
            if e.type == AgentEventType.ERROR
        ]
