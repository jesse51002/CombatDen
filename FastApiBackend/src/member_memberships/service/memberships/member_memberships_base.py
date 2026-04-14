"""Shared dependencies and helpers for membership operations."""

from __future__ import annotations

import logging
from datetime import UTC, date, datetime
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import text

from src.member_memberships import SQL_DIR
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionResponse,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.member_memberships.service.membership_payment_sync_service import (
        MembershipPaymentSyncService,
    )
    from src.member_memberships.service.payment_sync.price_writeback import (
        PriceWriteback,
    )
    from src.shared.gym_stripe_service import GymStripeService

logger = logging.getLogger(__name__)


class MemberMembershipsBase:
    """Base class for membership sub-services.

    Holds shared dependencies and reusable query/helper
    methods used across cancel, freeze, start, and
    update_price operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: MembershipPaymentSyncService,
        price_writeback: PriceWriteback,
        gym_stripe_service: GymStripeService,
    ) -> None:
        self._db_pool = db_pool
        self._payment_sync = payment_sync_service
        self._price_writeback = price_writeback
        self._gym_stripe = gym_stripe_service

    # ── Shared Queries ─────────────────────────────────────────

    async def _get_membership(
        self,
        item_id: UUID,
        crm_user_id: UUID,
    ) -> dict:
        """Fetch membership row for validation and Stripe info.

        Raises:
            ValueError: If the membership is not found.
        """
        get_sql = load_sql(SQL_DIR / "member_memberships_get.sql")
        params = {
            "item_id": str(item_id),
            "crm_user_id": str(crm_user_id),
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(get_sql), params)
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Membership not found: item_id={item_id}, crm_user_id={crm_user_id}")
        return dict(row)

    # ── Static Helpers ─────────────────────────────────────────

    @staticmethod
    def _extract_stripe_item_id(
        response: PaymentsSubscriptionResponse,
        stripe_price_id: str,
    ) -> str | None:
        """Find the stripe_item_id matching a price in the response."""
        for item in response.items:
            if item.stripe_price_id == stripe_price_id:
                return item.stripe_subscription_item_id
        return None

    @staticmethod
    def _period_end_to_date(
        current_period_end: int | None,
    ) -> date | None:
        """Convert a Stripe Unix timestamp to a date."""
        if current_period_end is None:
            return None
        return datetime.fromtimestamp(
            current_period_end,
            tz=UTC,
        ).date()
