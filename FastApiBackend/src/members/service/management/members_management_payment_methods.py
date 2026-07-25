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

    A property of the member's billing profile, stated in billing terms —
    any caller may ask it. It deliberately encodes no client's policy:
    the answer is "does this member have a payment method attached", and
    what a caller does with that is the caller's business.
    """

    async def has_payment_method(self, member_id: UUID) -> bool:
        """Whether the member has ANY payment method attached in Stripe.

        **Stripe is the source of truth, never a cached CRM column.**
        ``members.stripe_payment_method_id`` records only the card the CRM
        last saved as the default; a method attached out of band, or one
        the CRM's own writeback missed, would leave that column NULL while
        the customer really does have a chargeable method. Reading the
        stale column would answer "no payment method" for a member who has
        one — the exact false negative this read exists to prevent.

        A member with no Stripe customer returns ``False``: nothing can be
        attached to a customer that does not exist.

        Args:
            member_id: The member to inspect.

        Returns:
            True when the member's Stripe customer has at least one
            payment method attached.

        Raises:
            MemberNotFoundError: The member does not exist (-> 404).
            MemberGymStripeAccountMissingError: The member has a Stripe
                customer while their gym has no Stripe account configured
                (-> 400) — an inconsistency the caller must not read as
                "no payment method".
            PaymentsStripeError / stripe.StripeError: Any Stripe failure
                propagates — an error is NOT ``False``.
        """
        info = await self._get_stripe_info(member_id)

        stripe_customer_id = info["stripe_customer_id"]
        if not stripe_customer_id:
            return False

        stripe_account_id = info["stripe_account_id"]
        if not stripe_account_id:
            # The member has a customer but the gym's Connect account is
            # gone: the question is unanswerable, so fail loudly rather
            # than report the safe-looking (and possibly wrong) False.
            raise MemberGymStripeAccountMissingError(
                f"Gym {info['gym_id']} has no Stripe account configured"
            )

        return await self._payments.has_attached_payment_method(
            stripe_customer_id=stripe_customer_id,
            stripe_account_id=stripe_account_id,
        )
