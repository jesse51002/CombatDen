"""The membership reprice operation (append-only, DB-first verify-or-revert).

A reprice never mutates the membership row — ``price_id`` and
``stripe_item_id`` are trigger-enforced immutable. ``reprice`` cancels the old
row effective today, inserts its successor at the target price, copies the
live applied discounts onto the successor (ONE transaction), then the EXISTING
payment sync converges Stripe and the writeback stamps the successor
``applied`` and the old row ``deleted``.

A standalone membership operation that knows NOTHING about how it is dispatched
(the per-plan batch task today, a direct CRM call tomorrow): plain parameters
in, the successor's item_id out, and it handles its own failure with the
standard ``sync_or_revert`` contract — an unconfirmed converge REVERTS the DB
phase and raises, leaving the membership exactly as it was. This module imports
nothing from ``src.tasks``.
"""

import logging
from datetime import date
from uuid import UUID, uuid4

from schema.member_membership import StripeSyncStatus
from schema.task import ProrationBehavior
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
    """Execute a reprice onto a target price (append-only, verify-or-revert)."""

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
        proration_behavior: ProrationBehavior,
        target_price_id: UUID | None = None,
    ) -> UUID:
        """Run one reprice (DB-first); returns the successor row's item_id.

        Takes the payer lock itself (the membership's ``paid_by_member_id``),
        converges synchronously, returns when done — a standalone op like
        ``cancel`` / ``start``. The single member-detail upgrade calls it
        directly (no task); the per-plan batch runs it per task item.

        ``target_price_id`` resolution:
        - **None** (the single, member-detail upgrade) → resolve the plan's
          current ``is_active`` price and reprice to it.
        - **given** (the batch pins the active price at batch-discovery time)
          → reprice to that exact price **as-is**, never re-checked against
          the plan's *current* active price. A newer price created before the
          item runs must NOT divert or fail the upgrade the user asked for (a
          deactivated CRM price keeps a usable Stripe price — `plans_price.py`
          never archives one).

        A membership already on the target is a no-op (returns its own
        item_id, no work, no bill).

        Raises:
            LockBusyError: The payer is busy.
            ValueError: The membership does not validate (not found,
                cancelled, ended), has no active price (None case), or the
                given target is not a price of its plan.
            SyncNotConfirmedError: The converge could not be confirmed on
                Stripe — the DB phase has been reverted, the membership is
                exactly as it was.
        """
        # ``paid_by_member_id`` is immutable, so resolving the payer before
        # locking is race-free — and the lock keys on the PAYER, not the
        # member: a child's membership paid by a parent must lock the parent's
        # subscription, the one this reprice converges.
        payer_id = await self._resolve_payer(old_item_id, member_id)
        async with self._paying_lock.lock([payer_id]):
            row = await self._get_membership(old_item_id, member_id)
            self._validate_reprice(row, old_item_id, member_id)

            if target_price_id is None:
                target_price = await self._get_active_price_for_plan(
                    row["gym_id"],
                    row["plan_id"],
                )
                target_price_id = UUID(str(target_price["price_id"]))
            else:
                target_price = await self._get_price_for_plan(
                    row["gym_id"],
                    row["plan_id"],
                    target_price_id,
                )

            if UUID(str(row["price_id"])) == target_price_id:
                # Already on the target — a no-op (a duplicate request, or
                # already repriced). Nothing to do and nothing to bill: the
                # reconciler's sweep converges any DB↔Stripe drift, so there
                # is no defensive re-sync here.
                return old_item_id

            # Prorating op: converge the payer to a clean baseline first.
            await self._pre_sync_payments(payer_id)

            new_item_id = await self._write_db_phase(
                row,
                member_id,
                old_item_id,
                target_price_id,
                target_price,
            )

            await sync_or_revert(
                sync_fn=lambda: self._payment_sync.update_payments_recurring(
                    payer_id,
                    idempotency_key=uuid4(),
                    proration_behavior=proration_behavior,
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

    # ── Private — validation / resolution ──────────────────────

    async def _resolve_payer(
        self,
        old_item_id: UUID,
        member_id: UUID,
    ) -> UUID:
        """The membership's payer (``paid_by_member_id``) — the lock/sync key.

        Read before locking: ``paid_by_member_id`` is immutable, so this is
        race-free and lets the reprice lock the PAYER's subscription rather
        than the member's own.
        """
        row = await self._get_membership(old_item_id, member_id)
        return UUID(str(row["paid_by_member_id"]))

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

    # ── Private — DB phase (write + revert) ────────────────────

    async def _write_db_phase(
        self,
        row: dict,
        member_id: UUID,
        old_item_id: UUID,
        target_price_id: UUID,
        target_price: dict,
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

    # ── Private — shared row writes (real + preview) ───────────

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
        today: date,
    ) -> UUID:
        """Insert the successor row (pending add) on the shared session."""
        sql = load_sql(SQL_DIR / "member_memberships_insert.sql")
        result = await session.execute(
            text(sql),
            {
                "member_ids": [str(member_id)],
                "paid_by_member_ids": [str(row["paid_by_member_id"])],
                "gym_ids": [str(row["gym_id"])],
                "plan_ids": [str(row["plan_id"])],
                "price_ids": [str(target_price_id)],
                "start_dates": [today],
                "end_dates": [None],
                "last_paid_dates": [today],
                "next_due_dates": [None],
                "stripe_item_ids": [None],
                "total_prices": [target_price["price"]],
                # Reprice is recurring-only, and a recurring membership is
                # always quantity 1 (enforced by trg_recurring_quantity_must_be_one),
                # so the successor carries that invariant. (member_memberships_insert.sql
                # gained the required `quantities` param with the class-pack feature.)
                "quantities": [1],
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
