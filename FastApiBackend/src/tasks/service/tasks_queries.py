"""All DB access for the tasks domain (service-role writes, staff reads)."""

import logging
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.tasks import SQL_DIR
from src.tasks.tasks_schema import (
    TaskItemCreate,
    TaskItemResponse,
    TaskResponse,
)

logger = logging.getLogger(__name__)


class TasksQueries:
    """SQL access for tasks + task_items.

    Every method opens its own session, except
    ``set_item_new_membership`` — that stamp must land atomically with the
    operation's own DB writes, so it executes on the CALLER's session (no
    commit here).
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    # ── Create ─────────────────────────────────────────────────

    async def insert_task_with_items(
        self,
        gym_id: UUID,
        task_type: str,
        items: list[TaskItemCreate],
    ) -> UUID:
        """Insert one task + all its items atomically; returns the task_id."""
        task_sql = load_sql(SQL_DIR / "tasks_insert.sql")
        items_sql = load_sql(SQL_DIR / "task_items_insert.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(task_sql),
                {"gym_id": str(gym_id), "task_type": task_type},
            )
            task_id = UUID(str(result.scalar_one()))
            await session.execute(
                text(items_sql),
                {
                    "task_id": str(task_id),
                    "gym_id": str(gym_id),
                    "member_ids": [str(i.member_id) for i in items],
                    "old_item_ids": [
                        str(i.old_item_id) if i.old_item_id else None
                        for i in items
                    ],
                    "target_price_ids": [
                        str(i.target_price_id) if i.target_price_id else None
                        for i in items
                    ],
                    "prorates": [i.prorate for i in items],
                },
            )
            await session.commit()
        return task_id

    # ── Reads ──────────────────────────────────────────────────

    async def get_task(
        self,
        task_id: UUID,
        gym_id: UUID,
    ) -> TaskResponse | None:
        """Read one task + its items, gym-scoped."""
        sql = load_sql(SQL_DIR / "tasks_get.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"task_id": str(task_id), "gym_id": str(gym_id)},
            )
            row = result.mappings().fetchone()
        if row is None:
            return None
        items = await self._get_items_for_tasks([task_id])
        return self._to_task_response(dict(row), items.get(task_id, []))

    async def list_ongoing_tasks(self, gym_id: UUID) -> list[TaskResponse]:
        """A gym's unfinished (pending/running) tasks with their items."""
        sql = load_sql(SQL_DIR / "tasks_list_ongoing.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"gym_id": str(gym_id)},
            )
            rows = [dict(r) for r in result.mappings().fetchall()]
        if not rows:
            return []
        items = await self._get_items_for_tasks(
            [UUID(str(r["task_id"])) for r in rows]
        )
        return [
            self._to_task_response(
                row,
                items.get(UUID(str(row["task_id"])), []),
            )
            for row in rows
        ]

    async def list_unfinished_task_ids(self) -> list[UUID]:
        """Every unfinished task across all gyms (crash-recovery sweep)."""
        sql = load_sql(SQL_DIR / "tasks_list_unfinished.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql))
            return [UUID(str(r[0])) for r in result.fetchall()]

    async def get_items_for_task(
        self,
        task_id: UUID,
    ) -> list[TaskItemResponse]:
        """Read one task's items (oldest first)."""
        items = await self._get_items_for_tasks([task_id])
        return items.get(task_id, [])

    async def memberships_in_active_task(
        self,
        item_ids: list[UUID],
    ) -> set[UUID]:
        """Which of these membership rows an UNFINISHED task item references."""
        if not item_ids:
            return set()
        sql = load_sql(SQL_DIR / "task_items_active_for_memberships.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"item_ids": [str(i) for i in item_ids]},
            )
            return {UUID(str(r[0])) for r in result.fetchall()}

    # ── Item lifecycle ─────────────────────────────────────────

    async def claim_item(
        self,
        task_item_id: UUID,
    ) -> TaskItemResponse | None:
        """Atomically claim a pending item; None if it wasn't claimable."""
        return await self._claim(
            "task_item_claim.sql",
            {"task_item_id": str(task_item_id)},
        )

    async def claim_stale_item(
        self,
        task_item_id: UUID,
        stale_seconds: int,
    ) -> TaskItemResponse | None:
        """Reclaim a stale 'running' item left by a dead process."""
        return await self._claim(
            "task_item_claim_stale.sql",
            {
                "task_item_id": str(task_item_id),
                "stale_seconds": stale_seconds,
            },
        )

    async def complete_item(self, task_item_id: UUID) -> None:
        """Mark a running item completed (terminal)."""
        await self._update_item(
            "task_item_complete.sql",
            {"task_item_id": str(task_item_id)},
        )

    async def release_item_for_retry(
        self,
        task_item_id: UUID,
        error_message: str,
    ) -> None:
        """Record the error and release the item back to 'pending'."""
        await self._update_item(
            "task_item_release_retry.sql",
            {
                "task_item_id": str(task_item_id),
                "error_message": error_message,
            },
        )

    async def fail_item(
        self,
        task_item_id: UUID,
        error_message: str,
    ) -> None:
        """Mark a running item failed (terminal, after max attempts)."""
        await self._update_item(
            "task_item_fail.sql",
            {
                "task_item_id": str(task_item_id),
                "error_message": error_message,
            },
        )

    async def finalize_task_status(self, task_id: UUID) -> None:
        """Recompute the task's status from its items."""
        sql = load_sql(SQL_DIR / "tasks_finalize_status.sql")
        async with self._db_pool.session() as session:
            await session.execute(text(sql), {"task_id": str(task_id)})
            await session.commit()

    async def set_item_new_membership(
        self,
        session: AsyncSession,
        task_item_id: UUID,
        new_item_id: UUID,
    ) -> None:
        """Stamp the successor membership row onto the item.

        Executes on the CALLER's session (no commit) so the stamp lands
        atomically with the operation's own DB writes — the durable
        "DB phase done" marker.
        """
        sql = load_sql(SQL_DIR / "task_item_set_new_membership.sql")
        await session.execute(
            text(sql),
            {
                "task_item_id": str(task_item_id),
                "new_item_id": str(new_item_id),
            },
        )

    # ── Private ────────────────────────────────────────────────

    async def _claim(
        self,
        sql_name: str,
        params: dict,
    ) -> TaskItemResponse | None:
        sql = load_sql(SQL_DIR / sql_name)
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = result.mappings().fetchone()
            await session.commit()
        return TaskItemResponse(**dict(row)) if row else None

    async def _update_item(self, sql_name: str, params: dict) -> None:
        sql = load_sql(SQL_DIR / sql_name)
        async with self._db_pool.session() as session:
            await session.execute(text(sql), params)
            await session.commit()

    async def _get_items_for_tasks(
        self,
        task_ids: list[UUID],
    ) -> dict[UUID, list[TaskItemResponse]]:
        sql = load_sql(SQL_DIR / "task_items_get_for_tasks.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"task_ids": [str(t) for t in task_ids]},
            )
            rows = result.mappings().fetchall()
        items: dict[UUID, list[TaskItemResponse]] = {}
        for row in rows:
            item = TaskItemResponse(**dict(row))
            items.setdefault(item.task_id, []).append(item)
        return items

    @staticmethod
    def _to_task_response(
        row: dict,
        items: list[TaskItemResponse],
    ) -> TaskResponse:
        return TaskResponse(**row, items=items)
