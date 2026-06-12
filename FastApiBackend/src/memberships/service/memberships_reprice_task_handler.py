"""The membership_reprice task's item handler — a thin adapter, no op logic.

The bridge between the generic tasks executor and the task-agnostic
``MemberMembershipsReprice``: it translates the item's typed parameters into
a plain ``reprice(...)`` call and, on success, records the returned successor
onto the item (``task_items.new_item_id`` — the old→new linkage the CRM badge
reads). The reprice handles its own failure (verify-or-revert), so a failed
item simply carries the error — the membership is exactly as it was. The
reprice itself knows nothing about tasks; this adapter is the only place the
two meet.
"""

import logging

from sqlalchemy.ext.asyncio import AsyncSession  # noqa: TC002

import src.shared.db_schema_path  # noqa: F401
from src.memberships.service.memberships_reprice import (
    MemberMembershipsReprice,
)
from src.shared.database import DirectDatabasePool
from src.tasks.service.tasks_queries import TasksQueries
from src.tasks.tasks_schema import TaskItemResponse

logger = logging.getLogger(__name__)


class MemberMembershipsRepriceTaskHandler:
    """Adapts membership_reprice task items onto the reprice service."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        reprice_service: MemberMembershipsReprice,
    ) -> None:
        self._db_pool = db_pool
        self._reprice = reprice_service
        self._tasks_queries = TasksQueries(db_pool)

    async def execute_item(self, item: TaskItemResponse) -> None:
        """Execute one claimed reprice item; raises on failure (retried).

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
