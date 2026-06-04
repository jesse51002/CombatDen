"""Create a gym discount: DB first, then Stripe, then set stripe coupon ID."""

from __future__ import annotations

import logging

from sqlalchemy import text

from src.discounts import SQL_DIR
from src.discounts.schema.discounts_schema import (
    DiscountCreateRequest,
    DiscountResponse,
)
from src.discounts.service.discounts.discounts_base import DiscountsBase
from src.payments.payments_exceptions import StripeOrphanError
from src.payments.schema.metadata.stripe_coupon_metadata import (
    StripeCouponMetadata,
)
from src.payments.schema.payments_discount_schema import (
    PaymentsDiscountCreateRequest,
)
from src.payments.schema.payments_enums import StripeResourceType
from src.shared.db_first_helpers import cleanup_pending_row
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class DiscountsCreate(DiscountsBase):
    """Create a new gym discount using the DB-first pattern."""

    async def create_discount(
        self,
        request: DiscountCreateRequest,
    ) -> DiscountResponse:
        """Insert CRM row, create Stripe coupon, then set stripe_coupon_id.

        Args:
            request: Discount creation data.

        Returns:
            The created discount.

        Raises:
            ValueError: If the gym has no Stripe account.
            StripeOrphanError: If Stripe succeeds but the DB
                update fails after retries.
        """
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            request.gym_id,
        )

        # ── Step 1: DB insert (NULL stripe_coupon_id) ────────────
        row = await self._insert_discount(request)
        discount_id = str(row["discount_id"])

        # ── Step 2: Stripe create ────────────────────────────────
        try:
            stripe_resp = await self._stripe_discounts.create_discount(
                PaymentsDiscountCreateRequest(
                    discount_name=request.discount_name,
                    percentage_off=request.percentage_off,
                    amount_off=request.dollar_off,
                    currency="usd",
                    duration=request.duration,
                    duration_in_months=request.duration_in_months,
                    metadata=StripeCouponMetadata(
                        crm_discount_id=row["discount_id"],
                        gym_id=request.gym_id,
                    ),
                ),
                stripe_account_id,
            )
        except Exception:
            await cleanup_pending_row(
                delete_fn=lambda: self._delete_pending(discount_id),
                entity_name="gym_discount",
                crm_pk=discount_id,
            )
            raise

        # ── Step 3: Set stripe_coupon_id ─────────────────────────
        set_coupon_sql = load_sql(
            SQL_DIR / "discounts_set_stripe_coupon_id.sql",
        )
        try:
            row = await self._db_pool.execute_with_retry(
                set_coupon_sql,
                {
                    "discount_id": discount_id,
                    "stripe_coupon_id": stripe_resp.stripe_coupon_id,
                },
            )
        except Exception as exc:
            raise StripeOrphanError(
                stripe_resource_type=StripeResourceType.coupon,
                stripe_id=stripe_resp.stripe_coupon_id,
                crm_pk=discount_id,
            ) from exc

        return DiscountResponse(**row)

    # ── Private ────────────────────────────────────────────────

    async def _insert_discount(
        self,
        request: DiscountCreateRequest,
    ) -> dict:
        """Insert a discount row with NULL stripe_coupon_id."""
        sql = load_sql(SQL_DIR / "discounts_insert.sql")
        params = {
            "gym_id": str(request.gym_id),
            "discount_name": request.discount_name,
            "discount_type": request.discount_type.value,
            "percentage_off": request.percentage_off,
            "dollar_off": request.dollar_off,
            "membership_plan_id": (
                str(request.membership_plan_id) if request.membership_plan_id else None
            ),
            "linked_discount_num": request.linked_discount_num,
            "duration": request.duration.value,
            "duration_in_months": request.duration_in_months,
            "stripe_coupon_id": None,
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = dict(result.mappings().one())
            await session.commit()
        return row

    async def _delete_pending(self, discount_id: str) -> None:
        """Hard-delete a pending discount row (NULL stripe_coupon_id)."""
        sql = load_sql(SQL_DIR / "discounts_delete_pending.sql")
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {"discount_id": discount_id},
            )
            await session.commit()
