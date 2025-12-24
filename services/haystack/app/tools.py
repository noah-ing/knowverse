"""
Tool definitions and registry for Agentic RAG.

This module provides a framework for defining and executing tools
that agents can use during their reasoning process.
"""

import logging
import asyncio
import json
import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any, Callable, Union
from enum import Enum
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)


class ToolParameterType(str, Enum):
    """Supported parameter types for tools."""
    STRING = "string"
    INTEGER = "integer"
    NUMBER = "number"
    BOOLEAN = "boolean"
    ARRAY = "array"
    OBJECT = "object"


@dataclass
class ToolParameter:
    """Definition of a tool parameter."""
    type: ToolParameterType
    description: str
    required: bool = True
    default: Any = None
    enum: Optional[List[Any]] = None


@dataclass
class Tool:
    """Definition of an agent tool."""
    name: str
    description: str
    parameters: Dict[str, ToolParameter]
    function: Callable
    requires_streaming: bool = False
    category: str = "general"

    def to_openai_schema(self) -> Dict[str, Any]:
        """Convert to OpenAI function calling format."""
        properties = {}
        required = []

        for name, param in self.parameters.items():
            prop = {
                "type": param.type.value,
                "description": param.description
            }
            if param.enum:
                prop["enum"] = param.enum
            properties[name] = prop

            if param.required:
                required.append(name)

        return {
            "type": "function",
            "function": {
                "name": self.name,
                "description": self.description,
                "parameters": {
                    "type": "object",
                    "properties": properties,
                    "required": required
                }
            }
        }

    def to_anthropic_schema(self) -> Dict[str, Any]:
        """Convert to Anthropic tool use format."""
        properties = {}
        required = []

        for name, param in self.parameters.items():
            prop = {
                "type": param.type.value,
                "description": param.description
            }
            if param.enum:
                prop["enum"] = param.enum
            properties[name] = prop

            if param.required:
                required.append(name)

        return {
            "name": self.name,
            "description": self.description,
            "input_schema": {
                "type": "object",
                "properties": properties,
                "required": required
            }
        }


class ClarificationNeeded(Exception):
    """Exception raised when a tool needs user clarification."""
    def __init__(self, question: str, options: Optional[List[str]] = None):
        self.question = question
        self.options = options
        super().__init__(question)


class ToolError(Exception):
    """Exception raised when a tool execution fails."""
    def __init__(self, tool_name: str, message: str, recoverable: bool = True):
        self.tool_name = tool_name
        self.message = message
        self.recoverable = recoverable
        super().__init__(f"Tool '{tool_name}' failed: {message}")


@dataclass
class ToolResult:
    """Result of a tool execution."""
    success: bool
    data: Any
    error: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "success": self.success,
            "data": self.data,
            "error": self.error,
            "metadata": self.metadata
        }


