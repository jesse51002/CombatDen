"""Shared dependencies and helpers for membership plan operations."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import text

from src.membership_plans import SQL_DIR
from src.membership_plans.membership_plans_schemas import (
    MembershipPlanPriceResponse,
    MembershipPlanResponse,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.payments.service.payments_stripe_membership_service import (
        PaymentsStripeMembershipService,
    )
    from src.payments.service.payments_stripe_price_service import (
        PaymentsStripePriceService,
    )
    from src.shared.gym_stripe_service import GymStripeService

logger = logging.getLogger(__name__)


class MembershipPlansBase:
    """Base class for membership plan sub-services.

    Holds shared dependencies and reusable query methods
    used across create, update, delete, read, and price operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        gym_stripe_service: GymStripeService,
        stripe_membership_service: PaymentsStripeMembershipService,
        stripe_price_service: PaymentsStripePriceService,
    ) -> None:
        self._db_pool = db_pool
        self._gym_stripe = gym_stripe_service
        self._stripe_memberships = stripe_membership_service
        self._stripe_prices = stripe_price_service

    # ── Shared Queries ─────────────────────────────────────────

    async def _get_plan(self, plan_id: UUID, gym_id: UUID) -> dict:
        """Fetch a non-deleted plan row (with active price columns).

        Raises:
            ValueError: If the plan is not found.
        """
        sql = load_sql(SQL_DIR / "membership_plans_get.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"plan_id": str(plan_id), "gym_id": str(gym_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Plan {plan_id} not found")
        return dict(row)

    # ── Row → Response Mappers ─────────────────────────────────

    @staticmethod
    def _build_price_response(row: dict) -> MembershipPlanPriceResponse:
        """Build a price response from a DB row."""
        return MembershipPlanPriceResponse(
            price_id=row["price_id"],
            plan_id=row["plan_id"],
            gym_id=row["gym_id"],
            stripe_price_id=row["stripe_price_id"],
            price=row["price"],
            is_active=row["is_active"],
            created_at=row["created_at"],
        )

    @staticmethod
    def _extract_active_price(
        plan_row: dict,
    ) -> MembershipPlanPriceResponse | None:
        """Extract the active price from a joined plan row."""
        if plan_row.get("price_price_id") is None:
            return None
        return MembershipPlanPriceResponse(
            price_id=plan_row["price_price_id"],
            plan_id=plan_row["plan_id"],
            gym_id=plan_row["gym_id"],
            stripe_price_id=plan_row["price_stripe_price_id"],
            price=plan_row["price_price"],
            is_active=plan_row["price_is_active"],
            created_at=plan_row["price_created_at"],
        )

    @staticmethod
    def _build_plan_response(
        plan_row: dict,
        active_price: MembershipPlanPriceResponse | None = None,
    ) -> MembershipPlanResponse:
        """Build a plan response from a DB row + optional price."""
        return MembershipPlanResponse(
            plan_id=plan_row["plan_id"],
            gym_id=plan_row["gym_id"],
            plan_name=plan_row["plan_name"],
            plan_type=plan_row["plan_type"],
            class_count=plan_row["class_count"],
            duration_amount=plan_row["duration_amount"],
            duration_unit=plan_row["duration_unit"],
            is_public=plan_row["is_public"],
            stripe_product_id=plan_row["stripe_product_id"],
            created_at=plan_row["created_at"],
            active_price=active_price,
        )
