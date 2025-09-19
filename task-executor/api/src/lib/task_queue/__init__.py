"""Task queue library for managing task lifecycle and polling."""

from typing import Optional, List, Dict, Any
from datetime import datetime, timedelta
import uuid
import os
from sqlalchemy import select, update, and_, or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import UUID

from ...models import Task, TaskStatus, Worker, WorkerStatus
from ...config.logging import get_logger

logger = get_logger(__name__)


def _resolve_default_model() -> str:
    """Return the default LLM model to record with tasks."""
    for env_var in ("OPENROUTER_MODEL", "OPENAI_MODEL", "DEFAULT_AGENT_MODEL"):
        value = os.getenv(env_var)
        if value:
            return value
    return "gpt-4"


class TaskQueue:
    """Task queue manager for database-backed task queueing."""

    def __init__(self, session: AsyncSession):
        """Initialize task queue with database session."""
        self.session = session

    async def create_task(
        self,
        problem_id: str,
        parameters: Dict[str, Any]
    ) -> Task:
        """Create a new task in pending state."""
        # Set defaults for parameters
        params = {
            "max_steps": 30,
            "timeout_minutes": 30,
            "priority": 5,
            **parameters  # User parameters override defaults
        }

        agent_config = dict(params.get("agent_config") or {})
        model = str(agent_config.get("model", "")).strip()
        if not model:
            agent_config["model"] = _resolve_default_model()

        params["agent_config"] = agent_config

        task = Task(
            problem_id=problem_id,
            status=TaskStatus.PENDING,
            parameters=params
        )

        self.session.add(task)
        await self.session.commit()
        await self.session.refresh(task)

        logger.info(
            "task.created",
            task_id=str(task.id),
            problem_id=problem_id,
            priority=params.get("priority", 5)
        )

        return task

    async def claim_next_task(self, worker_id: str) -> Optional[Task]:
        """Claim next available task for worker (atomic operation)."""

        worker = await self.session.get(Worker, worker_id)
        if not worker:
            raise ValueError(f"Worker {worker_id} not found")

        backend_type = worker.backend_type

        # Build task query filtered by backend/capabilities.
        query = (
            select(Task)
            .where(Task.status == TaskStatus.PENDING)
            .where(
                or_(
                    ~Task.parameters.has_key("backend_type"),
                    Task.parameters["backend_type"].astext == backend_type,
                )
            )
            .order_by(
                Task.parameters["priority"].desc(),
                Task.created_at.asc()
            )
            .limit(1)
            .with_for_update(skip_locked=True)
        )

        result = await self.session.execute(query)
        task = result.scalar_one_or_none()

        if task:
            # Update task with worker assignment
            task.status = TaskStatus.RUNNING
            task.worker_id = worker_id
            task.started_at = datetime.utcnow()
            task.updated_at = datetime.utcnow()

            await self.session.commit()
            await self.session.refresh(task)

            logger.info(
                "task.claimed",
                task_id=str(task.id),
                worker_id=worker_id,
                problem_id=task.problem_id
            )

            return task

        return None

    async def complete_task(
        self,
        task_id: UUID,
        result: Dict[str, Any]
    ) -> Task:
        """Mark task as completed with results."""
        task = await self.get_task(task_id)
        if not task:
            raise ValueError(f"Task {task_id} not found")

        if not task.can_transition_to(TaskStatus.COMPLETED):
            raise ValueError(f"Task {task_id} cannot transition to completed from {task.status}")

        task.status = TaskStatus.COMPLETED
        task.result = result
        task.completed_at = datetime.utcnow()
        task.updated_at = datetime.utcnow()

        await self.session.commit()
        await self.session.refresh(task)

        logger.info(
            "task.completed",
            task_id=str(task_id),
            duration_seconds=(task.completed_at - task.started_at).total_seconds() if task.started_at else 0
        )

        return task

    async def fail_task(
        self,
        task_id: UUID,
        error_details: str
    ) -> Task:
        """Mark task as failed with error details."""
        task = await self.get_task(task_id)
        if not task:
            raise ValueError(f"Task {task_id} not found")

        if not task.can_transition_to(TaskStatus.FAILED):
            raise ValueError(f"Task {task_id} cannot transition to failed from {task.status}")

        task.status = TaskStatus.FAILED
        task.error_details = error_details
        task.completed_at = datetime.utcnow()
        task.updated_at = datetime.utcnow()

        await self.session.commit()
        await self.session.refresh(task)

        logger.error(
            "task.failed",
            task_id=str(task_id),
            error=error_details[:200]  # Log first 200 chars of error
        )

        return task

    async def timeout_task(self, task_id: UUID) -> Task:
        """Mark task as timed out."""
        task = await self.get_task(task_id)
        if not task:
            raise ValueError(f"Task {task_id} not found")

        if not task.can_transition_to(TaskStatus.TIMEOUT):
            raise ValueError(f"Task {task_id} cannot transition to timeout from {task.status}")

        timeout_minutes = task.parameters.get("timeout_minutes", 30)
        task.status = TaskStatus.TIMEOUT
        task.error_details = f"Task exceeded timeout limit of {timeout_minutes} minutes"
        task.completed_at = datetime.utcnow()
        task.updated_at = datetime.utcnow()

        await self.session.commit()
        await self.session.refresh(task)

        logger.warning(
            "task.timeout",
            task_id=str(task_id),
            timeout_minutes=timeout_minutes
        )

        return task

    async def cancel_task(self, task_id: UUID) -> Task:
        """Cancel a pending or running task."""
        task = await self.get_task(task_id)
        if not task:
            raise ValueError(f"Task {task_id} not found")

        if not task.can_transition_to(TaskStatus.CANCELLED):
            raise ValueError(f"Task {task_id} cannot be cancelled from {task.status}")

        task.status = TaskStatus.CANCELLED
        task.completed_at = datetime.utcnow()
        task.updated_at = datetime.utcnow()

        await self.session.commit()
        await self.session.refresh(task)

        logger.info("task.cancelled", task_id=str(task_id))

        return task

    async def get_task(self, task_id: UUID) -> Optional[Task]:
        """Get task by ID."""
        query = select(Task).where(Task.id == task_id)
        result = await self.session.execute(query)
        return result.scalar_one_or_none()

    async def list_tasks(
        self,
        status: Optional[TaskStatus] = None,
        problem_id: Optional[str] = None,
        worker_id: Optional[str] = None,
        limit: int = 20,
        offset: int = 0,
        sort: str = "-created_at"
    ) -> tuple[List[Task], int]:
        """List tasks with filtering and pagination."""
        # Build query with filters
        query = select(Task)
        count_query = select(Task)

        conditions = []
        if status:
            conditions.append(Task.status == status)
        if problem_id:
            conditions.append(Task.problem_id == problem_id)
        if worker_id:
            conditions.append(Task.worker_id == worker_id)

        if conditions:
            query = query.where(and_(*conditions))
            count_query = count_query.where(and_(*conditions))

        # Apply sorting
        if sort.startswith("-"):
            order_field = getattr(Task, sort[1:])
            query = query.order_by(order_field.desc())
        else:
            order_field = getattr(Task, sort)
            query = query.order_by(order_field.asc())

        # Apply pagination
        query = query.limit(limit).offset(offset)

        # Execute queries
        result = await self.session.execute(query)
        tasks = result.scalars().all()

        count_result = await self.session.execute(count_query)
        total = len(count_result.scalars().all())

        return tasks, total

    async def check_timeouts(self) -> List[Task]:
        """Check for tasks that have exceeded their timeout."""
        now = datetime.utcnow()
        timeout_tasks = []

        # Find running tasks that have exceeded timeout
        query = select(Task).where(
            and_(
                Task.status == TaskStatus.RUNNING,
                Task.started_at != None
            )
        )

        result = await self.session.execute(query)
        running_tasks = result.scalars().all()

        for task in running_tasks:
            timeout_minutes = task.parameters.get("timeout_minutes", 30)
            if task.started_at:
                elapsed = (now - task.started_at.replace(tzinfo=None)).total_seconds() / 60
                if elapsed > timeout_minutes:
                    timeout_task = await self.timeout_task(task.id)
                    timeout_tasks.append(timeout_task)

        return timeout_tasks

    async def get_queue_stats(self) -> Dict[str, int]:
        """Get statistics about the task queue."""
        stats = {}

        for status in TaskStatus:
            query = select(Task).where(Task.status == status)
            result = await self.session.execute(query)
            count = len(result.scalars().all())
            stats[status.value] = count

        return stats


# Export main class and functions
__all__ = ["TaskQueue"]
