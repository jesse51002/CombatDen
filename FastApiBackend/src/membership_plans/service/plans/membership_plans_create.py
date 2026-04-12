"""Create a membership plan: DB first, then Stripe, then set stripe IDs."""

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
from src.payments.payments_exceptions import StripeOrphanError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_membership_schema import (
    PaymentsMembershipCreateRequest,
    PaymentsMembershipPriceItem,
)
from src.shared.db_first_helpers import cleanup_pending_row
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MembershipPlansCreate(MembershipPlansBase):
    """Create a new membership plan using the DB-first pattern."""

    async def create_plan(
        self,
        request: MembershipPlanCreateRequest,
    ) -> MembershipPlanResponse:
        """Insert CRM rows, create Stripe Product+Price, then set stripe IDs.

        Args:
            request: Plan creation data including initial price.

        Returns:
            The created plan with its active price.

        Raises:
            ValueError: If the gym has no Stripe account.
            StripeOrphanError: If Stripe succeeds but the DB
                update fails after retries.
        """
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            request.gym_id,
        )

        # ── Step 1: DB insert (NULL stripe IDs) ──────────────────
        plan_row = await self._insert_plan(request)
        plan_id = str(plan_row["plan_id"])

        price_row = await self._insert_price(
            plan_id=plan_id,
            gym_id=str(request.gym_id),
            price=request.price,
        )
        price_id = str(price_row["price_id"])

        # ── Step 2: Stripe create ────────────────────────────────
        try:
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
                    metadata={
                        "crm_plan_id": plan_id,
                    },
                ),
                stripe_account_id,
            )
        except Exception:
            await self._cleanup_pending(plan_id, price_id, request)
            raise

        stripe_product_id = stripe_resp.stripe_product_id
        stripe_price_id = stripe_resp.prices[0].stripe_price_id

        # ── Step 3: Set stripe IDs ───────────────────────────────
        plan_sql = load_sql(
            SQL_DIR / "membership_plans_set_stripe_product_id.sql",
        )
        try:
            plan_row = await self._db_pool.execute_with_retry(
                plan_sql,
                {
                    "plan_id": plan_id,
                    "gym_id": str(request.gym_id),
                    "stripe_product_id": stripe_product_id,
                },
            )
        except Exception as exc:
            raise StripeOrphanError(
                stripe_resource_type=StripeResourceType.product,
                stripe_id=stripe_product_id,
                crm_pk=plan_id,
            ) from exc

        price_sql = load_sql(
            SQL_DIR / "membership_plans_price_set_stripe_price_id.sql",
        )
        try:
            price_row = await self._db_pool.execute_with_retry(
                price_sql,
                {
                    "price_id": price_id,
                    "plan_id": plan_id,
                    "stripe_price_id": stripe_price_id,
                },
            )
        except Exception as exc:
            raise StripeOrphanError(
                stripe_resource_type=StripeResourceType.price,
                stripe_id=stripe_price_id,
                crm_pk=price_id,
            ) from exc

        return self._build_plan_response(
            plan_row,
            active_price=self._build_price_response(price_row),
        )

    # ── Private ────────────────────────────────────────────────

    async def _insert_plan(
        self,
        request: MembershipPlanCreateRequest,
    ) -> dict:
        """Insert a plan row with NULL stripe_product_id."""
        sql = load_sql(SQL_DIR / "membership_plans_insert.sql")
        params = {
            "gym_id": str(request.gym_id),
            "plan_name": request.plan_name,
            "plan_type": request.plan_type.value,
            "class_count": request.class_count,
            "duration_amount": request.duration_amount,
            "duration_unit": (request.duration_unit.value if request.duration_unit else None),
            "is_public": request.is_public,
            "stripe_product_id": None,
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = dict(result.mappings().one())
            await session.commit()
        return row

    async def _insert_price(
        self,
        plan_id: str,
        gym_id: str,
        price: int,
    ) -> dict:
        """Insert a price row with NULL stripe_price_id."""
        sql = load_sql(SQL_DIR / "membership_plans_price_insert.sql")
        params = {
            "plan_id": plan_id,
            "gym_id": gym_id,
            "stripe_price_id": None,
            "price": price,
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = dict(result.mappings().one())
            await session.commit()
        return row

    async def _cleanup_pending(
        self,
        plan_id: str,
        price_id: str,
        request: MembershipPlanCreateRequest,
    ) -> None:
        """Delete pending plan and price rows after Stripe failure."""
        await cleanup_pending_row(
            delete_fn=lambda: self._delete_pending_price(price_id, plan_id),
            entity_name="membership_plan_price",
            crm_pk=price_id,
        )
        await cleanup_pending_row(
            delete_fn=lambda: self._delete_pending_plan(
                plan_id,
                str(request.gym_id),
            ),
            entity_name="membership_plan",
            crm_pk=plan_id,
        )

    async def _delete_pending_plan(
        self,
        plan_id: str,
        gym_id: str,
    ) -> None:
        """Hard-delete a pending plan row (NULL stripe_product_id)."""
        sql = load_sql(SQL_DIR / "membership_plans_delete_pending.sql")
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {"plan_id": plan_id, "gym_id": gym_id},
            )
            await session.commit()

    async def _delete_pending_price(
        self,
        price_id: str,
        plan_id: str,
    ) -> None:
        """Hard-delete a pending price row (NULL stripe_price_id)."""
        sql = load_sql(SQL_DIR / "membership_plans_price_delete_pending.sql")
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {"price_id": price_id, "plan_id": plan_id},
            )
            await session.commit()

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
