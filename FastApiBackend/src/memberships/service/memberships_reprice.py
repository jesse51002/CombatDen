"""Run ONE membership reprice (append-only) — task-agnostic.

A reprice never mutates the membership row — ``price_id`` and
``stripe_item_id`` are trigger-enforced immutable. One DB transaction cancels
the old row effective today, inserts its successor at the target price
(pending, NULL line id), and copies the live applied discounts onto the
successor. The EXISTING payment sync then converges Stripe — old consolidated
line decremented or removed, new line created or joined, prorated per the
request — and the existing writeback stamps the successor ``applied`` and the
old row ``deleted``.

This service knows NOTHING about how it is dispatched: plain parameters in,
the successor's item_id out, plus an optional generic in-transaction hook so
a caller can persist the old→new linkage atomically with the reprice's own
writes. It is idempotent/resumable on its own: a re-run that finds the old
row already cancelled with a live successor at the target price skips
straight to the convergent sync. No revert on failure — the transaction IS
the desired state; re-running converges it.
"""

import logging
from collections.abc import Awaitable, Callable
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

logger = logging.getLogger(__name__)

# Optional caller hook, executed INSIDE the reprice's DB transaction with the
# successor's item_id — for persisting linkage atomically with the reprice's
# own writes. The reprice neither knows nor cares what the hook does.
RecordSuccessor = Callable[[AsyncSession, UUID], Awaitable[None]]


