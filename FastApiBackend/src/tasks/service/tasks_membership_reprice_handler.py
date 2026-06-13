"""The membership_reprice task type — the only tasks↔memberships bridge.

The tasks engine is generic; this is the one place that knows a
``membership_reprice`` task drives ``MemberMembershipsReprice``. It both
CREATES such a task (``create`` — validate via the reprice op, then enqueue)
and RUNS one of its items (``execute_item`` — call the reprice op, record the
successor). The dependency points one way only: tasks → memberships;
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
    """Creates and runs membership_reprice tasks."""

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

    async def create(
        self,
        item_id: UUID,
        member_id: UUID,
        prorate: bool,
    ) -> UUID:
        """Validate the reprice request + create its task; returns task_id.

        Fail-fast validation (via the reprice op's ``resolve_target_price``)
        so an invalid / no-op reprice raises before any task row is written.
        Does NOT fire the run — the caller does (keeping the handler off the
        executor, so no DI cycle).

        Raises:
            ValueError: If the membership does not validate or is already on
                the active price (no no-op tasks).
        """
        resolution = await self._reprice.resolve_target_price(
            item_id,
            member_id,
        )
        return await self._tasks.create_task(
            resolution.gym_id,
            TaskType.membership_reprice,
            [
                TaskItemCreate(
                    member_id=member_id,
                    old_item_id=item_id,
                    target_price_id=resolution.target_price_id,
                    prorate=prorate,
                ),
            ],
        )

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
