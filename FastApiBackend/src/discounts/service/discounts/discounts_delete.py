"""Soft-delete a non-linked gym discount."""

from __future__ import annotations

import json
import logging
from typing import TYPE_CHECKING
from uuid import UUID

from fastapi import BackgroundTasks
from schema.gym_discount import DiscountType
from sqlalchemy import text

from src.discounts import SQL_DIR
from src.discounts.service.discounts.discounts_base import DiscountsBase
from src.payments.schema.payments_discount_schema import (
    PaymentsDiscountDeleteRequest,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.member_memberships.service.membership_payment_sync_service import (
        MembershipPaymentSyncService,
    )
    from src.payments.service.payments_stripe_discount_service import (
        PaymentsStripeDiscountService,
    )
    from src.shared.gym_stripe_service import GymStripeService

logger = logging.getLogger(__name__)


class DiscountsDelete(DiscountsBase):
    """Soft-delete a non-linked discount from CRM and Stripe."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        gym_stripe_service: GymStripeService,
        stripe_discount_service: PaymentsStripeDiscountService,
        membership_payment_sync_service: MembershipPaymentSyncService,
    ) -> None:
        super().__init__(db_pool, gym_stripe_service, stripe_discount_service)
        self._payment_sync = membership_payment_sync_service

    async def delete_discount(
        self,
        discount_id: UUID,
        gym_id: UUID,
        background_tasks: BackgroundTasks,
    ) -> None:
        """Soft-delete a non-linked discount.

        Deletes the Stripe coupon, removes the discount from all
        memberships, and queues payment sync as a background task.

        Args:
            discount_id: The discount to delete.
            gym_id: The gym owning the discount.
            background_tasks: FastAPI background tasks.

        Raises:
            ValueError: If discount not found, is linked, or
                gym has no Stripe account.
        """
        existing = await self._get_discount(discount_id)

        if existing["discount_type"] == DiscountType.linked:
            raise ValueError(
                "Cannot delete linked discounts via this endpoint",
            )

        if existing["stripe_coupon_id"]:
            try:
                stripe_account_id = await self._gym_stripe.get_stripe_account_id(
                    gym_id,
                )
                await self._stripe_discounts.delete_discount(
                    PaymentsDiscountDeleteRequest(
                        stripe_coupon_id=existing["stripe_coupon_id"],
                    ),
                    stripe_account_id,
                )
            except Exception:
                logger.warning(
                    "Failed to delete Stripe coupon %s (orphaned in Stripe)",
                    existing["stripe_coupon_id"],
                    exc_info=True,
                )

        soft_delete_sql = load_sql(SQL_DIR / "discounts_soft_delete.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(soft_delete_sql),
                {"discount_id": str(discount_id)},
            )
            row = result.mappings().fetchone()
            if not row:
                raise ValueError(f"Discount {discount_id} not found")
            await session.commit()

        affected = await self._remove_discount_from_memberships(
            discount_id,
        )
        if affected:
            background_tasks.add_task(
                self._payment_sync.bulk_payment_sync,
                affected,
            )

    # ── Private ────────────────────────────────────────────────

    async def _remove_discount_from_memberships(
        self,
        discount_id: UUID,
    ) -> list[UUID]:
        """Remove discount from all membership discount_ids arrays.

        Returns:
            List of affected crm_user_ids.
        """
        sql = load_sql(SQL_DIR / "discounts_remove_from_memberships.sql")
        discount_id_json = json.dumps([str(discount_id)])
        discount_id_text = f'"{discount_id}"'

        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "discount_id_json": discount_id_json,
                    "discount_id_text": discount_id_text,
                },
            )
            rows = result.mappings().fetchall()
            await session.commit()

        return [UUID(str(r["crm_user_id"])) for r in rows]
