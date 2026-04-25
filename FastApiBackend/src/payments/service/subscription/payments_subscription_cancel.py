import logging

from stripe.params._subscription_update_params import (
    SubscriptionUpdateParams,
)

from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionCancelRequest,
    PaymentsSubscriptionResponse,
)
from src.payments.service.subscription.payments_subscription_base import (
    PaymentsSubscriptionBase,
)

logger = logging.getLogger(__name__)


class PaymentsSubscriptionCancel(PaymentsSubscriptionBase):
    """Cancel Stripe subscriptions."""

    async def cancel_subscription(
        self,
        request: PaymentsSubscriptionCancelRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse:
        """Cancel a subscription immediately or at period end.

        If the subscription is already cancelled, logs a warning
        and returns the current state.
        """
        read_opts = self._client.connect_opts_readonly(stripe_account_id)
        write_opts = self._client.connect_opts(
            stripe_account_id, idempotency_key=request.idempotency_key
        )

        sub = await self._retrieve_subscription(
            request.stripe_subscription_id,
            read_opts,
        )

        if sub.status == "canceled":
            logger.warning(
                "Subscription %s is already cancelled",
                request.stripe_subscription_id,
            )
            return self._map_subscription(sub)

        if request.cancel_at_period_end:
            sub = await self._stripe.v1.subscriptions.update_async(
                request.stripe_subscription_id,
                params=SubscriptionUpdateParams(cancel_at_period_end=True),
                options=write_opts,
            )
        else:
            sub = await self._stripe.v1.subscriptions.cancel_async(
                request.stripe_subscription_id,
                options=write_opts,
            )
        return self._map_subscription(sub)
