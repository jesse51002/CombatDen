"""Service for managing member membership lifecycle."""

from __future__ import annotations

import logging
from datetime import date
from typing import TYPE_CHECKING
from uuid import UUID

from schema.membership_plan import PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships import SQL_DIR
from src.member_memberships.schema.payment_sync_schema import SyncItem
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.member_memberships.service.membership_payment_sync_service import (
        MembershipPaymentSyncService,
    )

logger = logging.getLogger(__name__)


class MemberMembershipsService:
    """Membership lifecycle operations.

    Orchestrates CRM state changes and Stripe sync for
    membership operations like cancel.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: MembershipPaymentSyncService,
    ) -> None:
        self._db_pool = db_pool
        self._payment_sync = payment_sync_service

    async def cancel(
        self,
        crm_user_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
    ) -> None:
        """Cancel a specific active recurring membership.

        Syncs the cancellation to Stripe first (including linked
        discount recalculation), then updates the CRM database.

        If the membership is already cancelled, this is a no-op.

        Args:
            crm_user_id: The member.
            gym_id: The gym.
            plan_id: The membership plan to cancel.

        Raises:
            ValueError: If the membership is not found, has already
                ended, or is non-recurring.
        """
        row = await self._get_membership(crm_user_id, gym_id, plan_id)

        if row["cancel_date"] is not None:
            return

        self._validate_cancel(row, crm_user_id, gym_id, plan_id)

        # ── Stripe sync (includes linked discount recalc) ──
        if row["stripe_price_id"]:
            cancel_item = SyncItem(
                stripe_price_id=row["stripe_price_id"],
                stripe_item_id=row["stripe_item_id"],
                crm_user_id=crm_user_id,
                plan_id=plan_id,
            )
            try:
                await self._payment_sync.update_payments_recurring(
                    crm_user_id,
                    add_ids=[],
                    cancel_ids=[cancel_item],
                )
            except PaymentsResourceNotFoundError:
                logger.warning(
                    "Stripe resource not found during cancel "
                    "(proceeding with CRM cancel): "
                    "crm_user_id=%s, gym_id=%s, plan_id=%s",
                    crm_user_id,
                    gym_id,
                    plan_id,
                )

        # ── CRM cancel ────────────────────────────────────
        await self._crm_cancel(crm_user_id, gym_id, plan_id)

    # ── Private Helpers ─────────────────────────────────────────

    async def _get_membership(
        self,
        crm_user_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
    ) -> dict:
        """Fetch membership row for validation and Stripe info."""
        get_sql = load_sql(SQL_DIR / "member_memberships_get.sql")
        params = {
            "crm_user_id": str(crm_user_id),
            "gym_id": str(gym_id),
            "plan_id": str(plan_id),
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(get_sql), params)
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(
                f"Membership not found: crm_user_id={crm_user_id}, "
                f"gym_id={gym_id}, plan_id={plan_id}"
            )
        return dict(row)

    @staticmethod
    def _validate_cancel(
        row: dict,
        crm_user_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
    ) -> None:
        """Validate a membership can be cancelled."""
        if row["plan_type"] != PlanType.recurring:
            raise ValueError(
                f"Cannot cancel non-recurring membership "
                f"(plan_type={row['plan_type']}): "
                f"crm_user_id={crm_user_id}, "
                f"gym_id={gym_id}, plan_id={plan_id}"
            )

        if row["end_date"] is not None and row["end_date"] <= date.today():
            logger.warning(
                f"Recurring membership has ended set. "
                f"Shouldn't be possible "
                f"(end_date={row['end_date']}): "
                f"crm_user_id={crm_user_id}, "
                f"gym_id={gym_id}, plan_id={plan_id}"
            )

    async def _crm_cancel(
        self,
        crm_user_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
    ) -> None:
        """Mark membership as cancelled in the CRM database."""
        cancel_sql = load_sql(SQL_DIR / "member_memberships_cancel.sql")
        params = {
            "crm_user_id": str(crm_user_id),
            "gym_id": str(gym_id),
            "plan_id": str(plan_id),
        }
        async with self._db_pool.session() as session:
            await session.execute(text(cancel_sql), params)
            await session.commit()
