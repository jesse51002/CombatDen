"""Shared dependencies and helpers for discount operations."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import text

from src.discounts import SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.payments.service.payments_stripe_discount_service import (
        PaymentsStripeDiscountService,
    )
    from src.shared.gym_stripe_service import GymStripeService

logger = logging.getLogger(__name__)


class DiscountsBase:
    """Base class for discount sub-services.

    Holds shared dependencies and reusable query methods
    used across create, update, and delete operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        gym_stripe_service: GymStripeService,
        stripe_discount_service: PaymentsStripeDiscountService,
    ) -> None:
        self._db_pool = db_pool
        self._gym_stripe = gym_stripe_service
        self._stripe_discounts = stripe_discount_service

    # ── Shared Queries ─────────────────────────────────────────

    async def _get_discount(self, discount_id: UUID) -> dict:
        """Fetch a non-deleted discount row.

        Raises:
            ValueError: If the discount is not found.
        """
        sql = load_sql(SQL_DIR / "discounts_get_by_id.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"discount_id": str(discount_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Discount {discount_id} not found")
        return dict(row)
