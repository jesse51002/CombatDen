"""Retry the saved card on a recurring membership's open invoice.

Finds the subscription's currently-open Stripe invoice and pays it on
the payer's DEFAULT card — the card twin of mark-paid-cash. Stripe's
``invoice.paid`` webhook then writes the CRM invoice and charge rows; a
decline raises from Stripe and propagates to the caller.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_today

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


class MemberMembershipsRetryCard(MemberMembershipsBase):
    """Retry a recurring membership's open Stripe invoice on the card."""

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

    async def retry_card(
        self,
        item_id: UUID,
        member_id: UUID,
        idempotency_key: UUID,
    ) -> None:
        """Retry the payer's default card on the subscription's open invoice.

        Validates the membership is recurring and has a Stripe
        subscription item, resolves the membership's PAYER (the row's
        ``paid_by_member_id``) to get the monthly subscription id, then
        delegates to the payment service to list + pay the open invoice on
        the payer's saved default card.

        Args:
            item_id: The membership row id.
            member_id: The member who owns the membership row.

        Raises:
            ValueError: If the membership is not recurring, is
                canceled, not linked to a Stripe subscription, or has
                no open invoice on that subscription.
            PaymentsStripeError: If Stripe returns an error.
            stripe.CardError: If the card is declined.
        """
        membership = await self._get_membership(item_id, member_id)

        plan_type = PlanType(membership["plan_type"])
        if plan_type != PlanType.recurring:
            raise ValueError("retry-card only applies to recurring memberships")
        if not membership["stripe_item_id"]:
            raise ValueError(f"Membership {item_id} is not linked to a Stripe subscription")

        cancel_date = membership["cancel_date"]
        if cancel_date is not None and cancel_date <= gym_today(
            membership["timezone"]
        ):
            raise ValueError(
                "Cannot retry the card on a canceled membership; "
                "create a new membership instead"
            )

        payer = await self._payer_resolver.resolve_payer(
            membership["paid_by_member_id"],
        )
        if not payer.stripe_sub_id_month:
            raise ValueError(
                f"No active monthly subscription for payer {payer.member_id}",
            )

        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            payer.gym_id,
        )

        await self._payment_service.pay_open_subscription_invoice_on_card(
            stripe_subscription_id=payer.stripe_sub_id_month,
            stripe_account_id=stripe_account_id,
            idempotency_key=str(idempotency_key),
        )
