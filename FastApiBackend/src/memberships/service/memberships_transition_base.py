"""Shared machinery for ops that replace a membership with a successor row.

Two membership operations follow the **same shape**: cancel the old row
effective today, insert a successor row (pending add), copy the live applied
discounts onto the successor (ONE transaction), then the EXISTING payment sync
converges Stripe and the writeback stamps the successor ``applied`` and the old
row ``deleted``:

- **reprice** (``MemberMembershipsReprice``) — same plan, a newer price version.
- **upgrade** (``MemberMembershipsUpgrade``) — a *different* plan's active price
  (cross-plan), charging the prorated difference.

The only thing that differs between them is *which plan/price the successor
lands on* and the *validation* in front of it; the cancel-old + insert-successor
+ copy-discounts + verify-or-revert machinery is identical, so it lives here on a
focused intermediate class instead of swelling ``MemberMembershipsBase`` (already
the largest service file) or being duplicated across the two ops.

Both ops take the payer family lock **themselves** (they are standalone,
synchronous calls — the facade delegates them without its own lock), so the
``paying_lock`` dependency and the shared ``__init__`` live here too. This module
imports nothing from ``src.tasks``.
"""

import logging
from datetime import date
from uuid import UUID

from schema.member_membership import StripeSyncStatus
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService
from src.shared.gym_timezone import gym_today
from src.shared.paying_member_lock import PayingMemberLock
from src.shared.sql_loader import load_sql
from src.sync.service.sync_service import PaymentSyncService

logger = logging.getLogger(__name__)


