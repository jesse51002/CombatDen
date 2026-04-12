"""Create a gym discount in CRM and Stripe."""

from __future__ import annotations

import logging

from sqlalchemy import text

from src.discounts import SQL_DIR
from src.discounts.schema.discounts_schema import (
    DiscountCreateRequest,
    DiscountResponse,
)
from src.discounts.service.discounts.discounts_base import DiscountsBase
from src.payments.schema.payments_discount_schema import (
    PaymentsDiscountCreateRequest,
)
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class DiscountsCreate(DiscountsBase):
    """Create a new gym discount in CRM and Stripe."""

    async def create_discount(
        self,
        request: DiscountCreateRequest,
    ) -> DiscountResponse:
        """Create a discount in the CRM database and Stripe.

        Args:
            request: Discount creation data.

        Returns:
            The created discount.

        Raises:
            ValueError: If the gym has no Stripe account.
        """
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            request.gym_id,
        )

        stripe_resp = await self._stripe_discounts.create_discount(
            PaymentsDiscountCreateRequest(
                discount_name=request.discount_name,
                percentage_off=request.percentage_off,
                amount_off=request.dollar_off,
                currency="usd",
                duration=request.duration,
                duration_in_months=request.duration_in_months,
            ),
            stripe_account_id,
        )

        insert_sql = load_sql(SQL_DIR / "discounts_insert.sql")
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
            "stripe_coupon_id": stripe_resp.stripe_coupon_id,
        }

        async with self._db_pool.session() as session:
            result = await session.execute(text(insert_sql), params)
            row = result.mappings().one()
            await session.commit()

        return DiscountResponse(**row)
