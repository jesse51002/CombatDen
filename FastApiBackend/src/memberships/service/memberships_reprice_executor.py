"""The membership_reprice task's per-item executor (append-only reprice).

A reprice never mutates the membership row — ``price_id`` and
``stripe_item_id`` are trigger-enforced immutable. Instead, one DB
transaction cancels the old row effective today, inserts its successor at the
target price (pending, NULL line id), copies the live applied discounts onto
the successor, and stamps the successor onto the task item (the durable
"DB phase done" marker). The EXISTING payment sync then converges Stripe —
old consolidated line decremented or removed, new line created or joined,
prorated per the request — and the existing writeback stamps the successor
``applied`` and the old row ``deleted``.

No revert on failure: the transaction IS the desired state. A retry (or the
reconciler's push sweep) re-runs the convergent sync; an item whose
``new_item_id`` is already stamped skips straight to it.
"""

import logging
from datetime import date
from uuid import UUID, uuid4

from schema.member_membership import StripeSyncStatus
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.shared.database import DirectDatabasePool
from src.shared.db_first_helpers import SyncNotConfirmedError
from src.shared.gym_stripe_service import GymStripeService
from src.shared.gym_timezone import gym_today
from src.shared.paying_member_lock import PayingMemberLock
from src.shared.sql_loader import load_sql
from src.sync.service.sync_service import PaymentSyncService
from src.tasks.service.tasks_queries import TasksQueries
from src.tasks.tasks_schema import TaskItemResponse

logger = logging.getLogger(__name__)


