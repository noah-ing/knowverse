"""
ReAct Agent implementation.

ReAct (Reason + Act) is a paradigm that interleaves reasoning and acting.
The agent thinks about what to do, takes an action (uses a tool),
observes the result, and repeats until it can provide a final answer.

Reference: https://arxiv.org/abs/2210.03629
"""

import logging
import time
from typing import AsyncGenerator, Optional, List, Dict, Any

from .base import BaseAgent, AgentState, AgentStep, AgentContext, AgentConfig
from .events import AgentEvent, AgentEventType
from app.tools import ToolRegistry, ClarificationNeeded, get_tool_registry

logger = logging.getLogger(__name__)


REACT_SYSTEM_PROMPT = """You are an intelligent assistant with access to tools to help answer questions.

For each step, you must respond in this exact format:

THOUGHT: <your reasoning about what to do next, what information you need, or how to interpret results>
ACTION: <the tool name to use>
ACTION_INPUT: <JSON object with the tool parameters>

Or, if you have gathered enough information to answer:

THOUGHT: <your final reasoning>
FINAL_ANSWER: <your complete answer to the user's question>

Available tools:
{tools_description}

Important guidelines:
1. Always start with a THOUGHT explaining your reasoning
2. Use tools to gather information before answering
3. If a tool returns an error, try a different approach
4. When you have enough information, provide a FINAL_ANSWER
5. Be thorough but efficient - don't use more tools than necessary
6. Cite your sources in the final answer when applicable

Current conversation:
{conversation_history}

Previous steps:
{scratchpad}

User's question: {query}

Now, provide your next step:"""


