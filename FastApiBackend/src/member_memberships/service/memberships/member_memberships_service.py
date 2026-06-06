"""Membership lifecycle operations (facade).

Delegates to focused sub-services while preserving
the public API and constructor signature.
"""

from __future__ import annotations

from datetime import date
from typing import TYPE_CHECKING
from uuid import UUID

from src.member_memberships.schema.member_memberships_schema import (
    MemberMembershipsChargeCardRequest,
)
from src.member_memberships.service.memberships.member_memberships_cancel import (
    MemberMembershipsCancel,
)
from src.member_memberships.service.memberships.member_memberships_charge_card import (
    MemberMembershipsChargeCard,
)
from src.member_memberships.service.memberships.member_memberships_freeze import (
    MemberMembershipsFreeze,
)
from src.member_memberships.service.memberships.member_memberships_mark_paid_cash import (
    MemberMembershipsMarkPaidCash,
)
from src.member_memberships.service.memberships.member_memberships_start import (
    MemberMembershipsStart,
)
from src.member_memberships.service.memberships.member_memberships_update_discounts import (
    MemberMembershipsUpdateDiscounts,
)
from src.member_memberships.service.memberships.member_memberships_update_price import (
    MemberMembershipsUpdatePrice,
)
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.shared.database import DirectDatabasePool

if TYPE_CHECKING:
    from src.member_memberships.service.payment_sync.payment_sync_service import (
        PaymentSyncService,
    )
    from src.payments.service.payments_stripe_payment_service import (
        PaymentsStripePaymentService,
    )
    from src.shared.billing_parent_resolver import BillingParentResolver
    from src.shared.gym_stripe_service import GymStripeService


class MemberMembershipsService:
    """Membership lifecycle operations (facade).

    Delegates to focused sub-services for cancel, freeze,
    start, and update_price operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        payment_service: PaymentsStripePaymentService,
        gym_stripe_service: GymStripeService,
        parent_resolver: BillingParentResolver,
    ) -> None:
        deps = (
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._cancel = MemberMembershipsCancel(*deps)
        self._freeze = MemberMembershipsFreeze(*deps)
        self._start = MemberMembershipsStart(
            *deps,
            payment_service=payment_service,
            parent_resolver=parent_resolver,
        )
        self._update_price = MemberMembershipsUpdatePrice(*deps)
        self._update_discounts = MemberMembershipsUpdateDiscounts(*deps)
        self._mark_paid_cash = MemberMembershipsMarkPaidCash(
            *deps,
            payment_service=payment_service,
        )
        self._charge_card = MemberMembershipsChargeCard(
            *deps,
            payment_service=payment_service,
        )

    # ── Cancel ─────────────────────────────────────────────────

    async def cancel(
        self,
        item_id: UUID,
        member_id: UUID,
        idempotency_key: UUID,
    ) -> date:
        """Cancel a specific active recurring membership.

        Returns the resolved ``cancel_date`` — the date through
        which the membership remains active.
        """
        return await self._cancel.cancel(item_id, member_id, idempotency_key)

    async def preview_cancel(
        self,
        item_id: UUID,
        member_id: UUID,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what cancelling a membership would charge."""
        return await self._cancel.preview_cancel(item_id, member_id)

    # ── Freeze / Unfreeze ──────────────────────────────────────

    async def freeze(
        self,
        member_id: UUID,
        gym_id: UUID,
        freeze_months: int,
        idempotency_key: UUID,
    ) -> None:
        """Freeze a member's account (account-level)."""
        await self._freeze.freeze(member_id, gym_id, freeze_months, idempotency_key)

    async def unfreeze(
        self,
        member_id: UUID,
        gym_id: UUID,
        idempotency_key: UUID,
    ) -> None:
        """Unfreeze a member's account (account-level)."""
        await self._freeze.unfreeze(member_id, gym_id, idempotency_key)

    # ── Start ──────────────────────────────────────────────────

    async def start(
        self,
        member_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
        price_id: UUID,
        idempotency_key: UUID,
        prorate: bool = True,
        paid_with_cash: bool = False,
    ) -> None:
        """Start a new membership for a member."""
        await self._start.start(
            member_id=member_id,
            gym_id=gym_id,
            plan_id=plan_id,
            price_id=price_id,
            idempotency_key=idempotency_key,
            prorate=prorate,
            paid_with_cash=paid_with_cash,
        )

    async def preview_start(
        self,
        member_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
        price_id: UUID,
        prorate: bool = True,
        paid_with_cash: bool = False,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what starting a membership would charge."""
        return await self._start.preview(
            member_id=member_id,
            gym_id=gym_id,
            plan_id=plan_id,
            price_id=price_id,
            prorate=prorate,
            paid_with_cash=paid_with_cash,
        )

    # ── Mark Paid (Cash) ───────────────────────────────────────

    async def mark_paid_cash(
        self,
        item_id: UUID,
        member_id: UUID,
        idempotency_key: UUID,
    ) -> None:
        """Mark a recurring membership's open Stripe invoice as paid via cash."""
        await self._mark_paid_cash.mark_paid_cash(item_id, member_id, idempotency_key)

    # ── Charge Card (ad-hoc amount) ────────────────────────────

    async def charge_card(
        self,
        request: MemberMembershipsChargeCardRequest,
    ) -> None:
        """Charge a member's card (or mark as cash) for an ad-hoc amount."""
        await self._charge_card.charge_card(request)

    # ── Update Price ───────────────────────────────────────────

    async def update_price(
        self,
        item_id: UUID,
        member_id: UUID,
        idempotency_key: UUID,
        prorate: bool = False,
    ) -> None:
        """Upgrade a membership to its plan's currently active price."""
        await self._update_price.update_price(
            item_id=item_id,
            member_id=member_id,
            idempotency_key=idempotency_key,
            prorate=prorate,
        )

    async def preview_update_price(
        self,
        item_id: UUID,
        member_id: UUID,
        prorate: bool = False,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview upgrading a membership to the plan's active price."""
        return await self._update_price.preview_update_price(
            item_id=item_id,
            member_id=member_id,
            prorate=prorate,
        )

    # ── Apply Discounts (add / remove snapshots) ───────────────

    async def apply_discounts(
        self,
        item_id: UUID,
        member_id: UUID,
        add_preset_ids: list[UUID],
        remove_applied_ids: list[UUID],
        idempotency_key: UUID,
    ) -> None:
        """Add / remove discount snapshots on an existing membership."""
        await self._update_discounts.apply_discounts(
            item_id=item_id,
            member_id=member_id,
            add_preset_ids=add_preset_ids,
            remove_applied_ids=remove_applied_ids,
            idempotency_key=idempotency_key,
        )

    async def preview_apply_discounts(
        self,
        item_id: UUID,
        member_id: UUID,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview the subscription with the membership's current snapshots."""
        return await self._update_discounts.preview_apply_discounts(
            item_id=item_id,
            member_id=member_id,
        )
