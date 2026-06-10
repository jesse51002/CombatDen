"""Charge a member's card for an ad-hoc amount.

Creates a one-off Stripe invoice (outside any subscription) for the
supplied amount and reason. The existing ``invoice.paid`` webhook
persists the CRM invoice and charge rows once Stripe settles the
payment. When ``paid_cash=True`` the invoice is marked paid out of
band in Stripe instead of charging the card.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from src.memberships.memberships_schema import (
    MemberMembershipsChargeCardRequest,
)
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.payments.schema.metadata.stripe_ad_hoc_invoice_metadata import (
    StripeAdHocInvoiceMetadata,
)
from src.payments.schema.payments_payment_schema import (
    PaymentsInvoiceItemSpec,
    PaymentsInvoicePaymentCreateRequest,
)
from src.shared.database import DirectDatabasePool

if TYPE_CHECKING:
    from src.payments.service.payments_stripe_payment_service import (
        PaymentsStripePaymentService,
    )
    from src.shared.billing_parent_resolver import BillingParentResolver
    from src.shared.gym_stripe_service import GymStripeService
    from src.sync.service.sync_service import (
        PaymentSyncService,
    )

logger = logging.getLogger(__name__)


class MemberMembershipsChargeCard(MemberMembershipsBase):
    """Charge a member's card (or mark as cash) for an ad-hoc amount."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        payment_service: PaymentsStripePaymentService,
        parent_resolver: BillingParentResolver,
    ) -> None:
        super().__init__(
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._payment_service = payment_service
        self._parent_resolver = parent_resolver

    async def charge_card(
        self,
        request: MemberMembershipsChargeCardRequest,
    ) -> None:
        """Create and pay a one-off invoice for ``amount_cents``.

        Resolves the paying parent to get the Stripe customer id,
        validates the request's ``gym_id`` matches the parent's
        gym, then delegates to the payment service to create +
        finalize + pay the invoice. When ``paid_cash=True`` the
        invoice is paid out of band (no card charge).

        Args:
            request: Charge-card request.

        Raises:
            ValueError: If the member's parent profile is not in
                the requested gym.
            PaymentsStripeError: If Stripe returns an error.
        """
        parent = await self._parent_resolver.resolve_parent(request.member_id)
        if parent.gym_id != request.gym_id:
            raise ValueError(
                f"Member {request.member_id} is not in gym {request.gym_id}",
            )

        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            parent.gym_id,
        )

        metadata = StripeAdHocInvoiceMetadata(
            member_id=request.member_id,
            gym_id=parent.gym_id,
        )

        payment_request = PaymentsInvoicePaymentCreateRequest(
            stripe_customer_id=parent.stripe_customer_id,
            items=[
                PaymentsInvoiceItemSpec(
                    amount=request.amount_cents,
                    description=request.reason,
                )
            ],
            metadata=metadata,
            paid_out_of_band=request.paid_cash,
            idempotency_key=str(request.idempotency_key),
        )

        await self._payment_service.create_invoice_payment(
            payment_request,
            stripe_account_id,
        )