class ReActAgent(BaseAgent):
    """
    ReAct Agent: Reason-Act-Observe loop.

    This agent alternates between:
    1. THOUGHT: Reasoning about what to do
    2. ACTION: Choosing and invoking a tool
    3. OBSERVATION: Processing the tool result

    The loop continues until the agent provides a FINAL_ANSWER.
    """

    def __init__(
        self,
        tools: Optional[ToolRegistry] = None,
        config: Optional[AgentConfig] = None,
        system_prompt: Optional[str] = None
    ):
        super().__init__(tools, config)
        self.system_prompt_template = system_prompt or REACT_SYSTEM_PROMPT

    @property
    def name(self) -> str:
        return "ReActAgent"

    async def run(
        self,
        query: str,
        context: AgentContext
    ) -> AsyncGenerator[AgentEvent, None]:
        """
        Execute the ReAct loop.

        Args:
            query: The user's question
            context: Execution context

        Yields:
            AgentEvent objects as the agent reasons and acts
        """
        self.reset()
        start_time = time.time()
        iteration = 0
        final_answer = None

        logger.info(f"ReActAgent starting for query: {query[:100]}...")

        try:
            while iteration < context.max_iterations:
                # Emit thinking event
                yield AgentEvent.thinking(iteration, f"Reasoning step {iteration + 1}")

                # Create step record
                step = self.create_step(AgentState.REASONING)

                # Build prompt with scratchpad
                prompt = self._build_prompt(query, context)

                # Get LLM response
                try:
                    response = await self.generate_llm_response(
                        prompt,
                        context,
                        with_tools=True
                    )
                except Exception as e:
                    logger.error(f"LLM generation failed: {e}")
                    yield AgentEvent.error(f"Failed to generate response: {str(e)}")
                    break

                # Parse the response
                thought, action, action_input = self.parse_llm_response(response)

                # Update step with thought
                self.update_step(step, thought=thought, action=action, action_input=action_input)

                # Emit thought event
                if thought:
                    yield AgentEvent.thought(thought, iteration)

                # Check for final answer
                if action == "FINAL_ANSWER":
                    final_answer = action_input.get("answer", "") if isinstance(action_input, dict) else str(action_input)
                    step.state = AgentState.COMPLETE
                    break

                # No action parsed - try to extract answer from response
                if not action:
                    logger.warning("No action parsed from response, checking for implicit answer")
                    # If response looks like a direct answer, treat it as final
                    if len(response) > 50 and "THOUGHT" not in response.upper():
                        final_answer = response
                        step.state = AgentState.COMPLETE
                        break
                    else:
                        yield AgentEvent.warning("Could not parse action from response")
                        iteration += 1
                        continue

                # Emit action event
                yield AgentEvent.action(action, action_input or {})

                # Execute the tool
                step.state = AgentState.ACTING

                try:
                    result = await self.execute_tool(action, action_input or {}, context)

                    if result.success:
                        observation = result.data
                        yield AgentEvent.observation(observation, action, success=True)
                    else:
                        observation = f"Error: {result.error}"
                        yield AgentEvent.observation(observation, action, success=False)

                    # Update step with observation
                    step.state = AgentState.OBSERVING
                    self.update_step(step, observation=observation)

                except ClarificationNeeded as e:
                    # Agent needs user input
                    step.state = AgentState.WAITING_USER
                    yield AgentEvent.clarify(e.question, e.options)
                    return  # Exit and wait for user response

                except Exception as e:
                    logger.exception(f"Tool execution failed: {action}")
                    observation = f"Tool error: {str(e)}"
                    self.update_step(step, observation=observation, error=str(e))
                    yield AgentEvent.observation(observation, action, success=False)

                iteration += 1

            # Generate final answer if we hit max iterations
            if final_answer is None and iteration >= context.max_iterations:
                logger.warning("Max iterations reached, generating best-effort answer")
                yield AgentEvent.warning("Maximum reasoning steps reached")
                final_answer = await self._generate_fallback_answer(query, context)

            # Emit final answer
            if final_answer:
                sources = self.get_sources_from_steps()

                # Run quality check if enabled
                quality_result = None
                if self.config.quality_threshold > 0:
                    quality_result = await self.run_quality_check(final_answer, sources, query)
                    if quality_result:
                        yield AgentEvent.quality_check(
                            score=quality_result.get("confidence_score", 0.0),
                            hallucination_risk=quality_result.get("hallucination_risk", 0.0),
                            warnings=quality_result.get("warnings", [])
                        )

                yield AgentEvent.final_answer(
                    answer=final_answer,
                    sources=sources if context.include_trace else None,
                    trace=self.get_trace() if context.include_trace else None,
                    confidence=quality_result.get("confidence_score") if quality_result else None
                )

            # Emit completion event
            duration = time.time() - start_time
            yield AgentEvent.complete(
                total_steps=len(self.steps),
                mode="react",
                duration=duration
            )

        except Exception as e:
            logger.exception("ReActAgent execution failed")
            yield AgentEvent.error(str(e), recoverable=False)

    def _build_prompt(self, query: str, context: AgentContext) -> str:
        """Build the prompt for the LLM."""
        # Format conversation history
        conv_history = ""
        if context.conversation_history:
            for msg in context.conversation_history[-5:]:  # Last 5 messages
                role = msg.get("role", "user")
                content = msg.get("content", "")
                conv_history += f"{role.capitalize()}: {content}\n"

        # Build scratchpad from previous steps
        scratchpad = self.build_scratchpad()

        # Get tools description
        tools_desc = self.tools.get_tools_description()

        # Format the prompt
        prompt = self.system_prompt_template.format(
            tools_description=tools_desc,
            conversation_history=conv_history or "No previous messages.",
            scratchpad=scratchpad or "No previous steps.",
            query=query
        )

        # Add custom system prompt if provided
        if context.system_prompt:
            prompt = f"{context.system_prompt}\n\n{prompt}"

        return prompt

    async def _generate_fallback_answer(self, query: str, context: AgentContext) -> str:
        """Generate a best-effort answer when max iterations reached."""
        # Summarize what we learned
        observations = []
        for step in self.steps:
            if step.observation and isinstance(step.observation, dict):
                if "documents" in step.observation:
                    for doc in step.observation["documents"][:3]:
                        if isinstance(doc, dict) and "content" in doc:
                            observations.append(doc["content"][:500])

        context_str = "\n\n".join(observations) if observations else "No relevant information found."

        fallback_prompt = f"""Based on the information gathered, provide the best possible answer to:

Question: {query}

Gathered information:
{context_str}

Provide a helpful answer based on the available information. If the information is incomplete, acknowledge what is known and what remains uncertain."""

        try:
            return await self.generate_llm_response(fallback_prompt, context)
        except Exception as e:
            logger.error(f"Fallback answer generation failed: {e}")
            return f"I was unable to fully answer your question after {len(self.steps)} reasoning steps. Based on my search, I found some relevant information but could not synthesize a complete answer."
