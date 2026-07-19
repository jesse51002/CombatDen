"""Shared dependencies and helpers for membership plan operations."""

from __future__ import annotations

import json
import logging
from typing import TYPE_CHECKING
from uuid import UUID

from schema.gym_waiver import WaiverType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.plans import SQL_DIR
from src.plans.plans_schema import (
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

    async def _validate_waiver_ids(
        self,
        gym_id: UUID,
        waiver_ids: list[UUID],
    ) -> None:
        """Validate a plan's requested required-waiver ids at write time.

        ``waiver_ids`` is JSONB with no FK, so this is the integrity check:
        every id must exist in the gym, be non-archived, and be a ``custom``
        waiver — special-purpose waivers (e.g. the payer-auth agreement) are
        never plan-attachable.

        Raises:
            ValueError: Naming the offending waiver(s) (→ 400).
        """
        if not waiver_ids:
            return

        requested = {str(w) for w in waiver_ids}
        sql = load_sql(SQL_DIR / "membership_plans_waiver_ids_validate.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "gym_id": str(gym_id),
                    "waiver_ids": json.dumps(sorted(requested)),
                },
            )
            rows = [dict(r) for r in result.mappings().all()]

        missing = requested - {str(r["waiver_id"]) for r in rows}
        if missing:
            raise ValueError(
                "Waiver(s) not found for this gym: "
                + ", ".join(sorted(missing))
            )
        archived = sorted(r["name"] for r in rows if r["is_deleted"])
        if archived:
            raise ValueError(
                "Archived waiver(s) cannot be required by a plan: "
                + ", ".join(archived)
            )
        non_custom = sorted(
            r["name"]
            for r in rows
            if r["waiver_type"] != WaiverType.custom
        )
        if non_custom:
            raise ValueError(
                "Special-purpose waiver(s) cannot be required by a plan: "
                + ", ".join(non_custom)
            )

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
    def _json_list(value: object) -> list:
        """Parse a jsonb column into a list, tolerating str or list.

        asyncpg may hand a jsonb column back as a JSON string or as an
        already-parsed list depending on codec setup; handle both.
        """
        if value is None:
            return []
        if isinstance(value, str):
            return json.loads(value)
        return list(value)  # type: ignore[arg-type]

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
            image_url=plan_row["image_url"],
            plan_type=plan_row["plan_type"],
            class_count=plan_row["class_count"],
            duration_amount=plan_row["duration_amount"],
            duration_unit=plan_row["duration_unit"],
            is_public=plan_row["is_public"],
            stripe_product_id=plan_row["stripe_product_id"],
            created_at=plan_row["created_at"],
            active_price=active_price,
            enrolled_count=plan_row.get("enrolled_count", 0),
            waiver_ids=MembershipPlansBase._json_list(plan_row.get("waiver_ids")),
        )
