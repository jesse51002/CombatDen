"""Charge an ad-hoc amount for a member, billed to an explicit payer.

Creates a one-off Stripe invoice (outside any subscription) for the
supplied amount and reason, on the request's ``paid_by_member_id``'s own
Stripe customer — the member themselves or their linked parent (the
self-or-parent authorization rule). The existing ``invoice.paid`` webhook
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
    from src.shared.gym_stripe_service import GymStripeService
    from src.shared.payer_resolver import PayerResolver
    from src.sync.service.sync_service import (
        PaymentSyncService,
    )

logger = logging.getLogger(__name__)


class MemberMembershipsChargeCard(MemberMembershipsBase):
    """Charge an explicit payer's card (or mark as cash) for an ad-hoc amount."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        payment_service: PaymentsStripePaymentService,
        payer_resolver: PayerResolver,
    ) -> None:
        super().__init__(
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._payment_service = payment_service
        self._payer_resolver = payer_resolver

    async def charge_card(
        self,
        request: MemberMembershipsChargeCardRequest,
    ) -> None:
        """Create and pay a one-off invoice for ``amount_cents``.

        Validates the request's payer is authorized for the member (the
        member themselves or the member's linked parent), resolves the
        PAYER's own Stripe customer, validates the request's ``gym_id``
        matches, then delegates to the payment service to create +
        finalize + pay the invoice. When ``paid_cash=True`` the invoice
        is paid out of band (no card charge).

        Args:
            request: Charge-card request (beneficiary + explicit payer).

        Raises:
            ValueError: If the payer is not the member or their linked
                parent, or the payer's profile is not in the requested gym.
            PaymentsStripeError: If Stripe returns an error.
        """
        await self._assert_payer_allowed(
            request.member_id, request.paid_by_member_id,
        )
        payer = await self._payer_resolver.resolve_payer(
            request.paid_by_member_id,
        )
        if payer.gym_id != request.gym_id:
            raise ValueError(
                f"Payer {request.paid_by_member_id} is not in gym {request.gym_id}",
            )

        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            payer.gym_id,
        )

        metadata = StripeAdHocInvoiceMetadata(
            member_id=request.member_id,
            gym_id=payer.gym_id,
        )

        payment_request = PaymentsInvoicePaymentCreateRequest(
            stripe_customer_id=payer.stripe_customer_id,
            items=[
                PaymentsInvoiceItemSpec(
                    amount=request.amount_cents,
                    description=request.reason,
                )
            ],
            metadata=metadata,
            # The reason lands on BOTH the invoice header and the line item.
            description=request.reason,
            paid_out_of_band=request.paid_cash,
            idempotency_key=str(request.idempotency_key),
        )

        await self._payment_service.create_invoice_payment(
            payment_request,
            stripe_account_id,
        )