class MemberMembershipsRepriceExecutor(MemberMembershipsBase):
    """Executes one membership_reprice task item (registered handler)."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        paying_lock: PayingMemberLock,
    ) -> None:
        super().__init__(db_pool, payment_sync_service, gym_stripe_service)
        self._paying_lock = paying_lock
        self._tasks_queries = TasksQueries(db_pool)

    async def execute_item(self, item: TaskItemResponse) -> None:
        """Execute one claimed reprice item; raises on failure (retried).

        Raises:
            LockBusyError: The family is busy (retryable).
            ValueError: The item no longer validates (membership gone /
                cancelled, or the target price is no longer the plan's
                active price).
            SyncNotConfirmedError: The converge did not confirm on Stripe.
        """
        async with self._paying_lock.lock([item.member_id]):
            new_item_id = item.new_item_id
            if new_item_id is None:
                new_item_id = await self._run_db_phase(item)

            # ── Sync phase: idempotent/convergent, safe to re-run after any
            # crash. The defensive no-op (successor == old row: nothing
            # changed) syncs without proration so it can never bill.
            is_noop = new_item_id == item.old_item_id
            prorate = bool(item.prorate) and not is_noop
            await self._payment_sync.update_payments_recurring(
                item.member_id,
                idempotency_key=uuid4(),
                proration_behavior="always_invoice" if prorate else "none",
            )

            await self._verify(item, new_item_id)

    # ── Private ────────────────────────────────────────────────

    async def _run_db_phase(self, item: TaskItemResponse) -> UUID:
        """Re-validate, then write the reprice's desired state atomically.

        Returns the successor row's item_id (== the old row's when the
        membership turned out to already sit on the target price — the
        endpoint rejects that case, so it only arises from a race).
        """
        if item.old_item_id is None or item.target_price_id is None:
            raise ValueError(
                f"Reprice item missing parameters: "
                f"task_item_id={item.task_item_id}"
            )

        row = await self._get_membership(item.old_item_id, item.member_id)
        self._validate_reprice(row, item)

        if UUID(str(row["price_id"])) == item.target_price_id:
            # Raced to already-on-target (the endpoint rejects no-ops).
            # The old row IS the desired state; record it as the successor.
            async with self._db_pool.session() as session:
                await self._tasks_queries.set_item_new_membership(
                    session,
                    item.task_item_id,
                    item.old_item_id,
                )
                await session.commit()
            return item.old_item_id

        target_price = await self._get_target_price(row, item)

        # Prorating op: converge the family to a clean baseline first.
        await self._pre_sync_payments(item.member_id)

        today = gym_today(row["timezone"])
        async with self._db_pool.session() as session:
            # Order matters for the DB gates: the old row's cancellation must
            # be effective before the successor INSERT (no-active/overlap
            # triggers) and before the discount copies (single-LIVE custom
            # trigger). FK targets: successor before copies.
            await self._cancel_immediate(session, item, today)
            new_item_id = await self._insert_successor(
                session,
                row,
                item,
                target_price,
                today,
            )
            await self._copy_applied_discounts(session, item, new_item_id, today)
            await self._tasks_queries.set_item_new_membership(
                session,
                item.task_item_id,
                new_item_id,
            )
            await session.commit()

        logger.info(
            "Reprice DB phase done: old_item_id=%s -> new_item_id=%s "
            "(price %s -> %s)",
            item.old_item_id,
            new_item_id,
            row["price_id"],
            item.target_price_id,
        )
        return new_item_id

    def _validate_reprice(self, row: dict, item: TaskItemResponse) -> None:
        """The endpoint validated at request time; re-check under the lock."""
        if row["cancel_date"] is not None:
            raise ValueError(
                f"Cannot reprice cancelled membership: "
                f"item_id={item.old_item_id}, member_id={item.member_id}"
            )
        if (
            row["end_date"] is not None
            and row["end_date"] <= gym_today(row["timezone"])
        ):
            raise ValueError(
                f"Cannot reprice ended membership: "
                f"item_id={item.old_item_id}, member_id={item.member_id}"
            )

    async def _get_target_price(
        self,
        row: dict,
        item: TaskItemResponse,
    ) -> dict:
        """The target must still be the plan's active price.

        Raises:
            ValueError: If the plan's active price moved since the task was
                created (the staff re-submits against the new active price).
        """
        active_price = await self._get_active_price_for_plan(
            row["gym_id"],
            row["plan_id"],
        )
        if UUID(str(active_price["price_id"])) != item.target_price_id:
            raise ValueError(
                f"Target price is no longer the plan's active price: "
                f"target_price_id={item.target_price_id}, "
                f"active_price_id={active_price['price_id']}"
            )
        return active_price

    async def _cancel_immediate(
        self,
        session: AsyncSession,
        item: TaskItemResponse,
        today: date,
    ) -> None:
        sql = load_sql(SQL_DIR / "member_memberships_cancel_immediate.sql")
        await session.execute(
            text(sql),
            {
                "item_id": str(item.old_item_id),
                "member_id": str(item.member_id),
                "gym_today": today,
            },
        )

    async def _insert_successor(
        self,
        session: AsyncSession,
        row: dict,
        item: TaskItemResponse,
        target_price: dict,
        today: date,
    ) -> UUID:
        """Insert the successor row (pending add) on the shared session."""
        sql = load_sql(SQL_DIR / "member_memberships_insert.sql")
        result = await session.execute(
            text(sql),
            {
                "member_ids": [str(item.member_id)],
                "gym_ids": [str(row["gym_id"])],
                "plan_ids": [str(row["plan_id"])],
                "price_ids": [str(item.target_price_id)],
                "start_dates": [today],
                "end_dates": [None],
                "last_paid_dates": [today],
                "next_due_dates": [None],
                "stripe_item_ids": [None],
                "prorates": [bool(item.prorate)],
                "total_prices": [target_price["price"]],
                "sync_statuses": [StripeSyncStatus.not_added.value],
            },
        )
        return UUID(str(result.mappings().one()["item_id"]))

    async def _copy_applied_discounts(
        self,
        session: AsyncSession,
        item: TaskItemResponse,
        new_item_id: UUID,
        today: date,
    ) -> None:
        sql = load_sql(
            SQL_DIR / "applied_discounts" / "copy_applied_discounts.sql"
        )
        await session.execute(
            text(sql),
            {
                "old_item_id": str(item.old_item_id),
                "new_item_id": str(new_item_id),
                "gym_today": today,
            },
        )

    async def _verify(
        self,
        item: TaskItemResponse,
        new_item_id: UUID,
    ) -> None:
        """The converge must have landed: successor applied, old row deleted.

        Raises:
            SyncNotConfirmedError: If the writeback did not confirm. Nothing
                is reverted — the DB already encodes the desired state; the
                retry (or the reconciler's push sweep) converges it.
        """
        new_status = await self._get_sync_status(new_item_id, item.member_id)
        if new_status != StripeSyncStatus.applied:
            raise SyncNotConfirmedError(
                f"Reprice not confirmed: successor row not applied "
                f"(new_item_id={new_item_id}, status={new_status})"
            )
        if new_item_id == item.old_item_id:
            return  # defensive no-op: there is no separate old row
        old_status = await self._get_sync_status(
            item.old_item_id,
            item.member_id,
        )
        if old_status != StripeSyncStatus.deleted:
            raise SyncNotConfirmedError(
                f"Reprice not confirmed: old row not deleted "
                f"(old_item_id={item.old_item_id}, status={old_status})"
            )
