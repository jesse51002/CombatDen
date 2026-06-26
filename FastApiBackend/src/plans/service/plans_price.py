"""Price management for membership plans."""

from __future__ import annotations

import logging
from uuid import UUID

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
        """Insert CRM price row, create Stripe Price, then set stripe ID.

        Existing members keep their old price. Use migrate endpoints
        to move them to the new price.

        Args:
            request: Plan ID, gym ID, and new price in cents.

        Returns:
            The newly created price.

        Raises:
            ValueError: If the plan is not found or has no Stripe product.
            StripeOrphanError: If Stripe succeeds but the DB
                update fails after retries.
        """
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

        deactivate_all_sql = load_sql(
            SQL_DIR / "membership_plans_price_deactivate_all.sql",
        )
        insert_sql = load_sql(
            SQL_DIR / "membership_plans_price_insert.sql",
        )
        set_price_sql = load_sql(
            SQL_DIR / "membership_plans_price_set_stripe_price_id.sql",
        )

        # Deactivate the old price, insert the new one, and create the Stripe
        # Price all inside ONE transaction that is not committed until the
        # Stripe Price is confirmed. Creating the Stripe Price *before* the
        # commit means a Stripe failure rolls the whole transaction back —
        # re-activating the old price — so the plan is never left with zero
        # active prices, and the old price is never *durably* deactivated until
        # its replacement is confirmed on Stripe.
        async with self._db_pool.session() as session:
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

            # Create & verify the Stripe Price while the deactivation is still
            # uncommitted. On failure the transaction rolls back (old price
            # restored) and the original error propagates — no orphan price and
            # no zero-active-price window.
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

            # The Stripe Price now exists; a DB failure past here is a true
            # orphan, so surface it as StripeOrphanError. The rollback keeps the
            # old price active in the DB, consistent with Stripe holding the new
            # (unrecorded) price.
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

        # ── Stripe: point the product at the new price; keep the old ACTIVE ─
        # We never archive a Stripe price. A gym can update a price while a
        # subscription migration onto it is mid-flight, and archiving the old
        # price would break that migration. The DB
        # (``membership_plan_prices.is_active``) is the single gate for which
        # price is current; every Stripe price stays active forever.
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

    async def _deactivate_old_price(
        self,
        plan_id: UUID,
        gym_id: UUID,
        exclude_price_id: UUID,
    ) -> dict | None:
        """Deactivate old active price rows, excluding the new one.

        Returns:
            The deactivated price row, or None if there was none.
        """
        deactivate_sql = load_sql(
            SQL_DIR / "membership_plans_price_deactivate.sql",
        )
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(deactivate_sql),
                {
                    "plan_id": str(plan_id),
                    "gym_id": str(gym_id),
                    "exclude_price_id": str(exclude_price_id),
                },
            )
            row = result.mappings().fetchone()
            await session.commit()

        return dict(row) if row else None

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
