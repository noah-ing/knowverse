"""
Plan-and-Execute Agent implementation.

This agent creates an explicit execution plan before acting:
1. Analyze the task and create a step-by-step plan
2. Execute each step in order
3. Optionally revise the plan based on results
4. Synthesize the final answer
"""

import logging
import time
import json
import re
from dataclasses import dataclass, field
from typing import AsyncGenerator, Optional, List, Dict, Any

from .base import BaseAgent, AgentState, AgentStep, AgentContext, AgentConfig
from .events import AgentEvent, AgentEventType
from app.tools import ToolRegistry, ClarificationNeeded, get_tool_registry

logger = logging.getLogger(__name__)


PLANNING_PROMPT = """Create a step-by-step plan to answer the following question.

Question: {query}

Available tools:
{tools_description}

Create a JSON plan with the following structure:
{{
    "goal": "Brief description of what we're trying to accomplish",
    "steps": [
        {{
            "step": 1,
            "description": "What this step does",
            "tool": "tool_name or null if no tool needed",
            "tool_input": {{"param": "value"}} or null,
            "depends_on": [] // list of step numbers this depends on
        }}
    ]
}}

Important:
1. Each step should be atomic and achievable
2. Specify dependencies between steps
3. Use null for tool if the step is just reasoning
4. Keep the plan concise (3-7 steps typically)

Plan:"""


REPLAN_PROMPT = """The current plan encountered an issue. Please revise the plan.

Original question: {query}

Original plan:
{original_plan}

Failed step: {failed_step}
Error: {error}

Completed steps and their results:
{completed_steps}

Please create a revised plan that:
1. Accounts for the error that occurred
2. Uses a different approach if needed
3. Builds on the successful steps

Revised plan (same JSON format):"""


SYNTHESIS_PROMPT = """Based on the following plan execution, provide a comprehensive answer.

Original question: {query}

Executed plan:
{plan_execution}

Synthesize a complete answer based on the results of each step:"""


@dataclass
class PlanStep:
    """A step in the execution plan."""
    step_number: int
    description: str
    tool: Optional[str] = None
    tool_input: Optional[Dict[str, Any]] = None
    depends_on: List[int] = field(default_factory=list)
    status: str = "pending"
    result: Any = None
    error: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "step": self.step_number,
            "description": self.description,
            "tool": self.tool,
            "tool_input": self.tool_input,
            "depends_on": self.depends_on,
            "status": self.status,
            "result": self.result,
            "error": self.error
        }


