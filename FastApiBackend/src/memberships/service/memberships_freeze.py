"""Freeze and unfreeze a PAYER's billing (per-payer, DB-first)."""

from __future__ import annotations

import logging
from datetime import date
from typing import TYPE_CHECKING
from uuid import UUID

from dateutil.relativedelta import relativedelta
from sqlalchemy import text

from src.memberships import SQL_DIR
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.shared.db_first_helpers import sync_or_revert
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.shared.database import DirectDatabasePool
    from src.shared.gym_stripe_service import GymStripeService
    from src.shared.payer_resolver import PayerResolver
    from src.sync.service.sync_freeze import (
        PaymentSyncFreeze,
    )
    from src.sync.service.sync_service import (
        PaymentSyncService,
    )

logger = logging.getLogger(__name__)


class MemberMembershipsFreeze(MemberMembershipsBase):
    """Freeze and unfreeze a payer's billing (per-payer, DB-first).

    Freeze is per PAYER: the window is written to the target member's OWN
    profile FIRST, then their own subscription's ``pause_collection`` is
    converged via ``PaymentSyncFreeze`` (NOT ``update_payments_recurring`` —
    freeze is a subscription-level pause, not a membership-item change).
    Freezing one payer never touches another payer's subscription, even in
    the same linked family. If the Stripe converge fails, the DB freeze
    window is reverted so the DB stays in sync.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        payer_resolver: PayerResolver,
        freeze_service: PaymentSyncFreeze,
    ) -> None:
        super().__init__(
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._payer_resolver = payer_resolver
        self._freeze_service = freeze_service

    async def freeze(
        self,
        member_id: UUID,
        gym_id: UUID,
        freeze_months: int,
        idempotency_key: UUID,
    ) -> None:
        """Freeze a payer's billing, DB-first.

        Writes the freeze window to the member's OWN profile FIRST, then pauses
        their subscription's Stripe collection from that window. If the Stripe
        pause fails, the freeze window is reverted (unfrozen) so the DB stays in
        sync with Stripe. If already frozen, idempotently updates the freeze end
        date.

        Args:
            member_id: The payer whose billing to freeze (their own
                subscription; memberships they pay for follow it).
            gym_id: The gym.
            freeze_months: Number of months to freeze.
            idempotency_key: Caller-supplied key scoped to this freeze.

        Raises:
            ValueError: If freeze_months is not positive.
        """
        if freeze_months <= 0:
            raise ValueError("freeze_months must be positive")

        payer = await self._payer_resolver.resolve_payer(member_id)
        today = gym_today(payer.timezone)
        freeze_end_date = today + relativedelta(months=freeze_months)

        # ── DB-first: write the freeze window, THEN converge Stripe ──
        await self._crm_freeze_profile(
            payer.member_id,
            payer.gym_id,
            today,
            freeze_end_date,
        )

        # Re-resolve so the payer carries the freeze window the sync reads.
        payer, account = await self._payer_resolver.resolve_payer_with_account(
            payer.member_id,
        )

        # No membership-row status to verify (freeze is a sub-level pause) —
        # revert the DB freeze window on any failure.
        await sync_or_revert(
            sync_fn=lambda: self._freeze_service.sync_freeze_state(
                payer,
                account,
                idempotency_key=idempotency_key,
            ),
            revert_fn=lambda: self._crm_unfreeze_profile(
                payer.member_id,
                payer.gym_id,
            ),
            entity_name="member_freeze",
            crm_pk=str(payer.member_id),
        )

    async def unfreeze(
        self,
        member_id: UUID,
        gym_id: UUID,
        idempotency_key: UUID,
    ) -> None:
        """Unfreeze a payer's billing, DB-first.

        Clears the freeze window on the member's OWN profile FIRST, then resumes
        their subscription's Stripe collection. If the Stripe resume fails, the
        freeze window is restored so the DB stays in sync with Stripe. If not
        frozen, re-syncs the (no-op) freeze state defensively and returns.

        Args:
            member_id: The payer whose billing to unfreeze.
            gym_id: The gym.
            idempotency_key: Caller-supplied key scoped to this unfreeze.
        """
        payer, account = await self._payer_resolver.resolve_payer_with_account(
            member_id,
        )

        if not payer.is_frozen:
            # Already unfrozen — re-sync the (no-op) freeze state defensively.
            await self._freeze_service.sync_freeze_state(
                payer,
                account,
                idempotency_key=idempotency_key,
            )
            return

        old_freeze_start = payer.freeze_start_date
        old_freeze_end = payer.freeze_end_date

        # ── DB-first: clear the freeze window, THEN converge Stripe ──
        await self._crm_unfreeze_profile(payer.member_id, payer.gym_id)

        # Re-resolve so the payer reflects the cleared window.
        payer, account = await self._payer_resolver.resolve_payer_with_account(
            payer.member_id,
        )

        await sync_or_revert(
            sync_fn=lambda: self._freeze_service.sync_freeze_state(
                payer,
                account,
                idempotency_key=idempotency_key,
            ),
            revert_fn=lambda: self._crm_freeze_profile(
                payer.member_id,
                payer.gym_id,
                old_freeze_start,
                old_freeze_end,
            ),
            entity_name="member_freeze",
            crm_pk=str(payer.member_id),
        )

    # ── Private ────────────────────────────────────────────────

    async def _crm_freeze_profile(
        self,
        member_id: UUID,
        gym_id: UUID,
        freeze_start_date: date,
        freeze_end_date: date,
    ) -> None:
        """Set freeze dates on the payer's profile."""
        sql = load_sql(SQL_DIR / "member_memberships_freeze_profile.sql")
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
            "freeze_start_date": freeze_start_date,
            "freeze_end_date": freeze_end_date,
        }
        async with self._db_pool.session() as session:
            await session.execute(text(sql), params)
            await session.commit()

    async def _crm_unfreeze_profile(
        self,
        member_id: UUID,
        gym_id: UUID,
    ) -> None:
        """Clear freeze dates on the payer's profile."""
        sql = load_sql(SQL_DIR / "member_memberships_unfreeze_profile.sql")
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
        }
        async with self._db_pool.session() as session:
            await session.execute(text(sql), params)
            await session.commit()
