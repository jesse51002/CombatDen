"""The membership_reprice task's item handler — a thin adapter, no op logic.

The bridge between the generic tasks executor and the task-agnostic
``MemberMembershipsReprice``: it translates the item's typed parameters into
a plain ``reprice(...)`` call and persists the old→new linkage
(``task_items.new_item_id``) via the reprice's generic in-transaction hook —
the durable marker the orphan-sweep exclusion and the CRM badge read. The
reprice itself knows nothing about tasks; this adapter is the only place the
two meet.
"""

import logging
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

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
        self._reprice = reprice_service
        self._tasks_queries = TasksQueries(db_pool)

    async def execute_item(self, item: TaskItemResponse) -> None:
        """Execute one claimed reprice item; raises on failure (retried).

        Raises:
            ValueError: If the item is missing its reprice parameters, or
                the reprice no longer validates.
            LockBusyError / SyncNotConfirmedError: Propagated from the
                reprice (retryable).
        """
        if item.old_item_id is None or item.target_price_id is None:
            raise ValueError(
                f"Reprice item missing parameters: "
                f"task_item_id={item.task_item_id}"
            )

        async def _record(session: AsyncSession, new_item_id: UUID) -> None:
            await self._tasks_queries.set_item_new_membership(
                session,
                item.task_item_id,
                new_item_id,
            )

        await self._reprice.reprice(
            member_id=item.member_id,
            old_item_id=item.old_item_id,
            target_price_id=item.target_price_id,
            prorate=bool(item.prorate),
            record_successor=_record,
        )
