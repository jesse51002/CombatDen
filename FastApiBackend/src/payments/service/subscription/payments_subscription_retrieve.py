"""Read the current state of an existing Stripe subscription."""

from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionResponse,
)
from src.payments.service.subscription.payments_subscription_base import (
    PaymentsSubscriptionBase,
)


class PaymentsSubscriptionRetrieve(PaymentsSubscriptionBase):
    """Retrieve the live state of a subscription (read-only)."""

    async def get_subscription(
        self,
        stripe_subscription_id: str,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse:
        """Retrieve a subscription's current items and discounts.

        Read-only. The mapped response carries each item's currently
        attached coupon ids (``items[*].discounts``) and the
        subscription-level coupon ids (``discounts``) — the payment sync
        reads these to verify which coupons Stripe currently has attached
        to the subscription.

        Args:
            stripe_subscription_id: The live Stripe subscription ID.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            The subscription's current state.

        Raises:
            PaymentsResourceNotFoundError: If the subscription is not
                found or is canceled.
        """
        opts = self._client.connect_opts_readonly(stripe_account_id)
        sub = await self._retrieve_subscription(
            stripe_subscription_id,
            opts,
        )
        return self._map_subscription(sub)
