"""The membership_reprice task type — the only tasks↔memberships bridge.

The tasks engine is generic; this is the one place that knows a
``membership_reprice`` task drives ``MemberMembershipsReprice``. It both
CREATES the per-plan BATCH task (``create_batch`` — discover via the reprice
op, then enqueue one item per membership) and RUNS one of its items
(``execute_item`` — call the reprice op, record the successor). Tasks are
ONLY for the batch; the single member-detail upgrade calls the reprice op
directly. The dependency points one way only: tasks → memberships;
``src.memberships`` imports nothing from ``src.tasks``.
"""

import logging
from uuid import UUID

from schema.task import TaskType
from sqlalchemy.ext.asyncio import AsyncSession  # noqa: TC002

import src.shared.db_schema_path  # noqa: F401
from src.memberships.service.memberships_reprice import (
    MemberMembershipsReprice,
)
from src.shared.database import DirectDatabasePool
from src.tasks.service.tasks_queries import TasksQueries
from src.tasks.service.tasks_service import TasksService
from src.tasks.tasks_schema import TaskItemCreate, TaskItemResponse

logger = logging.getLogger(__name__)


class MembershipRepriceTaskHandler:
    """Creates (batch) and runs membership_reprice tasks."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        reprice_service: MemberMembershipsReprice,
        tasks_service: TasksService,
    ) -> None:
        self._db_pool = db_pool
        self._reprice = reprice_service
        self._tasks = tasks_service
        self._tasks_queries = TasksQueries(db_pool)

    async def create_batch(
        self,
        gym_id: UUID,
        plan_id: UUID,
        prorate: bool,
    ) -> tuple[UUID | None, int]:
        """Discover the plan's memberships to upgrade + create ONE task.

        Auto-discovers every live membership on the plan not on its active
        price (skipping any already mid-task) and creates one
        ``membership_reprice`` task with an item per membership (each pinning
        the plan's active price). Does NOT fire the run — the caller does
        (keeping the handler off the executor, so no DI cycle).

        Returns:
            ``(task_id, membership_count)`` — ``(None, 0)`` when nothing
            needs upgrading (no task is created).
        """
        targets = await self._reprice.find_plan_reprice_targets(
            gym_id,
            plan_id,
        )
        if not targets:
            return None, 0
        task_id = await self._tasks.create_task(
            gym_id,
            TaskType.membership_reprice,
            [
                TaskItemCreate(
                    member_id=t.member_id,
                    old_item_id=t.old_item_id,
                    target_price_id=t.target_price_id,
                    prorate=prorate,
                )
                for t in targets
            ],
        )
        return task_id, len(targets)

    async def execute_item(self, item: TaskItemResponse) -> None:
        """Run one claimed reprice item; raises on failure (retried).

        An item that already carries a ``new_item_id`` finished its reprice
        on a previous run (the process died between the reprice succeeding
        and the item being marked completed) — nothing left to do.

        Raises:
            ValueError: If the item is missing its reprice parameters, or
                the reprice does not validate.
            LockBusyError / SyncNotConfirmedError: Propagated from the
                reprice (retryable; the reprice reverted itself).
        """
        if item.old_item_id is None or item.target_price_id is None:
            raise ValueError(
                f"Reprice item missing parameters: "
                f"task_item_id={item.task_item_id}"
            )
        if item.new_item_id is not None:
            return

        new_item_id = await self._reprice.reprice(
            member_id=item.member_id,
            old_item_id=item.old_item_id,
            target_price_id=item.target_price_id,
            prorate=bool(item.prorate),
        )

        session: AsyncSession
        async with self._db_pool.session() as session:
            await self._tasks_queries.set_item_new_membership(
                session,
                item.task_item_id,
                new_item_id,
            )
            await session.commit()