class PlanExecuteAgent(BaseAgent):
    """
    Plan-and-Execute Agent: Create plan, then execute steps.

    This agent:
    1. Creates an explicit execution plan
    2. Executes each step in dependency order
    3. Can revise the plan if a step fails
    4. Synthesizes the final answer from results
    """

    def __init__(
        self,
        tools: Optional[ToolRegistry] = None,
        config: Optional[AgentConfig] = None,
        max_replans: int = 2
    ):
        super().__init__(tools, config)
        self.max_replans = max_replans
        self.current_plan: List[PlanStep] = []
        self.replan_count = 0

    @property
    def name(self) -> str:
        return "PlanExecuteAgent"

    async def run(
        self,
        query: str,
        context: AgentContext
    ) -> AsyncGenerator[AgentEvent, None]:
        """
        Execute the plan-and-execute process.

        Args:
            query: The user's question
            context: Execution context

        Yields:
            AgentEvent objects as the agent plans and executes
        """
        self.reset()
        self.current_plan = []
        self.replan_count = 0
        start_time = time.time()

        logger.info(f"PlanExecuteAgent starting for query: {query[:100]}...")

        try:
            # Phase 1: Planning
            yield AgentEvent.phase("planning", "Creating execution plan")

            self.current_plan = await self._create_plan(query, context)

            if not self.current_plan:
                yield AgentEvent.error("Failed to create execution plan")
                return

            # Emit the plan
            yield AgentEvent.plan(
                steps=[s.to_dict() for s in self.current_plan],
                total_steps=len(self.current_plan)
            )

            # Phase 2: Execution
            yield AgentEvent.phase("execution", f"Executing {len(self.current_plan)} steps")

            execution_success = await self._execute_plan(query, context)

            # Check if we need to synthesize results
            if not execution_success:
                yield AgentEvent.warning("Plan execution encountered issues")

            # Phase 3: Synthesis
            yield AgentEvent.phase("synthesis", "Generating final answer")

            final_answer = await self._synthesize_answer(query, context)

            # Get all sources from executed steps
            all_sources = []
            for step in self.current_plan:
                if step.result and isinstance(step.result, dict):
                    docs = step.result.get("documents", [])
                    for doc in docs:
                        if doc not in all_sources:
                            all_sources.append(doc)

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
                mode="plan_execute",
                duration=duration
            )

        except Exception as e:
            logger.exception("PlanExecuteAgent execution failed")
            yield AgentEvent.error(str(e), recoverable=False)

    async def _execute_plan(
        self,
        query: str,
        context: AgentContext
    ) -> bool:
        """Execute the plan, handling failures with replanning."""
        # Sort steps by dependencies (topological sort)
        sorted_steps = self._topological_sort(self.current_plan)

        for step in sorted_steps:
            # Check if dependencies are satisfied
            deps_satisfied = all(
                self._get_step(dep).status == "completed"
                for dep in step.depends_on
            )

            if not deps_satisfied:
                logger.warning(f"Step {step.step_number} has unsatisfied dependencies")
                step.status = "skipped"
                continue

            # Create agent step record
            agent_step = self.create_step(AgentState.EXECUTING)
            agent_step.thought = step.description

            try:
                # Execute the step
                if step.tool:
                    result = await self.tools.execute(
                        step.tool,
                        step.tool_input or {},
                        context.to_tool_context()
                    )

                    if result.success:
                        step.result = result.data
                        step.status = "completed"
                        agent_step.observation = result.data
                    else:
                        step.error = result.error
                        step.status = "failed"
                        agent_step.error = result.error

                        # Attempt replan if allowed
                        if self.config.allow_replan and self.replan_count < self.max_replans:
                            self.replan_count += 1
                            new_plan = await self._replan(query, step, context)
                            if new_plan:
                                self.current_plan = new_plan
                                return await self._execute_plan(query, context)
                else:
                    # Step doesn't require a tool (reasoning step)
                    step.status = "completed"
                    step.result = "Reasoning complete"

                self.update_step(agent_step)

            except ClarificationNeeded as e:
                step.status = "waiting"
                raise  # Propagate to main run method

            except Exception as e:
                logger.error(f"Step {step.step_number} failed: {e}")
                step.status = "failed"
                step.error = str(e)

                if self.config.allow_replan and self.replan_count < self.max_replans:
                    self.replan_count += 1
                    new_plan = await self._replan(query, step, context)
                    if new_plan:
                        self.current_plan = new_plan
                        return await self._execute_plan(query, context)

        # Check if all required steps completed
        return all(
            s.status in ("completed", "skipped")
            for s in self.current_plan
        )

    async def _create_plan(
        self,
        query: str,
        context: AgentContext
    ) -> List[PlanStep]:
        """Create an execution plan for the query."""
        tools_desc = self.tools.get_tools_description()
        prompt = PLANNING_PROMPT.format(
            query=query,
            tools_description=tools_desc
        )

        try:
            response = await self.generate_llm_response(prompt, context)
            return self._parse_plan(response)
        except Exception as e:
            logger.error(f"Plan creation failed: {e}")
            return []

    async def _replan(
        self,
        query: str,
        failed_step: PlanStep,
        context: AgentContext
    ) -> Optional[List[PlanStep]]:
        """Create a revised plan after a step failure."""
        # Format completed steps
        completed = "\n".join(
            f"Step {s.step_number}: {s.description}\nResult: {s.result}"
            for s in self.current_plan
            if s.status == "completed"
        )

        prompt = REPLAN_PROMPT.format(
            query=query,
            original_plan=json.dumps([s.to_dict() for s in self.current_plan], indent=2),
            failed_step=f"Step {failed_step.step_number}: {failed_step.description}",
            error=failed_step.error,
            completed_steps=completed or "None"
        )

        try:
            response = await self.generate_llm_response(prompt, context)
            return self._parse_plan(response)
        except Exception as e:
            logger.error(f"Replan failed: {e}")
            return None

    def _parse_plan(self, response: str) -> List[PlanStep]:
        """Parse a plan from LLM response."""
        try:
            # Find JSON in response
            json_match = re.search(r'\{[\s\S]*\}', response)
            if not json_match:
                return []

            plan_data = json.loads(json_match.group())
            steps = plan_data.get("steps", [])

            plan_steps = []
            for step_data in steps:
                plan_steps.append(PlanStep(
                    step_number=step_data.get("step", len(plan_steps) + 1),
                    description=step_data.get("description", ""),
                    tool=step_data.get("tool"),
                    tool_input=step_data.get("tool_input"),
                    depends_on=step_data.get("depends_on", [])
                ))

            return plan_steps

        except (json.JSONDecodeError, KeyError) as e:
            logger.error(f"Plan parsing failed: {e}")
            return []

    def _topological_sort(self, steps: List[PlanStep]) -> List[PlanStep]:
        """Sort steps by dependencies (topological order)."""
        # Simple implementation for small plans
        sorted_steps = []
        remaining = list(steps)

        while remaining:
            # Find steps with no unsatisfied dependencies
            ready = [
                s for s in remaining
                if all(
                    self._get_step(dep) in sorted_steps
                    for dep in s.depends_on
                )
            ]

            if not ready:
                # Cycle detected or missing dependencies, add remaining
                sorted_steps.extend(remaining)
                break

            for step in ready:
                sorted_steps.append(step)
                remaining.remove(step)

        return sorted_steps

    def _get_step(self, step_number: int) -> Optional[PlanStep]:
        """Get a plan step by number."""
        for step in self.current_plan:
            if step.step_number == step_number:
                return step
        return None

    async def _synthesize_answer(
        self,
        query: str,
        context: AgentContext
    ) -> str:
        """Synthesize final answer from plan execution results."""
        # Format plan execution
        execution_text = ""
        for step in self.current_plan:
            execution_text += f"\n## Step {step.step_number}: {step.description}\n"
            execution_text += f"Status: {step.status}\n"
            if step.result:
                result_str = json.dumps(step.result, indent=2) if isinstance(step.result, (dict, list)) else str(step.result)
                # Truncate long results
                if len(result_str) > 1000:
                    result_str = result_str[:1000] + "... [truncated]"
                execution_text += f"Result: {result_str}\n"
            if step.error:
                execution_text += f"Error: {step.error}\n"

        prompt = SYNTHESIS_PROMPT.format(
            query=query,
            plan_execution=execution_text
        )

        try:
            return await self.generate_llm_response(prompt, context)
        except Exception as e:
            logger.error(f"Synthesis failed: {e}")
            return f"I created and executed a plan but encountered an error during synthesis: {str(e)}"
