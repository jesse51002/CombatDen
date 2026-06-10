"""Create a gym discount (plain config, no Stripe coupon).

Creating a discount is two inserts in one transaction: the IDENTITY row
(gym_discounts: name + type) and its first ACTIVE value version
(gym_discount_values: percent/dollar + lifetime). No coupon is pre-baked — the
sync computes each consolidated line's effective coupon at sync-time and writes
the resolved stripe_coupon_id back onto the applied-discount row. There is no
linked branch (linked/family discounts are per-plan pricing, not a discount).

DiscountsService never touches applied-discount rows — it owns only
``gym_discounts`` / ``gym_discount_values``. ``mint_custom_discounts`` returns
plain discount ids that the memberships side applies exactly like presets.
"""

from __future__ import annotations

import logging
from uuid import UUID

from schema.gym_discount import DiscountType
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.discounts import SQL_DIR
from src.discounts.schema.discounts_schema import (
    DiscountCreateRequest,
    DiscountResponse,
    DiscountValue,
)
from src.discounts.service.discounts_base import DiscountsBase
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class DiscountsCreate(DiscountsBase):
    """Create a regular-only, coupon-free gym discount + its first version."""

    async def create_discount(
        self,
        request: DiscountCreateRequest,
    ) -> DiscountResponse:
        """Insert the identity row + first active value version, return both.

        Args:
            request: Discount creation data (identity + value/lifetime).

        Returns:
            The created discount (identity merged with its active value).
        """
        async with self._db_pool.session() as session:
            identity = await self._insert_identity(session, request)
            value = await self._insert_value(session, request, identity)
            await session.commit()
        return DiscountResponse.from_row({**identity, **value})

    async def mint_custom_discounts(
        self,
        gym_id: UUID,
        values: list[DiscountValue],
    ) -> list[UUID]:
        """Mint each inline custom value as a ``custom`` discount; return ids.

        The one home for the ``DiscountValue`` → discount conversion
        (auto-generated name + ``custom`` type). Callers fold the minted ids
        into the apply list and delete the minted discounts on revert.
        """
        minted: list[UUID] = []
        for value in values:
            response = await self.create_discount(
                DiscountCreateRequest(
                    gym_id=gym_id,
                    discount_name=self._custom_name(value),
                    discount_type=DiscountType.custom,
                    value=value,
                )
            )
            minted.append(response.discount_id)
        return minted

    # ── Private ────────────────────────────────────────────────

    @staticmethod
    def _custom_name(value: DiscountValue) -> str:
        """Auto-generate a display name for an inline custom value."""
        if value.percentage_off is not None:
            return f"Custom {value.percentage_off}% off"
        return f"Custom ${value.dollar_off / 100:.2f} off"

    @staticmethod
    async def _insert_identity(
        session: AsyncSession,
        request: DiscountCreateRequest,
    ) -> dict:
        """Insert the gym_discounts identity row."""
        sql = load_sql(SQL_DIR / "discounts_insert.sql")
        params = {
            "gym_id": str(request.gym_id),
            "discount_name": request.discount_name,
            "discount_type": request.discount_type.value,
        }
        result = await session.execute(text(sql), params)
        return dict(result.mappings().one())

    @staticmethod
    async def _insert_value(
        session: AsyncSession,
        request: DiscountCreateRequest,
        identity: dict,
    ) -> dict:
        """Insert the first active gym_discount_values version."""
        value = request.value
        sql = load_sql(SQL_DIR / "discount_values_insert.sql")
        params = {
            "discount_id": str(identity["discount_id"]),
            "gym_id": str(identity["gym_id"]),
            "percentage_off": value.percentage_off,
            "dollar_off": value.dollar_off,
            "discount_mode": value.discount_mode.value,
            "duration_amount": value.duration_amount,
            "duration_unit": (
                value.duration_unit.value if value.duration_unit is not None else None
            ),
            "end_date": value.end_date,
        }
        result = await session.execute(text(sql), params)
        return dict(result.mappings().one())
