"""Facade for task records: create, read, and the in-task guard.

Storage/reads only — RUNNING a task is ``TasksExecutor``'s job. The two are
separate services so the dependency graph stays acyclic: domain facades (e.g.
memberships) depend on this service to create/read tasks, while the executor
depends on the domains' item handlers.
"""

import logging
from uuid import UUID

from schema.task import TaskType

import src.shared.db_schema_path  # noqa: F401
from src.shared.database import DirectDatabasePool
from src.tasks.service.tasks_queries import TasksQueries
from src.tasks.tasks_exceptions import MembershipInTaskError
from src.tasks.tasks_schema import TaskItemCreate, TaskResponse

logger = logging.getLogger(__name__)


class TasksService:
    """Create and read tracked background tasks."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._queries = TasksQueries(db_pool)

    async def create_task(
        self,
        gym_id: UUID,
        task_type: TaskType,
        items: list[TaskItemCreate],
    ) -> UUID:
        """Create a task + its items atomically ('pending'); returns task_id.

        Raises:
            ValueError: If the task has no items.
        """
        if not items:
            raise ValueError("A task needs at least one item")
        return await self._queries.insert_task_with_items(
            gym_id,
            task_type.value,
            items,
        )

    async def get_task(
        self,
        task_id: UUID,
        gym_id: UUID,
    ) -> TaskResponse | None:
        """Read one task + items, gym-scoped (None if not found)."""
        return await self._queries.get_task(task_id, gym_id)

    async def list_ongoing_tasks(self, gym_id: UUID) -> list[TaskResponse]:
        """A gym's unfinished tasks with items — the CRM's polling list.

        Each item carries old_item_id/new_item_id, so the memberships screen
        can badge any membership that is currently inside a task.
        """
        return await self._queries.list_ongoing_tasks(gym_id)

    async def assert_memberships_not_in_task(
        self,
        item_ids: list[UUID],
    ) -> None:
        """The in-task guard: reject mutations on task-referenced memberships.

        Raises:
            MembershipInTaskError: If any of the membership rows is referenced
                by a pending/running task item (as the row being acted on or
                as its successor).
        """
        in_task = await self._queries.memberships_in_active_task(item_ids)
        if in_task:
            raise MembershipInTaskError(
                f"Membership(s) {sorted(str(i) for i in in_task)} are part "
                f"of an in-progress task; retry once it finishes"
            )
