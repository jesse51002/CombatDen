"""Freeze and unfreeze a member's account (account-level)."""

import logging
from datetime import date
from uuid import UUID

from dateutil.relativedelta import relativedelta
from sqlalchemy import text

from src.member_memberships import SQL_DIR
from src.member_memberships.service.memberships.member_memberships_base import (
    MemberMembershipsBase,
)
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MemberMembershipsFreeze(MemberMembershipsBase):
    """Freeze and unfreeze account-level billing."""

    async def freeze(
        self,
        crm_user_id: UUID,
        gym_id: UUID,
        freeze_months: int,
    ) -> None:
        """Freeze a member's account (account-level).

        Pauses Stripe subscription billing and sets freeze
        dates on the parent profile. If already frozen,
        idempotently updates the freeze end date.

        Args:
            crm_user_id: Any family member's profile ID.
            gym_id: The gym.
            freeze_months: Number of months to freeze.

        Raises:
            ValueError: If freeze_months is not positive.
        """
        if freeze_months <= 0:
            raise ValueError("freeze_months must be positive")

        parent = await self._payment_sync.resolve_parent(crm_user_id)
        freeze_end_date = date.today() + relativedelta(months=freeze_months)

        # ── Stripe first ──────────────────────────────────
        await self._payment_sync.update_payments_recurring(
            crm_user_id,
            add_ids=[],
            cancel_ids=[],
            freeze_end_date=freeze_end_date,
        )

        # ── CRM freeze ────────────────────────────────────
        await self._crm_freeze_profile(
            parent.crm_user_id,
            parent.gym_id,
            freeze_end_date,
        )

    async def unfreeze(
        self,
        crm_user_id: UUID,
        gym_id: UUID,
    ) -> None:
        """Unfreeze a member's account (account-level).

        Resumes Stripe subscription billing and clears freeze
        dates on the parent profile. If not frozen, calls sync
        with no changes for consistency, then returns.

        Args:
            crm_user_id: Any family member's profile ID.
            gym_id: The gym.
        """
        parent = await self._payment_sync.resolve_parent(crm_user_id)

        if not parent.is_frozen:
            await self._payment_sync.update_payments_recurring(
                crm_user_id,
                add_ids=[],
                cancel_ids=[],
            )
            return

        # ── Stripe first ──────────────────────────────────
        await self._payment_sync.update_payments_recurring(
            crm_user_id,
            add_ids=[],
            cancel_ids=[],
            unfreeze=True,
        )

        # ── CRM unfreeze ──────────────────────────────────
        await self._crm_unfreeze_profile(
            parent.crm_user_id,
            parent.gym_id,
        )

    # ── Private ────────────────────────────────────────────────

    async def _crm_freeze_profile(
        self,
        crm_user_id: UUID,
        gym_id: UUID,
        freeze_end_date: date,
    ) -> None:
        """Set freeze dates on the parent profile."""
        sql = load_sql(SQL_DIR / "member_memberships_freeze_profile.sql")
        params = {
            "crm_user_id": str(crm_user_id),
            "gym_id": str(gym_id),
            "freeze_end_date": freeze_end_date,
        }
        async with self._db_pool.session() as session:
            await session.execute(text(sql), params)
            await session.commit()

    async def _crm_unfreeze_profile(
        self,
        crm_user_id: UUID,
        gym_id: UUID,
    ) -> None:
        """Clear freeze dates on the parent profile."""
        sql = load_sql(SQL_DIR / "member_memberships_unfreeze_profile.sql")
        params = {
            "crm_user_id": str(crm_user_id),
            "gym_id": str(gym_id),
        }
        async with self._db_pool.session() as session:
            await session.execute(text(sql), params)
            await session.commit()
