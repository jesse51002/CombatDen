"""Service for managing gym discounts (CRM + Stripe)."""

from __future__ import annotations

import json
import logging
from typing import TYPE_CHECKING
from uuid import UUID

if TYPE_CHECKING:
    from src.shared.stripe_reconciliation.stripe_reconciliation_service import (
        StripeReconciliationService,
    )

from fastapi import BackgroundTasks
from schema.gym_discount import DiscountType
from schema.immutable_columns import GYM_DISCOUNTS
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.discounts import SQL_DIR
from src.discounts.schema.discounts_schema import (
    DiscountCreateRequest,
    DiscountResponse,
    DiscountUpdateData,
    DiscountUpdateRequest,
)
from src.member_memberships.service.membership_payment_sync_service import (
    MembershipPaymentSyncService,
)
from src.payments.schema.payments_discount_schema import (
    PaymentsDiscountCreateRequest,
)
from src.payments.schema.payments_enums import StripeCouponDuration
from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
)
from src.shared.column_guard import validate_mutable_columns
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

VALUE_FIELDS = frozenset(
    {
        "percentage_off",
        "dollar_off",
        "duration",
        "duration_in_months",
    }
)


class DiscountsService:
    """Orchestrates discount CRUD across CRM database and Stripe.

    Creates/updates/deletes gym_discounts rows and their
    corresponding Stripe coupons. Cascades changes to
    memberships that reference the discount.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        gym_stripe_service: GymStripeService,
        stripe_discount_service: PaymentsStripeDiscountService,
        membership_payment_sync_service: MembershipPaymentSyncService,
    ) -> None:
        self._db_pool = db_pool
        self._gym_stripe = gym_stripe_service
        self._stripe_discounts = stripe_discount_service
        self._payment_sync = membership_payment_sync_service

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

    @staticmethod
    def _collect_changes(data: DiscountUpdateData) -> dict[str, object]:
        """Extract non-None mutable fields from the update data."""
        changes: dict[str, object] = {}
        for field in DiscountUpdateData.model_fields:
            value = getattr(data, field)
            if value is not None:
                changes[field] = value
        return changes

    @staticmethod
    def _validate_merged_state(merged: dict) -> None:
        """Validate the merged discount state after applying changes.

        Raises:
            ValueError: If the merged state violates constraints.
        """
        has_pct = merged.get("percentage_off") is not None
        has_amt = merged.get("dollar_off") is not None
        if has_pct == has_amt:
            raise ValueError(
                "Exactly one of percentage_off or dollar_off must be set",
            )

        duration = merged.get("duration")
        if duration == StripeCouponDuration.repeating.value:
            if merged.get("duration_in_months") is None:
                raise ValueError(
                    "duration_in_months is required when duration is 'repeating'",
                )
        elif merged.get("duration_in_months") is not None:
            raise ValueError(
                "duration_in_months must be None when duration is not 'repeating'",
            )

    async def _get_affected_crm_user_ids(
        self,
        discount_id: UUID,
    ) -> list[UUID]:
        """Find all crm_user_ids whose memberships use this discount."""
        sql = load_sql(SQL_DIR / "discounts_get_affected_memberships.sql")
        discount_id_json = json.dumps([str(discount_id)])

        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"discount_id_json": discount_id_json},
            )
            rows = result.mappings().fetchall()

        return [UUID(str(r["crm_user_id"])) for r in rows]

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

    # ── create ───────────────────────────────────────────────────

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

    # ── update ───────────────────────────────────────────────────

    async def update_discount(
        self,
        request: DiscountUpdateRequest,
        background_tasks: BackgroundTasks,
        reconciliation_service: StripeReconciliationService,
    ) -> DiscountResponse:
        """Update a non-linked discount in the CRM database and Stripe.

        Only provided (non-None) fields are updated. If value fields
        changed, creates a new Stripe coupon and deletes the old one.
        Queues membership payment sync as a background task.

        Args:
            request: Discount update data (partial).
            background_tasks: FastAPI background tasks.

        Returns:
            The updated discount.

        Raises:
            ValueError: If discount not found, is linked, no
                fields provided, or merged state is invalid.
        """
        existing = await self._get_discount(request.discount_id)

        if existing["discount_type"] == DiscountType.linked:
            raise ValueError(
                "Cannot update linked discounts via this endpoint",
            )

        changes = self._collect_changes(request.data)
        if not changes:
            return DiscountResponse(**existing)

        validate_mutable_columns(GYM_DISCOUNTS, set(changes.keys()))

        merged = {**existing, **changes}
        self._validate_merged_state(merged)

        values_changed = bool(changes.keys() & VALUE_FIELDS)

        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            request.gym_id,
        )

        stripe_resp = await self._stripe_discounts.create_discount(
            PaymentsDiscountCreateRequest(
                discount_name=merged["discount_name"],
                percentage_off=merged["percentage_off"],
                amount_off=merged["dollar_off"],
                currency="usd",
                duration=StripeCouponDuration(merged["duration"]),
                duration_in_months=merged["duration_in_months"],
            ),
            stripe_account_id,
        )
        changes["stripe_coupon_id"] = stripe_resp.stripe_coupon_id

        if existing["stripe_coupon_id"]:
            try:
                await self._stripe_discounts.delete_discount(
                    existing["stripe_coupon_id"],
                    stripe_account_id,
                )
            except Exception:
                logger.warning(
                    "Failed to delete old Stripe coupon %s (orphaned in Stripe)",
                    existing["stripe_coupon_id"],
                    exc_info=True,
                )

        update_sql = load_sql(SQL_DIR / "discounts_update.sql")
        params = {
            "discount_id": str(request.discount_id),
            "discount_name": merged["discount_name"],
            "percentage_off": merged["percentage_off"],
            "dollar_off": merged["dollar_off"],
            "duration": str(merged["duration"]),
            "duration_in_months": merged["duration_in_months"],
            "stripe_coupon_id": stripe_resp.stripe_coupon_id,
        }

        async with self._db_pool.session() as session:
            result = await session.execute(text(update_sql), params)
            row = result.mappings().fetchone()
            if not row:
                raise ValueError(
                    f"Discount {request.discount_id} not found",
                )
            await session.commit()

        if values_changed:
            affected = await self._get_affected_crm_user_ids(
                request.discount_id,
            )
            if affected:
                background_tasks.add_task(
                    self._payment_sync.bulk_payment_sync,
                    affected,
                    reconciliation_service,
                )

        return DiscountResponse(**row)

    # ── delete ───────────────────────────────────────────────────

    async def delete_discount(
        self,
        discount_id: UUID,
        gym_id: UUID,
        background_tasks: BackgroundTasks,
        reconciliation_service: StripeReconciliationService,
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
                    existing["stripe_coupon_id"],
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
                reconciliation_service,
            )
