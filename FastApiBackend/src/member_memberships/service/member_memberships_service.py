"""Membership lifecycle operations (facade).

Delegates to focused sub-services while preserving
the public API and constructor signature.
"""

from __future__ import annotations

from datetime import date
from typing import TYPE_CHECKING
from uuid import UUID

from src.member_memberships.service.memberships.member_memberships_cancel import (
    MemberMembershipsCancel,
)
from src.member_memberships.service.memberships.member_memberships_freeze import (
    MemberMembershipsFreeze,
)
from src.member_memberships.service.memberships.member_memberships_start import (
    MemberMembershipsStart,
)
from src.member_memberships.service.memberships.member_memberships_update_price import (
    MemberMembershipsUpdatePrice,
)
from src.shared.database import DirectDatabasePool

if TYPE_CHECKING:
    from src.member_memberships.service.membership_payment_sync_service import (
        MembershipPaymentSyncService,
    )
    from src.payments.service.payments_stripe_payment_service import (
        PaymentsStripePaymentService,
    )
    from src.shared.gym_stripe_service import GymStripeService


class MemberMembershipsService:
    """Membership lifecycle operations (facade).

    Delegates to focused sub-services for cancel, freeze,
    start, and update_price operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: MembershipPaymentSyncService,
        payment_service: PaymentsStripePaymentService,
        gym_stripe_service: GymStripeService,
    ) -> None:
        deps = (db_pool, payment_sync_service)
        self._cancel = MemberMembershipsCancel(*deps)
        self._freeze = MemberMembershipsFreeze(*deps)
        self._start = MemberMembershipsStart(
            *deps,
            payment_service=payment_service,
            gym_stripe_service=gym_stripe_service,
        )
        self._update_price = MemberMembershipsUpdatePrice(*deps)

    # ── Cancel ─────────────────────────────────────────────────

    async def cancel(
        self,
        item_id: UUID,
        crm_user_id: UUID,
    ) -> None:
        """Cancel a specific active recurring membership."""
        await self._cancel.cancel(item_id, crm_user_id)

    # ── Freeze / Unfreeze ──────────────────────────────────────

    async def freeze(
        self,
        crm_user_id: UUID,
        gym_id: UUID,
        freeze_months: int,
    ) -> None:
        """Freeze a member's account (account-level)."""
        await self._freeze.freeze(crm_user_id, gym_id, freeze_months)

    async def unfreeze(
        self,
        crm_user_id: UUID,
        gym_id: UUID,
    ) -> None:
        """Unfreeze a member's account (account-level)."""
        await self._freeze.unfreeze(crm_user_id, gym_id)

    # ── Start ──────────────────────────────────────────────────

    async def start(
        self,
        crm_user_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
        price_id: UUID,
        start_date: date,
        discount_ids: list[UUID] | None = None,
        include_linked_discount: bool = False,
        prorate: bool = True,
    ) -> None:
        """Start a new membership for a member."""
        await self._start.start(
            crm_user_id=crm_user_id,
            gym_id=gym_id,
            plan_id=plan_id,
            price_id=price_id,
            start_date=start_date,
            discount_ids=discount_ids,
            include_linked_discount=include_linked_discount,
            prorate=prorate,
        )

    # ── Update Price ───────────────────────────────────────────

    async def update_price(
        self,
        item_id: UUID,
        crm_user_id: UUID,
        new_price_id: UUID,
        prorate: bool = False,
    ) -> None:
        """Update the price tier of an existing membership."""
        await self._update_price.update_price(
            item_id=item_id,
            crm_user_id=crm_user_id,
            new_price_id=new_price_id,
            prorate=prorate,
        )
