"""Create a membership plan in CRM and Stripe."""

from __future__ import annotations

import logging

from schema.membership_plan import DurationUnit, PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.membership_plans import SQL_DIR
from src.membership_plans.membership_plans_schemas import (
    MembershipPlanCreateRequest,
    MembershipPlanResponse,
)
from src.membership_plans.service.plans.membership_plans_base import (
    MembershipPlansBase,
)
from src.payments.schema.payments_membership_schema import (
    PaymentsMembershipCreateRequest,
    PaymentsMembershipPriceItem,
)
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MembershipPlansCreate(MembershipPlansBase):
    """Create a new membership plan in CRM and Stripe."""

    async def create_plan(
        self,
        request: MembershipPlanCreateRequest,
    ) -> MembershipPlanResponse:
        """Create a Stripe Product+Price then insert into CRM.

        Args:
            request: Plan creation data including initial price.

        Returns:
            The created plan with its active price.

        Raises:
            ValueError: If the gym has no Stripe account.
        """
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            request.gym_id,
        )

        # ── Stripe first ──────────────────────────────────────
        recurring_interval, recurring_interval_count = self._resolve_price_interval(request)

        stripe_resp = await self._stripe_memberships.create_membership(
            PaymentsMembershipCreateRequest(
                plan_name=request.plan_name,
                prices=[
                    PaymentsMembershipPriceItem(
                        unit_amount=request.price,
                        plan_type=request.plan_type,
                        recurring_interval=recurring_interval,
                        recurring_interval_count=recurring_interval_count,
                        is_default=True,
                    ),
                ],
            ),
            stripe_account_id,
        )

        stripe_product_id = stripe_resp.stripe_product_id
        stripe_price_id = stripe_resp.prices[0].stripe_price_id

        # ── CRM insert plan ──────────────────────────────────
        insert_plan_sql = load_sql(
            SQL_DIR / "membership_plans_insert.sql",
        )
        plan_params = {
            "gym_id": str(request.gym_id),
            "plan_name": request.plan_name,
            "plan_type": request.plan_type.value,
            "class_count": request.class_count,
            "duration_amount": request.duration_amount,
            "duration_unit": (request.duration_unit.value if request.duration_unit else None),
            "is_public": request.is_public,
            "stripe_product_id": stripe_product_id,
        }

        async with self._db_pool.session() as session:
            result = await session.execute(
                text(insert_plan_sql),
                plan_params,
            )
            plan_row = dict(result.mappings().one())
            await session.commit()

        # ── CRM insert price ─────────────────────────────────
        insert_price_sql = load_sql(
            SQL_DIR / "membership_plans_price_insert.sql",
        )
        price_params = {
            "plan_id": str(plan_row["plan_id"]),
            "gym_id": str(request.gym_id),
            "stripe_price_id": stripe_price_id,
            "price": request.price,
        }

        async with self._db_pool.session() as session:
            result = await session.execute(
                text(insert_price_sql),
                price_params,
            )
            price_row = dict(result.mappings().one())
            await session.commit()

        return self._build_plan_response(
            plan_row,
            active_price=self._build_price_response(price_row),
        )

    # ── Private ────────────────────────────────────────────────

    @staticmethod
    def _resolve_price_interval(
        request: MembershipPlanCreateRequest,
    ) -> tuple[DurationUnit, int]:
        """Determine the Stripe recurring interval for a plan.

        Recurring plans are always month/1. Non-recurring plans
        use their duration fields if set, otherwise default to
        month/1 (Stripe requires interval even for one-time prices
        but it's ignored).
        """
        if request.plan_type == PlanType.recurring:
            return DurationUnit.month, 1

        if request.duration_unit and request.duration_amount:
            return request.duration_unit, request.duration_amount

        return DurationUnit.month, 1
