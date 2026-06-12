"""Run ONE membership reprice (append-only, DB-first verify-or-revert).

A reprice never mutates the membership row — ``price_id`` and
``stripe_item_id`` are trigger-enforced immutable. One DB transaction cancels
the old row effective today, inserts its successor at the target price
(pending, NULL line id), and copies the live applied discounts onto the
successor. The EXISTING payment sync then converges Stripe — old consolidated
line decremented or removed, new line created or joined, prorated per the
request — and the existing writeback stamps the successor ``applied`` and the
old row ``deleted``.

A standalone operation like every other lifecycle op: it knows NOTHING about
how it is dispatched (a tracked task today, a direct CRM call tomorrow) —
plain parameters in, the successor's item_id out — and it handles its own
failure with the standard ``sync_or_revert`` contract: an unconfirmed
converge REVERTS the DB phase (discount copies → pending successor → the old
row's ``cancel_date``, still clearable pre-'deleted') and raises, leaving the
membership exactly as it was.
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
from src.shared.db_first_helpers import sync_or_revert
from src.shared.gym_stripe_service import GymStripeService
from src.shared.gym_timezone import gym_today
from src.shared.paying_member_lock import PayingMemberLock
from src.shared.sql_loader import load_sql
from src.sync.service.sync_service import PaymentSyncService

logger = logging.getLogger(__name__)


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
    ) -> UUID:
        """Run one reprice (DB-first); returns the successor row's item_id.

        Takes the family lock itself. A membership already sitting on the
        target price (a race; callers validate against it) gets a defensive
        billing-safe re-sync and returns its own item_id.

        Args:
            member_id: The member being repriced.
            old_item_id: The membership row being replaced.
            target_price_id: Must be the plan's currently active price.
            prorate: ``always_invoice`` vs ``none`` on the converge.

        Raises:
            LockBusyError: The family is busy.
            ValueError: The membership does not validate (not found,
                cancelled, ended, or the target is no longer the plan's
                active price).
            SyncNotConfirmedError: The converge could not be confirmed on
                Stripe — the DB phase has been reverted, the membership is
                exactly as it was.
        """
        async with self._paying_lock.lock([member_id]):
            row = await self._get_membership(old_item_id, member_id)
            self._validate_reprice(row, old_item_id, member_id)

            if UUID(str(row["price_id"])) == target_price_id:
                # Already on the target (callers reject no-ops; a race can
                # still land here). Nothing to write — re-sync defensively,
                # without proration so it can never bill.
                await self._payment_sync.update_payments_recurring(
                    member_id,
                    idempotency_key=uuid4(),
                    proration_behavior="none",
                )
                return old_item_id

            target_price = await self._get_target_price(
                row,
                old_item_id,
                target_price_id,
            )

            # Prorating op: converge the family to a clean baseline first.
            await self._pre_sync_payments(member_id)

            new_item_id = await self._write_db_phase(
                row,
                member_id,
                old_item_id,
                target_price_id,
                target_price,
                prorate,
            )

            await sync_or_revert(
                sync_fn=lambda: self._payment_sync.update_payments_recurring(
                    member_id,
                    idempotency_key=uuid4(),
                    proration_behavior=(
                        "always_invoice" if prorate else "none"
                    ),
                ),
                revert_fn=lambda: self._revert_db_phase(
                    member_id,
                    old_item_id,
                    new_item_id,
                ),
                entity_name="member_membership_reprice",
                crm_pk=str(old_item_id),
                verify_fn=lambda: self._verify(
                    member_id,
                    old_item_id,
                    new_item_id,
                ),
            )
            return new_item_id

    # ── Private ────────────────────────────────────────────────

    def _validate_reprice(
        self,
        row: dict,
        old_item_id: UUID,
        member_id: UUID,
    ) -> None:
        """Validate the membership can be repriced."""
        if row["cancel_date"] is not None:
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

    async def _write_db_phase(
        self,
        row: dict,
        member_id: UUID,
        old_item_id: UUID,
        target_price_id: UUID,
        target_price: dict,
        prorate: bool,
    ) -> UUID:
        """Write the reprice's desired state in ONE transaction.

        Order matters for the DB gates: the old row's cancellation must be
        effective before the successor INSERT (no-active/overlap triggers)
        and before the discount copies (single-LIVE custom trigger). FK
        targets: successor before copies.
        """
        today = gym_today(row["timezone"])
        async with self._db_pool.session() as session:
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
            await session.commit()

        logger.info(
            "Reprice DB phase written: old_item_id=%s -> new_item_id=%s "
            "(price %s -> %s)",
            old_item_id,
            new_item_id,
            row["price_id"],
            target_price_id,
        )
        return new_item_id

    async def _revert_db_phase(
        self,
        member_id: UUID,
        old_item_id: UUID,
        new_item_id: UUID,
    ) -> None:
        """Undo the reprice's DB phase after an unconfirmed converge.

        Reverse order of the write: discount copies → pending successor →
        clear the old row's ``cancel_date`` (allowed — the old row was never
        stamped 'deleted', which is exactly the unconfirmed case).

        Known-residual guard (same doctrine as the other DB-first reverts):
        if the writeback already stamped the successor's line id, the swap
        materially landed on Stripe — the successor row is permanent (its
        line id is immutable, a historical record) and un-cancelling the old
        row would resurrect a second live membership. The revert is skipped;
        the idempotent re-sync / reconciler finishes the converge.
        """
        new_status = await self._get_sync_status(new_item_id, member_id)
        if new_status == StripeSyncStatus.applied:
            logger.warning(
                "Reprice revert skipped — successor already on Stripe "
                "(new_item_id=%s); the re-sync/reconciler completes it",
                new_item_id,
            )
            return

        async with self._db_pool.session() as session:
            await self._delete_copied_discounts(session, new_item_id)
            await session.commit()
        await self._delete_pending([new_item_id])
        async with self._db_pool.session() as session:
            sql = load_sql(SQL_DIR / "member_memberships_uncancel.sql")
            await session.execute(
                text(sql),
                {
                    "item_id": str(old_item_id),
                    "member_id": str(member_id),
                },
            )
            await session.commit()

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

    async def _delete_copied_discounts(
        self,
        session: AsyncSession,
        new_item_id: UUID,
    ) -> None:
        sql = load_sql(
            SQL_DIR / "applied_discounts" / "delete_copied_discounts.sql"
        )
        await session.execute(text(sql), {"item_id": str(new_item_id)})

    async def _verify(
        self,
        member_id: UUID,
        old_item_id: UUID,
        new_item_id: UUID,
    ) -> bool:
        """The converge landed iff successor 'applied' AND old row 'deleted'."""
        new_status = await self._get_sync_status(new_item_id, member_id)
        if new_status != StripeSyncStatus.applied:
            return False
        old_status = await self._get_sync_status(old_item_id, member_id)
        return old_status == StripeSyncStatus.deleted