class ToolRegistry:
    """Registry of available agent tools."""

    def __init__(self):
        self.tools: Dict[str, Tool] = {}
        self._register_builtin_tools()

    def register(self, tool: Tool) -> None:
        """Register a tool."""
        self.tools[tool.name] = tool
        logger.info(f"Registered tool: {tool.name}")

    def get(self, name: str) -> Optional[Tool]:
        """Get a tool by name."""
        return self.tools.get(name)

    def list_tools(self) -> List[str]:
        """List all registered tool names."""
        return list(self.tools.keys())

    def get_schemas_openai(self) -> List[Dict[str, Any]]:
        """Get all tool schemas in OpenAI format."""
        return [tool.to_openai_schema() for tool in self.tools.values()]

    def get_schemas_anthropic(self) -> List[Dict[str, Any]]:
        """Get all tool schemas in Anthropic format."""
        return [tool.to_anthropic_schema() for tool in self.tools.values()]

    def get_tools_description(self) -> str:
        """Get a formatted description of all tools for text-based agents."""
        lines = []
        for tool in self.tools.values():
            params = []
            for name, param in tool.parameters.items():
                req = "(required)" if param.required else "(optional)"
                params.append(f"    - {name}: {param.type.value} {req} - {param.description}")

            lines.append(f"- {tool.name}: {tool.description}")
            if params:
                lines.extend(params)
            lines.append("")

        return "\n".join(lines)

    async def execute(self, tool_name: str, parameters: Dict[str, Any], context: Optional[Dict[str, Any]] = None) -> ToolResult:
        """Execute a tool with given parameters."""
        tool = self.get(tool_name)
        if not tool:
            return ToolResult(
                success=False,
                data=None,
                error=f"Unknown tool: {tool_name}"
            )

        try:
            # Validate required parameters
            for name, param in tool.parameters.items():
                if param.required and name not in parameters:
                    if param.default is not None:
                        parameters[name] = param.default
                    else:
                        return ToolResult(
                            success=False,
                            data=None,
                            error=f"Missing required parameter: {name}"
                        )

            # Inject context if the function accepts it
            import inspect
            sig = inspect.signature(tool.function)
            if 'context' in sig.parameters:
                parameters['context'] = context or {}

            # Execute the tool
            start_time = datetime.now()

            if asyncio.iscoroutinefunction(tool.function):
                result = await tool.function(**parameters)
            else:
                result = await asyncio.to_thread(tool.function, **parameters)

            execution_time = (datetime.now() - start_time).total_seconds()

            return ToolResult(
                success=True,
                data=result,
                metadata={
                    "tool": tool_name,
                    "execution_time": execution_time
                }
            )

        except ClarificationNeeded:
            raise  # Re-raise for agent to handle
        except ToolError as e:
            return ToolResult(
                success=False,
                data=None,
                error=e.message,
                metadata={"recoverable": e.recoverable}
            )
        except Exception as e:
            logger.exception(f"Tool execution failed: {tool_name}")
            return ToolResult(
                success=False,
                data=None,
                error=str(e)
            )

    def _register_builtin_tools(self) -> None:
        """Register all built-in tools."""
        self.register(self._create_search_knowledge_base_tool())
        self.register(self._create_calculate_tool())
        self.register(self._create_summarize_tool())
        self.register(self._create_compare_tool())
        self.register(self._create_clarify_tool())

    def _create_search_knowledge_base_tool(self) -> Tool:
        """Create the search_knowledge_base tool."""

        async def search_knowledge_base(
            query: str,
            top_k: int = 5,
            collection: Optional[str] = None,
            filters: Optional[Dict[str, Any]] = None,
            context: Optional[Dict[str, Any]] = None
        ) -> Dict[str, Any]:
            """Search the knowledge base using RAG-Fusion and reranking."""
            from app.advanced_retrieval import AdvancedRetriever, RetrievalConfig

            org_id = context.get("org_id") if context else None

            retriever = AdvancedRetriever()
            config = RetrievalConfig(
                use_rag_fusion=True,
                use_reranking=True,
                final_k=top_k
            )

            results = await asyncio.to_thread(
                retriever.retrieve,
                query,
                collection=collection,
                org_id=org_id,
                config=config
            )

            documents = []
            for r in results:
                doc = {
                    "id": getattr(r, 'id', None),
                    "content": getattr(r, 'content', getattr(r, 'text', '')),
                    "title": getattr(r, 'title', 'Untitled'),
                    "score": getattr(r, 'score', 0.0),
                    "metadata": getattr(r, 'metadata', {})
                }
                documents.append(doc)

            return {
                "documents": documents,
                "count": len(documents),
                "query": query,
                "strategy": "rag_fusion_rerank"
            }

        return Tool(
            name="search_knowledge_base",
            description="Search the organization's knowledge base for relevant documents. Use for finding factual information, supporting evidence, or context.",
            parameters={
                "query": ToolParameter(
                    type=ToolParameterType.STRING,
                    description="The search query",
                    required=True
                ),
                "top_k": ToolParameter(
                    type=ToolParameterType.INTEGER,
                    description="Number of results to return",
                    required=False,
                    default=5
                ),
                "collection": ToolParameter(
                    type=ToolParameterType.STRING,
                    description="Specific collection to search (optional)",
                    required=False
                ),
                "filters": ToolParameter(
                    type=ToolParameterType.OBJECT,
                    description="Metadata filters (optional)",
                    required=False
                )
            },
            function=search_knowledge_base,
            category="retrieval"
        )

    def _create_calculate_tool(self) -> Tool:
        """Create the calculate tool for math and date operations."""

        def calculate(
            expression: str,
            variables: Optional[Dict[str, Any]] = None
        ) -> Dict[str, Any]:
            """Perform mathematical or date calculations safely."""
            import math
            from dateutil import parser as date_parser
            from dateutil.relativedelta import relativedelta

            variables = variables or {}

            # Check if it's a date operation
            date_keywords = ['days', 'months', 'years', 'weeks', 'date', 'today', 'now']
            is_date_op = any(kw in expression.lower() for kw in date_keywords)

            if is_date_op:
                try:
                    # Handle date calculations
                    today = datetime.now()

                    # Replace keywords
                    expr = expression.lower()
                    if 'today' in expr or 'now' in expr:
                        base_date = today
                    else:
                        # Try to extract a date from the expression
                        date_match = re.search(r'\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}/\d{4}', expression)
                        if date_match:
                            base_date = date_parser.parse(date_match.group())
                        else:
                            base_date = today

                    # Parse the operation
                    delta = relativedelta()

                    days_match = re.search(r'([+-]?\d+)\s*days?', expr)
                    if days_match:
                        delta += relativedelta(days=int(days_match.group(1)))

                    weeks_match = re.search(r'([+-]?\d+)\s*weeks?', expr)
                    if weeks_match:
                        delta += relativedelta(weeks=int(weeks_match.group(1)))

                    months_match = re.search(r'([+-]?\d+)\s*months?', expr)
                    if months_match:
                        delta += relativedelta(months=int(months_match.group(1)))

                    years_match = re.search(r'([+-]?\d+)\s*years?', expr)
                    if years_match:
                        delta += relativedelta(years=int(years_match.group(1)))

                    result_date = base_date + delta

                    return {
                        "result": result_date.isoformat(),
                        "formatted": result_date.strftime("%B %d, %Y"),
                        "expression": expression,
                        "type": "date"
                    }

                except Exception as e:
                    raise ToolError("calculate", f"Date calculation failed: {str(e)}")

            else:
                # Math calculation
                try:
                    # Create safe namespace with math functions
                    safe_dict = {
                        'abs': abs, 'round': round, 'min': min, 'max': max,
                        'sum': sum, 'len': len, 'pow': pow,
                        'sqrt': math.sqrt, 'log': math.log, 'log10': math.log10,
                        'sin': math.sin, 'cos': math.cos, 'tan': math.tan,
                        'pi': math.pi, 'e': math.e,
                        **variables
                    }

                    # Sanitize expression (remove dangerous characters)
                    sanitized = re.sub(r'[^0-9+\-*/%().a-zA-Z_ ]', '', expression)

                    result = eval(sanitized, {"__builtins__": {}}, safe_dict)

                    return {
                        "result": result,
                        "expression": expression,
                        "type": "math"
                    }

                except Exception as e:
                    raise ToolError("calculate", f"Math calculation failed: {str(e)}")

        return Tool(
            name="calculate",
            description="Perform mathematical calculations or date arithmetic. Supports basic math, percentages, and date operations like 'today + 30 days'.",
            parameters={
                "expression": ToolParameter(
                    type=ToolParameterType.STRING,
                    description="The mathematical expression or date operation to evaluate",
                    required=True
                ),
                "variables": ToolParameter(
                    type=ToolParameterType.OBJECT,
                    description="Variables to use in the expression (e.g., {'x': 10})",
                    required=False
                )
            },
            function=calculate,
            category="computation"
        )

    def _create_summarize_tool(self) -> Tool:
        """Create the summarize tool."""

        async def summarize(
            content: str,
            max_length: int = 200,
            focus: Optional[str] = None,
            context: Optional[Dict[str, Any]] = None
        ) -> Dict[str, Any]:
            """Summarize content using the LLM."""
            from app.generation import llm_registry

            prompt = f"Summarize the following in {max_length} words or less"
            if focus:
                prompt += f", focusing on {focus}"
            prompt += f":\n\n{content}"

            provider = llm_registry.get_provider()
            summary = await asyncio.to_thread(
                provider.generate,
                prompt,
                [],
                {"max_tokens": max_length * 2}
            )

            return {
                "summary": summary,
                "original_length": len(content),
                "summary_length": len(summary),
                "focus": focus
            }

        return Tool(
            name="summarize",
            description="Summarize long content into a concise form. Use when content is too long to include directly.",
            parameters={
                "content": ToolParameter(
                    type=ToolParameterType.STRING,
                    description="The content to summarize",
                    required=True
                ),
                "max_length": ToolParameter(
                    type=ToolParameterType.INTEGER,
                    description="Maximum length in words",
                    required=False,
                    default=200
                ),
                "focus": ToolParameter(
                    type=ToolParameterType.STRING,
                    description="Specific aspect to focus on in the summary",
                    required=False
                )
            },
            function=summarize,
            category="generation"
        )

    def _create_compare_tool(self) -> Tool:
        """Create the compare tool for multi-source comparison."""

        async def compare(
            sources: List[str],
            criteria: Optional[List[str]] = None,
            context: Optional[Dict[str, Any]] = None
        ) -> Dict[str, Any]:
            """Compare multiple sources using the LLM."""
            from app.generation import llm_registry

            if len(sources) < 2:
                raise ToolError("compare", "Need at least 2 sources to compare")

            criteria_str = ", ".join(criteria) if criteria else "key differences and similarities"

            prompt = f"Compare the following sources based on {criteria_str}. Provide a structured comparison:\n\n"
            for i, source in enumerate(sources):
                prompt += f"Source {i + 1}:\n{source[:2000]}\n\n"  # Limit source length

            provider = llm_registry.get_provider()
            comparison = await asyncio.to_thread(
                provider.generate,
                prompt,
                [],
                {"max_tokens": 800}
            )

            return {
                "comparison": comparison,
                "num_sources": len(sources),
                "criteria": criteria or ["general comparison"]
            }

        return Tool(
            name="compare",
            description="Compare information from multiple sources. Use for comparative analysis.",
            parameters={
                "sources": ToolParameter(
                    type=ToolParameterType.ARRAY,
                    description="List of source texts to compare",
                    required=True
                ),
                "criteria": ToolParameter(
                    type=ToolParameterType.ARRAY,
                    description="Specific criteria for comparison",
                    required=False
                )
            },
            function=compare,
            category="analysis"
        )

    def _create_clarify_tool(self) -> Tool:
        """Create the clarify tool for user interaction."""

        def clarify(
            question: str,
            options: Optional[List[str]] = None
        ) -> None:
            """Request clarification from the user. This pauses execution."""
            raise ClarificationNeeded(question=question, options=options)

        return Tool(
            name="clarify",
            description="Ask the user for clarification when the query is ambiguous or you need more information. This pauses execution until the user responds.",
            parameters={
                "question": ToolParameter(
                    type=ToolParameterType.STRING,
                    description="The clarification question to ask",
                    required=True
                ),
                "options": ToolParameter(
                    type=ToolParameterType.ARRAY,
                    description="Suggested options for the user to choose from",
                    required=False
                )
            },
            function=clarify,
            requires_streaming=True,
            category="interaction"
        )


# Global tool registry instance
tool_registry = ToolRegistry()


def get_tool_registry() -> ToolRegistry:
    """Get the global tool registry instance."""
    return tool_registry