class MemberMembershipsTransitionBase(MemberMembershipsBase):
    """Cancel-old + insert-successor + verify-or-revert, shared by two ops."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        paying_lock: PayingMemberLock,
    ) -> None:
        super().__init__(db_pool, payment_sync_service, gym_stripe_service)
        self._paying_lock = paying_lock

    # ── Payer resolution (lock/sync key) ───────────────────────

    async def _resolve_payer(
        self,
        old_item_id: UUID,
        member_id: UUID,
    ) -> UUID:
        """The membership's payer (``paid_by_member_id``) — the lock/sync key.

        Read before locking: ``paid_by_member_id`` is immutable, so this is
        race-free and lets the op lock the PAYER's subscription rather than the
        member's own (a child's membership paid by a parent must lock the
        parent's subscription, the one this op converges).
        """
        row = await self._get_membership(old_item_id, member_id)
        return UUID(str(row["paid_by_member_id"]))

    # ── DB phase (write + revert) ──────────────────────────────

    async def _write_db_phase(
        self,
        row: dict,
        member_id: UUID,
        old_item_id: UUID,
        target_plan_id: UUID,
        target_price_id: UUID,
        target_price: dict,
    ) -> UUID:
        """Write the desired state in ONE transaction; returns successor id.

        Order matters for the DB gates: the old row's cancellation must be
        effective before the successor INSERT (no-active/overlap triggers) and
        before the discount copies (single-LIVE custom trigger). FK targets:
        successor before copies. ``target_plan_id`` is the plan the successor
        lands on — the **same** plan for a reprice, a **different** plan for a
        cross-plan upgrade.
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
                target_plan_id,
                target_price_id,
                target_price,
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
            "Transition DB phase written: old_item_id=%s -> new_item_id=%s "
            "(plan %s -> %s, price %s -> %s)",
            old_item_id,
            new_item_id,
            row["plan_id"],
            target_plan_id,
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
        """Undo the DB phase after an unconfirmed converge.

        Reverse order of the write: discount copies → pending successor → clear
        the old row's ``cancel_date`` (allowed — the old row was never stamped
        'deleted', which is exactly the unconfirmed case).

        Known-residual guard (same doctrine as the other DB-first reverts): if
        the writeback already stamped the successor's line id, the swap
        materially landed on Stripe — the successor row is permanent (its line
        id is immutable, a historical record) and un-cancelling the old row
        would resurrect a second live membership. The revert is skipped; the
        idempotent re-sync / reconciler finishes the converge.
        """
        new_status = await self._get_sync_status(new_item_id, member_id)
        if new_status == StripeSyncStatus.applied:
            logger.warning(
                "Transition revert skipped — successor already on Stripe "
                "(new_item_id=%s); the re-sync/reconciler completes it",
                new_item_id,
            )
            return

        # All three writes share ONE transaction so the revert is
        # all-or-nothing (matching ``_write_db_phase``); a crash mid-revert
        # must never leave a half-reverted membership (a stranded ``not_added``
        # successor, or the old row still cancelled). ``_delete_pending`` lives
        # in ``MemberMembershipsBase`` and opens its own session, so its single
        # delete is replicated inline here on the shared session (same SQL file)
        # to keep it inside this transaction.
        async with self._db_pool.session() as session:
            await self._delete_copied_discounts(session, new_item_id)
            delete_pending_sql = load_sql(
                SQL_DIR / "member_memberships_delete_pending.sql"
            )
            await session.execute(
                text(delete_pending_sql),
                {"item_ids": [str(new_item_id)]},
            )
            uncancel_sql = load_sql(
                SQL_DIR / "member_memberships_uncancel.sql"
            )
            await session.execute(
                text(uncancel_sql),
                {
                    "item_id": str(old_item_id),
                    "member_id": str(member_id),
                },
            )
            await session.commit()

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

    # ── Shared row writes (real + preview) ─────────────────────

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
        target_plan_id: UUID,
        target_price_id: UUID,
        target_price: dict,
        today: date,
        sync_status: StripeSyncStatus = StripeSyncStatus.not_added,
    ) -> UUID:
        """Insert the successor row on the shared session; returns its item_id.

        ``target_plan_id`` is threaded explicitly (not read off ``row``) so the
        successor can land on a different plan for a cross-plan upgrade; a
        reprice passes the old row's own ``plan_id``. ``sync_status`` is
        ``not_added`` for a real op and ``preview_add`` when a preview stages a
        hypothetical successor (which the preview read includes and the real
        read excludes).
        """
        sql = load_sql(SQL_DIR / "member_memberships_insert.sql")
        result = await session.execute(
            text(sql),
            {
                "member_ids": [str(member_id)],
                "paid_by_member_ids": [str(row["paid_by_member_id"])],
                "gym_ids": [str(row["gym_id"])],
                "plan_ids": [str(target_plan_id)],
                "price_ids": [str(target_price_id)],
                "start_dates": [today],
                "end_dates": [None],
                "last_paid_dates": [today],
                "next_due_dates": [None],
                "stripe_item_ids": [None],
                "total_prices": [target_price["price"]],
                # Preserve the source row's quantity (recurring is always 1 per
                # trg_recurring_quantity_must_be_one). Required by the shared
                # insert SQL since PR #32 added the quantity column.
                "quantities": [row["quantity"]],
                "sync_statuses": [sync_status.value],
            },
        )
        return UUID(str(result.mappings().one()["item_id"]))

    async def _copy_applied_discounts(
        self,
        session: AsyncSession,
        old_item_id: UUID,
        new_item_id: UUID,
        today: date,
        sync_status: StripeSyncStatus = StripeSyncStatus.not_added,
    ) -> None:
        """Copy the old row's live applied discounts onto the successor.

        ``sync_status`` is ``not_added`` for a real op and ``preview_add`` when
        a preview stages them onto a hypothetical successor.
        """
        sql = load_sql(
            SQL_DIR / "applied_discounts" / "copy_applied_discounts.sql"
        )
        await session.execute(
            text(sql),
            {
                "old_item_id": str(old_item_id),
                "new_item_id": str(new_item_id),
                "gym_today": today,
                "sync_status": sync_status.value,
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
