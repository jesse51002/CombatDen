"""Stripe subscription item retrieval."""

import stripe

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionItemResponse,
)
from src.payments.service.subscription.payments_subscription_base import (
    PaymentsSubscriptionBase,
)


class PaymentsSubscriptionItem(PaymentsSubscriptionBase):
    """Retrieve and inspect individual subscription items."""

    async def get_item(
        self,
        subscription_item_id: str,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionItemResponse:
        """Retrieve a single subscription item from Stripe.

        Raises PaymentsResourceNotFoundError if the item does not
        exist or if its parent subscription is canceled.

        Args:
            subscription_item_id: The Stripe subscription item ID.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            The subscription item details.

        Raises:
            PaymentsResourceNotFoundError: If the item is not found
                or its parent subscription is canceled.
        """
        opts = self._client.connect_opts(stripe_account_id)

        try:
            si = await self._stripe.v1.subscription_items.retrieve_async(
                subscription_item_id,
                options=opts,
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsResourceNotFoundError(
                f"Subscription item {subscription_item_id} not found",
                resource_id=subscription_item_id,
                resource_type=StripeResourceType.subscription_item,
            ) from exc

        subscription_id = si.subscription
        await self._retrieve_subscription(subscription_id, opts)

        discount_ids: list[str] = []
        if hasattr(si, "discounts") and si.discounts:
            for d in si.discounts:
                if hasattr(d, "coupon") and d.coupon:
                    discount_ids.append(d.coupon.id)

        return PaymentsSubscriptionItemResponse(
            stripe_subscription_item_id=si.id,
            stripe_price_id=si.price.id,
            quantity=si.quantity or 1,
            discounts=discount_ids,
        )
