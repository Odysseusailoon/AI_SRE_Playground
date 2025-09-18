"""Real task executor using AIOpsLab Orchestrator."""

import os
import sys
import asyncio
import uuid
from typing import Dict, Any, Optional, Tuple
from datetime import datetime
import json
from pathlib import Path
import asyncio
from dotenv import load_dotenv

# Load environment variables from .env file
env_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../../../../../.env'))
if os.path.exists(env_path):
    load_dotenv(env_path)
else:
    # Try alternative path
    env_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../../../.env'))
    if os.path.exists(env_path):
        load_dotenv(env_path)

# Add AIOpsLab to path - need to go up from task-executor/api/src/workers
aiopslab_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../../../'))
if aiopslab_path not in sys.path:
    sys.path.insert(0, aiopslab_path)

from aiopslab.orchestrator import Orchestrator
from aiopslab.session import Session
from sqlalchemy.ext.asyncio import AsyncSession

from .executor import TaskExecutor
from ..models import Task, LLMConversation, MessageRole
from ..config.logging import get_logger
from ..config.settings import settings

logger = get_logger(__name__)


class OrchestratorExecutor(TaskExecutor):
    """Execute tasks using real AIOpsLab Orchestrator with Kind clusters."""

    def __init__(self, worker_id: str, session: AsyncSession, backend_type: str = "orchestrator"):
        """Initialize the orchestrator executor."""
        super().__init__(worker_id, backend_type)
        self.session = session
        self.cluster_name = f"aiopslab-{worker_id}"
        self.orchestrator = None
        self.current_conversation = None
        self.agent = None

    @staticmethod
    def _get_default_model() -> Optional[str]:
        """Resolve default LLM model from environment variables."""
        for env_var in ("OPENROUTER_MODEL", "OPENAI_MODEL", "DEFAULT_AGENT_MODEL"):
            value = os.getenv(env_var)
            if value:
                return value
        return "gpt-4"

    def _prepare_agent_config(self, config: Optional[Dict[str, Any]]) -> Dict[str, Any]:
        """Normalize agent configuration and apply environment defaults."""
        prepared: Dict[str, Any] = dict(config or {})

        model = str(prepared.get("model", "")).strip()
        if not model:
            prepared["model"] = self._get_default_model()

        return prepared

    async def setup_cluster(self):
        """Create and setup Kind cluster for this worker."""
        try:
            # Check if cluster exists
            stdout, stderr, code = await self._run_command(
                "kind", "get", "clusters"
            )

            if code != 0:
                logger.error(
                    "orchestrator.kind.list_failed",
                    worker_id=self.worker_id,
                    stderr=stderr.strip()
                )
                return False

            clusters = {line.strip() for line in stdout.splitlines() if line.strip()}
            needs_create = self.cluster_name not in clusters

            if not needs_create:
                _, _, nodes_code = await self._run_command(
                    "kubectl",
                    "--context",
                    f"kind-{self.cluster_name}",
                    "get",
                    "nodes",
                )
                if nodes_code != 0:
                    logger.warning(
                        "orchestrator.cluster.unhealthy",
                        worker_id=self.worker_id,
                        cluster_name=self.cluster_name
                    )
                    await self._run_command(
                        "kind", "delete", "cluster", "--name", self.cluster_name
                    )
                    needs_create = True

            if needs_create:
                logger.info(
                    "orchestrator.cluster.creating",
                    worker_id=self.worker_id,
                    cluster_name=self.cluster_name
                )

                # Create Kind cluster
                await self._run_command(
                    "kind", "create", "cluster", "--name", self.cluster_name,
                    check=True
                )

                logger.info(
                    "orchestrator.cluster.created",
                    worker_id=self.worker_id,
                    cluster_name=self.cluster_name
                )
            else:
                logger.info(
                    "orchestrator.cluster.exists",
                    worker_id=self.worker_id,
                    cluster_name=self.cluster_name
                )

            # Set kubectl context
            await self._run_command(
                "kubectl", "config", "use-context", f"kind-{self.cluster_name}",
                check=True
            )

            return True

        except Exception as e:
            logger.error(
                "orchestrator.cluster.failed",
                worker_id=self.worker_id,
                error=str(e)
            )
            return False

    async def execute(self, task: Task) -> Dict[str, Any]:
        """Execute a task using the real orchestrator."""
        try:
            logger.info(
                "orchestrator.task.start",
                task_id=str(task.id),
                problem_id=task.problem_id,
                worker_id=self.worker_id
            )

            # Setup cluster
            if not await self.setup_cluster():
                return {
                    "success": False,
                    "error": "Failed to setup Kind cluster"
                }

            previous_container = os.getenv("KIND_CONTAINER_NAME")
            os.environ["KIND_CONTAINER_NAME"] = f"{self.cluster_name}-control-plane"

            try:
                # Initialize orchestrator
                results_dir = Path("/tmp/aiopslab") / str(task.id)
                results_dir.mkdir(parents=True, exist_ok=True)
                self.orchestrator = Orchestrator(results_dir=results_dir)

                # Create conversation record
                agent_config = self._prepare_agent_config(task.parameters.get("agent_config"))
                self.current_conversation = await self._create_conversation(task, agent_config)

                # Initialize the agent based on config
                agent = await self._create_agent(agent_config)
                if not agent:
                    return {
                        "success": False,
                        "error": "Failed to create agent"
                    }
                self.agent = agent

                # Ensure conversation reflects the actual model being used
                resolved_model = getattr(agent, "model", None)
                if self.current_conversation and resolved_model:
                    self.current_conversation.model_name = resolved_model
                    await self.session.commit()

                # Create logging wrapper to capture conversations
                from .llm_logging_agent import LLMLoggingAgent
                logging_agent = LLMLoggingAgent(
                    agent,
                    self.current_conversation,
                    self.session
                )

                # Register agent with orchestrator
                self.orchestrator.register_agent(logging_agent)

                # Initialize and run the problem
                prob_desc, task_desc, actions = self.orchestrator.init_problem(task.problem_id)
                session = self.orchestrator.session

                if hasattr(agent, "init_context"):
                    actions_str = json.dumps(actions, indent=2) if isinstance(actions, (dict, list)) else str(actions)
                    try:
                        agent.init_context(prob_desc, task_desc, actions_str)
                    except Exception as e:
                        logger.warning("orchestrator.agent.init_context.failed", error=str(e))

                # Log initial problem description
                await self._log_message(
                    MessageRole.SYSTEM,
                    f"Problem: {prob_desc}\nTask: {task_desc}",
                    metadata={
                        "problem_id": task.problem_id,
                        "task_type": session.problem.__class__.__name__ if session and session.problem else None
                    }
                )

                # Run the orchestrator
                logger.info(
                    "orchestrator.running",
                    task_id=str(task.id),
                    problem_id=task.problem_id
                )

                # Run orchestrator (this will interact with the agent)
                max_steps = task.parameters.get("max_steps", settings.DEFAULT_MAX_STEPS)
                success, solution = await self._run_orchestrator(max_steps=max_steps)

                conversation_id = None
                total_messages = None
                if self.current_conversation:
                    conversation_id = str(self.current_conversation.id)
                    total_messages = self.current_conversation.total_messages

                # Mark conversation as ended
                await self._end_conversation(success=success)

                # Get execution results
                result = {
                    "success": success,
                    "solution": solution,
                    "problem_id": task.problem_id,
                    "execution_time": datetime.utcnow().isoformat(),
                    "conversation_id": conversation_id,
                    "total_messages": total_messages,
                "session_id": str(session.session_id) if session else None
            }

                logger.info(
                    "orchestrator.task.complete",
                    task_id=str(task.id),
                    success=success,
                    conversation_id=conversation_id
                )

                return result
            finally:
                if previous_container is None:
                    os.environ.pop("KIND_CONTAINER_NAME", None)
                else:
                    os.environ["KIND_CONTAINER_NAME"] = previous_container

        except Exception as e:
            logger.exception(
                "orchestrator.task.failed",
                task_id=str(task.id)
            )

            if self.current_conversation:
                await self._log_message(
                    MessageRole.SYSTEM,
                    f"Task execution failed: {str(e)}",
                    metadata={"error": str(e)}
                )
                await self._end_conversation(success=False, error=str(e))

            return {
                "success": False,
                "error": str(e),
                "execution_time": datetime.utcnow().isoformat()
            }

    async def _create_agent(self, agent_config: Dict[str, Any]):
        """Create the appropriate agent based on configuration."""
        model = agent_config.get("model") or self._get_default_model()
        model = str(model).strip()
        use_openrouter = agent_config.get("use_openrouter", False)

        try:
            # Use our simplified GPTAgent that doesn't have external dependencies
            from .simple_gpt_agent import GPTAgent

            if use_openrouter or os.getenv("OPENROUTER_API_KEY"):
                # Use OpenRouter for any model
                api_key = os.getenv("OPENROUTER_API_KEY")
                base_url = os.getenv("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")

                if not api_key:
                    logger.error("orchestrator.agent.no_openrouter_key", model=model)
                    return None

                # OpenRouter supports many models with unified API
                # Map common model names to OpenRouter format
                openrouter_model = model
                if "/" not in model:  # Not already in openrouter format
                    model_mapping = {
                        "gpt-4": "openai/gpt-4",
                        "gpt-4-turbo": "openai/gpt-4-turbo",
                        "gpt-4o": "openai/gpt-4o",
                        "gpt-4o-mini": "openai/gpt-4o-mini",
                        "gpt-3.5-turbo": "openai/gpt-3.5-turbo",
                        "claude-3-opus": "anthropic/claude-3-opus",
                        "claude-3-sonnet": "anthropic/claude-3-sonnet",
                        "claude-3-haiku": "anthropic/claude-3-haiku",
                        "llama-3-70b": "meta-llama/llama-3-70b-instruct",
                        "mixtral-8x7b": "mistralai/mixtral-8x7b-instruct"
                    }
                    openrouter_model = model_mapping.get(model, f"openai/{model}")

                logger.info(
                    "orchestrator.agent.using_openrouter",
                    model=openrouter_model,
                    base_url=base_url
                )

                # Use simplified GPTAgent with OpenRouter
                return GPTAgent(
                    model=openrouter_model,
                    api_key=api_key,
                    temperature=agent_config.get("temperature", 0.7),
                    base_url=base_url
                )

            elif model.startswith("gpt") or model.startswith("o1"):
                # Try OpenAI first, fall back to OpenRouter
                api_key = os.getenv("OPENAI_API_KEY")
                if api_key:
                    return GPTAgent(
                        model=model,
                        api_key=api_key,
                        temperature=agent_config.get("temperature", 0.7)
                    )

                # Fall back to OpenRouter if available
                openrouter_key = os.getenv("OPENROUTER_API_KEY")
                if openrouter_key:
                    base_url = os.getenv("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")
                    # Map to OpenRouter format
                    openrouter_model = f"openai/{model}" if "/" not in model else model
                    logger.info(
                        "orchestrator.agent.fallback_openrouter",
                        model=openrouter_model
                    )
                    return GPTAgent(
                        model=openrouter_model,
                        api_key=openrouter_key,
                        temperature=agent_config.get("temperature", 0.7),
                        base_url=base_url
                    )

                logger.error("orchestrator.agent.no_api_key", model=model)
                return None

            elif model.startswith("claude"):
                # Claude agent via OpenRouter
                api_key = os.getenv("OPENROUTER_API_KEY")
                base_url = os.getenv("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")

                if not api_key:
                    logger.error("orchestrator.agent.no_api_key", model=model)
                    return None

                # Map claude model names to OpenRouter format
                claude_model = model
                if "/" not in model:
                    claude_mapping = {
                        "claude-3-opus": "anthropic/claude-3-opus",
                        "claude-3-sonnet": "anthropic/claude-3-sonnet",
                        "claude-3-haiku": "anthropic/claude-3-haiku",
                        "claude": "anthropic/claude-3-opus"
                    }
                    claude_model = claude_mapping.get(model, f"anthropic/{model}")

                return GPTAgent(
                    model=claude_model,
                    api_key=api_key,
                    temperature=agent_config.get("temperature", 0.7),
                    base_url=base_url
                )
            else:
                logger.error("orchestrator.agent.unknown_model", model=model)
                return None

        except Exception as e:
            logger.error(
                "orchestrator.agent.creation_failed",
                model=model,
                error=str(e)
            )
            return None

    async def _run_orchestrator(self, max_steps: int):
        """Run the orchestrator and capture results."""
        try:
            result = await self.orchestrator.start_problem(max_steps=max_steps)

            session = self.orchestrator.session
            solved = False
            solution = None

            results_payload = None
            if isinstance(result, dict):
                results_payload = result.get("results") if "results" in result else result

            if results_payload:
                if isinstance(results_payload, dict):
                    if "success" in results_payload:
                        solved = bool(results_payload.get("success"))
                    elif "Detection Accuracy" in results_payload:
                        solved = str(results_payload.get("Detection Accuracy", "")).lower() == "correct"
                solution = results_payload

            if session:
                session_results = getattr(session, "results", None)
                if isinstance(session_results, dict):
                    if "success" in session_results:
                        solved = bool(session_results.get("success"))
                    elif "Detection Accuracy" in session_results:
                        solved = str(session_results.get("Detection Accuracy", "")).lower() == "correct"
                solution = session_results
                if not solution and hasattr(session, "get_solution"):
                    solution = session.get_solution()

            serializable_solution = json.loads(json.dumps(solution or result, default=str))

            return solved, serializable_solution

        except Exception as e:
            logger.exception("orchestrator.run.failed")
            return False, str(e)

    async def _create_conversation(self, task: Task, agent_config: Dict) -> LLMConversation:
        """Create a new conversation record."""
        model_name = str(agent_config.get("model") or self._get_default_model()).strip()

        conversation = LLMConversation(
            task_id=task.id,
            session_id=uuid.uuid4(),
            model_name=model_name,
            model_config={
                "temperature": agent_config.get("temperature", 0.7),
                "max_tokens": agent_config.get("max_tokens", 4000),
                "top_p": agent_config.get("top_p", 1.0)
            },
            messages=[],
            conversation_metadata={
                "problem_id": task.problem_id,
                "worker_id": self.worker_id,
                "cluster_name": self.cluster_name
            }
        )

        self.session.add(conversation)
        await self.session.commit()
        await self.session.refresh(conversation)

        return conversation

    async def _log_message(
        self,
        role: MessageRole,
        content: str,
        function_name: Optional[str] = None,
        function_args: Optional[Dict] = None,
        function_result: Optional[Any] = None,
        metadata: Optional[Dict] = None
    ):
        """Log a message to the current conversation."""
        if not self.current_conversation:
            return

        message = {
            "timestamp": datetime.utcnow().isoformat(),
            "role": role.value,
            "content": content
        }

        if function_name:
            message["function_name"] = function_name
        if function_args:
            message["function_args"] = function_args
        if function_result:
            message["function_result"] = function_result
        if metadata:
            message["metadata"] = metadata

        # Create a new list to trigger SQLAlchemy's change detection
        messages_copy = list(self.current_conversation.messages)
        messages_copy.append(message)
        self.current_conversation.messages = messages_copy
        self.current_conversation.total_messages += 1

        await self.session.commit()

    async def _end_conversation(self, success: bool = True, error: Optional[str] = None):
        """Mark the conversation as ended."""
        if not self.current_conversation:
            return

        self.current_conversation.ended_at = datetime.utcnow()

        if not isinstance(self.current_conversation.conversation_metadata, dict):
            self.current_conversation.conversation_metadata = {}

        self.current_conversation.conversation_metadata["success"] = success
        if error:
            self.current_conversation.conversation_metadata["error"] = error

        # Calculate approximate token usage based on message content
        total_chars = sum(len(msg.get("content", "")) for msg in self.current_conversation.messages)
        estimated_tokens = total_chars // 4  # Rough estimation

        self.current_conversation.total_tokens = estimated_tokens

        # Estimate cost based on model
        model = self.current_conversation.model_name
        if "gpt-4" in model:
            cost_per_1k = 0.03  # GPT-4 approximate cost
        elif "gpt-3.5" in model:
            cost_per_1k = 0.002  # GPT-3.5 approximate cost
        elif "claude" in model:
            cost_per_1k = 0.01  # Claude approximate cost
        else:
            cost_per_1k = 0.01  # Default

        self.current_conversation.total_cost = {
            "input_tokens": estimated_tokens * 0.6,
            "output_tokens": estimated_tokens * 0.4,
            "total_cost": (estimated_tokens / 1000) * cost_per_1k
        }

        await self.session.commit()
        self.current_conversation = None

    async def cleanup(self):
        """Cleanup resources."""
        # Optionally delete the Kind cluster
        # subprocess.run(["kind", "delete", "cluster", "--name", self.cluster_name])
        pass

    async def _run_command(self, *cmd, check: bool = False) -> Tuple[str, str, int]:
        """Run a shell command asynchronously."""
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await process.communicate()
        if check and process.returncode != 0:
            raise RuntimeError(
                f"Command {' '.join(cmd)} failed with {process.returncode}: {stderr.decode().strip()}"
            )
        return stdout.decode(), stderr.decode(), process.returncode
