"""Report whether a member has a payment method attached, read from Stripe."""

from __future__ import annotations

import logging
from uuid import UUID

from src.members.members_exceptions import (
    MemberGymStripeAccountMissingError,
)
from src.members.service.management.members_management_base import (
    MembersManagementBase,
)

logger = logging.getLogger(__name__)


class MembersManagementPaymentMethods(MembersManagementBase):
    """Read a member's attached-payment-method status live from Stripe.

    Deliberately encodes no client's policy — it answers only "is a payment
    method attached"; what a caller does with that is the caller's business.
    """

    async def has_payment_method(self, member_id: UUID) -> bool:
        """Whether the member has ANY payment method attached in Stripe.

        **Stripe is the source of truth, never the cached CRM column.**
        ``members.stripe_payment_method_id`` records only the card the CRM
        last saved as default, so a method attached out of band leaves it
        NULL while the customer really does have one — the false negative
        this read exists to prevent. No Stripe customer returns ``False``.

        Args:
            member_id: The member to inspect.

        Returns:
            True when the Stripe customer has at least one method attached.

        Raises:
            MemberNotFoundError: The member does not exist (-> 404).
            MemberGymStripeAccountMissingError: The member has a Stripe
                customer while their gym has none (-> 400) — an
                inconsistency a caller must not read as "no payment method".
            PaymentsStripeError / stripe.StripeError: Any Stripe failure
                propagates — an error is NOT ``False``.
        """
        info = await self._get_stripe_info(member_id)

        stripe_customer_id = info["stripe_customer_id"]
        if not stripe_customer_id:
            return False

        stripe_account_id = info["stripe_account_id"]
        if not stripe_account_id:
            # Unanswerable, so fail loudly rather than report the
            # safe-looking (and possibly wrong) False.
            raise MemberGymStripeAccountMissingError(
                f"Gym {info['gym_id']} has no Stripe account configured"
            )

        return await self._payments.has_attached_payment_method(
            stripe_customer_id=stripe_customer_id,
            stripe_account_id=stripe_account_id,
        )
