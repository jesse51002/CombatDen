"""Discount preset CRUD operations (facade).

Delegates to focused sub-services while preserving the public API. Presets are
plain, coupon-free gym config: no Stripe coupon, no payment-sync cascade on
create/update/delete. Coupons are computed at sync-time and written back onto
the applied-discount snapshot.
"""

from __future__ import annotations

from uuid import UUID

from src.discounts.schema.discounts_schema import (
    DiscountCreateRequest,
    DiscountResponse,
    DiscountUpdateRequest,
    DiscountValue,
)
from src.discounts.service.discounts.discounts_create import DiscountsCreate
from src.discounts.service.discounts.discounts_delete import DiscountsDelete
from src.discounts.service.discounts.discounts_list import DiscountsList
from src.discounts.service.discounts.discounts_update import DiscountsUpdate
from src.shared.database import DirectDatabasePool


class DiscountsService:
    """Discount preset CRUD operations (facade).

    Delegates to focused sub-services for create, update, archive,
    and list operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
    ) -> None:
        self._create = DiscountsCreate(db_pool)
        self._update = DiscountsUpdate(db_pool)
        self._delete = DiscountsDelete(db_pool)
        self._list = DiscountsList(db_pool)

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
        """Create a coupon-free discount preset."""
        return await self._create.create_discount(request)

    async def mint_custom_discounts(
        self,
        gym_id: UUID,
        values: list[DiscountValue],
    ) -> list[UUID]:
        """Mint inline custom values as ``custom`` discounts; return their ids."""
        return await self._create.mint_custom_discounts(gym_id, values)

    # ── Update ─────────────────────────────────────────────────

    async def update_discount(
        self,
        request: DiscountUpdateRequest,
    ) -> DiscountResponse:
        """Edit a preset's intent and lifetime spec."""
        return await self._update.update_discount(request)

    # ── Delete ─────────────────────────────────────────────────

    async def delete_discount(
        self,
        discount_id: UUID,
    ) -> None:
        """Archive a preset (soft-delete)."""
        await self._delete.delete_discount(discount_id)
