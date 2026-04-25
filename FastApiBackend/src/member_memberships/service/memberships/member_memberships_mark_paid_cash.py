"""Mark a recurring membership's open invoice as paid via cash.

Finds the subscription's currently-open Stripe invoice and pays it
out of band — no card is charged. Stripe's ``invoice.paid`` webhook
then writes the CRM invoice and charge rows with
``payment_method_type='cash'``.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.service.memberships.member_memberships_base import (
    MemberMembershipsBase,
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

logger = logging.getLogger(__name__)


class MemberMembershipsMarkPaidCash(MemberMembershipsBase):
    """Pay a recurring membership's open Stripe invoice out of band."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: MembershipPaymentSyncService,
        gym_stripe_service: GymStripeService,
        payment_service: PaymentsStripePaymentService,
    ) -> None:
        super().__init__(
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._payment_service = payment_service

    async def mark_paid_cash(
        self,
        item_id: UUID,
        crm_user_id: UUID,
        idempotency_key: UUID,
    ) -> None:
        """Mark the membership's subscription's open invoice paid via cash.

        Validates the membership is recurring and has a Stripe
        subscription item, resolves the paying parent to get the
        monthly subscription id, then delegates to the payment
        service to list + pay the open invoice.

        Args:
            item_id: The membership row id.
            crm_user_id: The member (or family member) whose
                subscription holds the open invoice.

        Raises:
            ValueError: If the membership is not recurring, not
                linked to a Stripe subscription, or has no open
                invoice on that subscription.
            PaymentsStripeError: If Stripe returns an error.
        """
        membership = await self._get_membership(item_id, crm_user_id)

        plan_type = PlanType(membership["plan_type"])
        if plan_type != PlanType.recurring:
            raise ValueError("mark-paid-cash only applies to recurring memberships")
        if not membership["stripe_item_id"]:
            raise ValueError(f"Membership {item_id} is not linked to a Stripe subscription")

        parent = await self._payment_sync.resolve_parent(crm_user_id)
        if not parent.stripe_sub_id_month:
            raise ValueError(f"No active monthly subscription for crm_user_id={crm_user_id}")

        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            parent.gym_id,
        )

        await self._payment_service.pay_open_subscription_invoice_out_of_band(
            stripe_subscription_id=parent.stripe_sub_id_month,
            stripe_account_id=stripe_account_id,
            idempotency_key=str(idempotency_key),
        )
