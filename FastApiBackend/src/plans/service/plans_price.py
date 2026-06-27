"""Price management for membership plans."""

from __future__ import annotations

import logging

from schema.membership_plan import DurationUnit, PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.payments.payments_exceptions import StripeOrphanError
from src.payments.schema.metadata.stripe_price_metadata import (
    StripePriceMetadata,
)
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_price_schema import (
    PaymentsPriceCreateRequest,
)
from src.plans import SQL_DIR
from src.plans.plans_schema import (
    MembershipPlanPriceRequest,
    MembershipPlanPriceResponse,
)
from src.plans.service.plans_base import (
    MembershipPlansBase,
)
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MembershipPlansPrice(MembershipPlansBase):
    """Set / update plan prices."""

    # ── Set Price ──────────────────────────────────────────────

    async def set_price(
        self,
        request: MembershipPlanPriceRequest,
    ) -> MembershipPlanPriceResponse:
        """Insert CRM price row, create Stripe Price, then set stripe ID."""
        plan = await self._get_plan(request.plan_id, request.gym_id)

        stripe_product_id = plan.get("stripe_product_id")
        if not stripe_product_id:
            raise ValueError(
                f"Plan {request.plan_id} has no Stripe product",
            )

        plan_type = PlanType(plan["plan_type"])
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            request.gym_id,
        )

        recurring_interval, recurring_interval_count = self._resolve_interval(
            plan,
        )

        lock_sql = load_sql(
            SQL_DIR / "membership_plans_lock.sql",
        )
        deactivate_all_sql = load_sql(
            SQL_DIR / "membership_plans_price_deactivate_all.sql",
        )
        insert_sql = load_sql(
            SQL_DIR / "membership_plans_price_insert.sql",
        )
        set_price_sql = load_sql(
            SQL_DIR / "membership_plans_price_set_stripe_price_id.sql",
        )

        # Lock the plan row FOR UPDATE first, then deactivate-old + insert-new +
        # Stripe create + set-id run in ONE txn. The per-plan lock serializes
        # concurrent set_price on the same plan (a second caller blocks until the
        # first commits), so two callers never both create a Stripe price and
        # strand the loser's — the prior race where the <=1-active-price index
        # rejected the loser's commit AFTER its Stripe price already existed.
        # The txn still rolls back the deactivation on a Stripe failure (never
        # zero active prices); do NOT move the Stripe call out of it — deactivate
        # + insert must stay atomic for that index. StripeOrphanError remains the
        # backstop for a set-id failure after the price is created. Cost: a pooled
        # conn held across the Stripe call (fine for this rare admin op; the lock
        # also bounds same-plan connection-hold contention to one in-flight call).
        async with self._db_pool.session() as session:
            await session.execute(
                text(lock_sql),
                {
                    "plan_id": str(request.plan_id),
                    "gym_id": str(request.gym_id),
                },
            )

            deact_result = await session.execute(
                text(deactivate_all_sql),
                {
                    "plan_id": str(request.plan_id),
                    "gym_id": str(request.gym_id),
                },
            )
            old_price_row = deact_result.mappings().fetchone()
            old_price = dict(old_price_row) if old_price_row else None

            insert_result = await session.execute(
                text(insert_sql),
                {
                    "plan_id": str(request.plan_id),
                    "gym_id": str(request.gym_id),
                    "stripe_price_id": None,
                    "price": request.price,
                },
            )
            new_price_row = dict(insert_result.mappings().one())
            price_id = str(new_price_row["price_id"])

            stripe_resp = await self._stripe_prices.create_price(
                PaymentsPriceCreateRequest(
                    stripe_product_id=stripe_product_id,
                    unit_amount=request.price,
                    plan_type=plan_type,
                    recurring_interval=recurring_interval,
                    recurring_interval_count=recurring_interval_count,
                    metadata=StripePriceMetadata(
                        crm_price_id=new_price_row["price_id"],
                        plan_id=request.plan_id,
                        gym_id=request.gym_id,
                    ),
                ),
                stripe_account_id,
            )

            # DB failure here means Stripe has the price but we don't — surface as orphan.
            try:
                set_result = await session.execute(
                    text(set_price_sql),
                    {
                        "price_id": price_id,
                        "plan_id": str(request.plan_id),
                        "stripe_price_id": stripe_resp.stripe_price_id,
                    },
                )
                new_price_row = dict(set_result.mappings().one())
                await session.commit()
            except Exception as exc:
                raise StripeOrphanError(
                    stripe_resource_type=StripeResourceType.price,
                    stripe_id=stripe_resp.stripe_price_id,
                    crm_pk=price_id,
                ) from exc

        # Point the product at the new default price. Never archive old Stripe
        # prices — the DB is the gate; migrations may still reference the old one.
        if old_price and old_price.get("stripe_price_id"):
            try:
                await self._stripe_prices.set_product_default_price(
                    stripe_product_id=stripe_product_id,
                    stripe_price_id=stripe_resp.stripe_price_id,
                    stripe_account_id=stripe_account_id,
                )
            except Exception:
                logger.warning(
                    "Failed to set product %s default price to %s",
                    stripe_product_id,
                    stripe_resp.stripe_price_id,
                    exc_info=True,
                )

        return self._build_price_response(new_price_row)

    # ── Private ────────────────────────────────────────────────

    @staticmethod
    def _resolve_interval(plan: dict) -> tuple[DurationUnit, int]:
        """Determine the Stripe recurring interval from a plan row."""
        plan_type = PlanType(plan["plan_type"])
        if plan_type == PlanType.recurring:
            return DurationUnit.month, 1

        if plan.get("duration_unit") and plan.get("duration_amount"):
            return (
                DurationUnit(plan["duration_unit"]),
                plan["duration_amount"],
            )

        return DurationUnit.month, 1
