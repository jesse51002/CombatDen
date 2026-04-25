"""Discount CRUD operations (facade).

Delegates to focused sub-services while preserving
the public API and constructor signature.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import BackgroundTasks

from src.discounts.schema.discounts_schema import (
    DiscountCreateRequest,
    DiscountResponse,
    DiscountUpdateRequest,
)
from src.discounts.service.discounts.discounts_create import DiscountsCreate
from src.discounts.service.discounts.discounts_delete import DiscountsDelete
from src.discounts.service.discounts.discounts_list import DiscountsList
from src.discounts.service.discounts.discounts_update import DiscountsUpdate
from src.member_memberships.service.membership_payment_sync_service import (
    MembershipPaymentSyncService,
)
from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService


class DiscountsService:
    """Discount CRUD operations (facade).

    Delegates to focused sub-services for create, update,
    and delete operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        gym_stripe_service: GymStripeService,
        stripe_discount_service: PaymentsStripeDiscountService,
        membership_payment_sync_service: MembershipPaymentSyncService,
    ) -> None:
        deps = (db_pool, gym_stripe_service, stripe_discount_service)
        self._create = DiscountsCreate(*deps)
        self._update = DiscountsUpdate(
            *deps,
            membership_payment_sync_service=membership_payment_sync_service,
        )
        self._delete = DiscountsDelete(
            *deps,
            membership_payment_sync_service=membership_payment_sync_service,
        )
        self._list = DiscountsList(*deps)

    # ── List ───────────────────────────────────────────────────

    async def list_discounts(
        self,
        gym_id: UUID,
    ) -> list[DiscountResponse]:
        """List preset discounts for a gym."""
        return await self._list.list_discounts(gym_id)

    # ── Create ─────────────────────────────────────────────────

    async def create_discount(
        self,
        request: DiscountCreateRequest,
    ) -> DiscountResponse:
        """Create a discount in the CRM database and Stripe."""
        return await self._create.create_discount(request)

    # ── Update ─────────────────────────────────────────────────

    async def update_discount(
        self,
        request: DiscountUpdateRequest,
        background_tasks: BackgroundTasks,
    ) -> DiscountResponse:
        """Update a non-linked discount in CRM and Stripe."""
        return await self._update.update_discount(
            request,
            background_tasks,
        )

    # ── Delete ─────────────────────────────────────────────────

    async def delete_discount(
        self,
        discount_id: UUID,
        gym_id: UUID,
        background_tasks: BackgroundTasks,
    ) -> None:
        """Soft-delete a non-linked discount."""
        await self._delete.delete_discount(
            discount_id,
            gym_id,
            background_tasks,
        )