class MemberMembershipsReprice(MemberMembershipsBase):
    """Execute one reprice onto a target price (no dispatch knowledge)."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        paying_lock: PayingMemberLock,
    ) -> None:
        super().__init__(db_pool, payment_sync_service, gym_stripe_service)
        self._paying_lock = paying_lock

    async def reprice(
        self,
        member_id: UUID,
        old_item_id: UUID,
        target_price_id: UUID,
        prorate: bool,
        record_successor: RecordSuccessor | None = None,
    ) -> UUID:
        """Run one reprice; returns the successor row's item_id.

        Takes the family lock itself. Idempotent: a re-run after a crash or
        failed converge resumes — old row already cancelled + live successor
        at the target price found → skip to the sync. A membership already
        sitting on the target price (a race; callers validate against it)
        gets a defensive billing-safe re-sync and returns its own item_id.

        Args:
            member_id: The member being repriced.
            old_item_id: The membership row being replaced.
            target_price_id: Must be the plan's currently active price.
            prorate: ``always_invoice`` vs ``none`` on the converge.
            record_successor: Optional hook run inside the reprice's DB
                transaction with (session, successor item_id).

        Raises:
            LockBusyError: The family is busy (retry later).
            ValueError: The membership no longer validates (gone, cancelled
                with no successor, ended, or the target is no longer the
                plan's active price).
            SyncNotConfirmedError: The converge did not confirm on Stripe.
                Nothing is reverted — re-running converges the same desired
                state.
        """
        async with self._paying_lock.lock([member_id]):
            new_item_id = await self._ensure_desired_state(
                member_id,
                old_item_id,
                target_price_id,
                prorate,
                record_successor,
            )

            # ── Sync phase: idempotent/convergent, safe to re-run. The
            # defensive no-op (successor == old row: nothing changed) syncs
            # without proration so it can never bill.
            is_noop = new_item_id == old_item_id
            do_prorate = prorate and not is_noop
            await self._payment_sync.update_payments_recurring(
                member_id,
                idempotency_key=uuid4(),
                proration_behavior=(
                    "always_invoice" if do_prorate else "none"
                ),
            )

            await self._verify(member_id, old_item_id, new_item_id)
            return new_item_id

    # ── Private ────────────────────────────────────────────────

    async def _ensure_desired_state(
        self,
        member_id: UUID,
        old_item_id: UUID,
        target_price_id: UUID,
        prorate: bool,
        record_successor: RecordSuccessor | None,
    ) -> UUID:
        """Make the DB encode the reprice; returns the successor item_id.

        Either writes it (cancel old + insert successor + copy discounts,
        one transaction) or recognizes it is already written (resume) /
        already true (no-op).
        """
        row = await self._get_membership(old_item_id, member_id)

        if row["cancel_date"] is not None:
            successor = await self._find_successor(
                member_id,
                row,
                target_price_id,
            )
            if successor is not None:
                # Resume: a prior run's DB phase already wrote the desired
                # state; only the converge is left.
                return successor
            raise ValueError(
                f"Cannot reprice cancelled membership: "
                f"item_id={old_item_id}, member_id={member_id}"
            )
        if (
            row["end_date"] is not None
            and row["end_date"] <= gym_today(row["timezone"])
        ):
            raise ValueError(
                f"Cannot reprice ended membership: "
                f"item_id={old_item_id}, member_id={member_id}"
            )

        if UUID(str(row["price_id"])) == target_price_id:
            # Already on the target (a race; callers reject no-ops). The
            # old row IS the desired state — record it as its own successor.
            if record_successor is not None:
                async with self._db_pool.session() as session:
                    await record_successor(session, old_item_id)
                    await session.commit()
            return old_item_id

        target_price = await self._get_target_price(
            row,
            old_item_id,
            target_price_id,
        )

        # Prorating op: converge the family to a clean baseline first.
        await self._pre_sync_payments(member_id)

        today = gym_today(row["timezone"])
        async with self._db_pool.session() as session:
            # Order matters for the DB gates: the old row's cancellation must
            # be effective before the successor INSERT (no-active/overlap
            # triggers) and before the discount copies (single-LIVE custom
            # trigger). FK targets: successor before copies.
            await self._cancel_immediate(
                session,
                old_item_id,
                member_id,
                today,
            )
            new_item_id = await self._insert_successor(
                session,
                row,
                member_id,
                target_price_id,
                target_price,
                prorate,
                today,
            )
            await self._copy_applied_discounts(
                session,
                old_item_id,
                new_item_id,
                today,
            )
            if record_successor is not None:
                await record_successor(session, new_item_id)
            await session.commit()

        logger.info(
            "Reprice DB phase done: old_item_id=%s -> new_item_id=%s "
            "(price %s -> %s)",
            old_item_id,
            new_item_id,
            row["price_id"],
            target_price_id,
        )
        return new_item_id

    async def _find_successor(
        self,
        member_id: UUID,
        row: dict,
        target_price_id: UUID,
    ) -> UUID | None:
        """The member's live row on the target price (resume detection)."""
        sql = load_sql(SQL_DIR / "member_memberships_find_successor.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "member_id": str(member_id),
                    "gym_id": str(row["gym_id"]),
                    "plan_id": str(row["plan_id"]),
                    "target_price_id": str(target_price_id),
                },
            )
            found = result.fetchone()
        return UUID(str(found[0])) if found else None

    async def _get_target_price(
        self,
        row: dict,
        old_item_id: UUID,
        target_price_id: UUID,
    ) -> dict:
        """The target must still be the plan's active price.

        Raises:
            ValueError: If the plan's active price moved since the reprice
                was requested (the caller re-requests against the new one).
        """
        active_price = await self._get_active_price_for_plan(
            row["gym_id"],
            row["plan_id"],
        )
        if UUID(str(active_price["price_id"])) != target_price_id:
            raise ValueError(
                f"Target price is no longer the plan's active price: "
                f"target_price_id={target_price_id}, "
                f"active_price_id={active_price['price_id']}, "
                f"item_id={old_item_id}"
            )
        return active_price

    async def _cancel_immediate(
        self,
        session: AsyncSession,
        old_item_id: UUID,
        member_id: UUID,
        today: date,
    ) -> None:
        sql = load_sql(SQL_DIR / "member_memberships_cancel_immediate.sql")
        await session.execute(
            text(sql),
            {
                "item_id": str(old_item_id),
                "member_id": str(member_id),
                "gym_today": today,
            },
        )

    async def _insert_successor(
        self,
        session: AsyncSession,
        row: dict,
        member_id: UUID,
        target_price_id: UUID,
        target_price: dict,
        prorate: bool,
        today: date,
    ) -> UUID:
        """Insert the successor row (pending add) on the shared session."""
        sql = load_sql(SQL_DIR / "member_memberships_insert.sql")
        result = await session.execute(
            text(sql),
            {
                "member_ids": [str(member_id)],
                "gym_ids": [str(row["gym_id"])],
                "plan_ids": [str(row["plan_id"])],
                "price_ids": [str(target_price_id)],
                "start_dates": [today],
                "end_dates": [None],
                "last_paid_dates": [today],
                "next_due_dates": [None],
                "stripe_item_ids": [None],
                "prorates": [prorate],
                "total_prices": [target_price["price"]],
                "sync_statuses": [StripeSyncStatus.not_added.value],
            },
        )
        return UUID(str(result.mappings().one()["item_id"]))

    async def _copy_applied_discounts(
        self,
        session: AsyncSession,
        old_item_id: UUID,
        new_item_id: UUID,
        today: date,
    ) -> None:
        sql = load_sql(
            SQL_DIR / "applied_discounts" / "copy_applied_discounts.sql"
        )
        await session.execute(
            text(sql),
            {
                "old_item_id": str(old_item_id),
                "new_item_id": str(new_item_id),
                "gym_today": today,
                "sync_status": StripeSyncStatus.not_added.value,
            },
        )

    async def _verify(
        self,
        member_id: UUID,
        old_item_id: UUID,
        new_item_id: UUID,
    ) -> None:
        """The converge must have landed: successor applied, old row deleted.

        Raises:
            SyncNotConfirmedError: If the writeback did not confirm. Nothing
                is reverted — the DB already encodes the desired state; a
                re-run (or the reconciler's push sweep) converges it.
        """
        new_status = await self._get_sync_status(new_item_id, member_id)
        if new_status != StripeSyncStatus.applied:
            raise SyncNotConfirmedError(
                f"Reprice not confirmed: successor row not applied "
                f"(new_item_id={new_item_id}, status={new_status})"
            )
        if new_item_id == old_item_id:
            return  # defensive no-op: there is no separate old row
        old_status = await self._get_sync_status(old_item_id, member_id)
        if old_status != StripeSyncStatus.deleted:
            raise SyncNotConfirmedError(
                f"Reprice not confirmed: old row not deleted "
                f"(old_item_id={old_item_id}, status={old_status})"
            )
