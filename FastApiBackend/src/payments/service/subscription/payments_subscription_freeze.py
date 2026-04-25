from stripe.params._subscription_update_params import (
    SubscriptionUpdateParams,
    SubscriptionUpdateParamsPauseCollection,
)

from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionFreezeRequest,
    PaymentsSubscriptionFreezeResponse,
    PaymentsSubscriptionResponse,
    PaymentsSubscriptionUnfreezeRequest,
)
from src.payments.service.subscription.payments_subscription_base import (
    PaymentsSubscriptionBase,
)


class PaymentsSubscriptionFreeze(PaymentsSubscriptionBase):
    """Freeze and unfreeze Stripe subscriptions."""

    async def freeze_subscription(
        self,
        request: PaymentsSubscriptionFreezeRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionFreezeResponse:
        """Pause collection on a subscription (freeze).

        If ``freeze_end_date`` is provided, the subscription will
        automatically resume on that date.
        """
        read_opts = self._client.connect_opts_readonly(stripe_account_id)
        write_opts = self._client.connect_opts(
            stripe_account_id, idempotency_key=request.idempotency_key
        )

        await self._retrieve_subscription(
            request.stripe_subscription_id,
            read_opts,
        )

        pause_params = SubscriptionUpdateParamsPauseCollection(
            behavior="void",
        )
        if request.freeze_end_date:
            pause_params["resumes_at"] = self._date_to_unix(
                request.freeze_end_date,
            )

        sub = await self._stripe.v1.subscriptions.update_async(
            request.stripe_subscription_id,
            params=SubscriptionUpdateParams(pause_collection=pause_params),
            options=write_opts,
        )

        actual_resumes_at = None
        if sub.pause_collection and sub.pause_collection.resumes_at:
            actual_resumes_at = sub.pause_collection.resumes_at

        return PaymentsSubscriptionFreezeResponse(
            stripe_subscription_id=sub.id,
            pause_collection_behavior="void",
            resumes_at=actual_resumes_at,
        )

    async def unfreeze_subscription(
        self,
        request: PaymentsSubscriptionUnfreezeRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse:
        """Resume collection on a paused subscription (unfreeze).

        Clears pause_collection and preserves the original billing
        cycle alignment by passing billing_cycle_anchor="unchanged".
        """
        read_opts = self._client.connect_opts_readonly(stripe_account_id)
        write_opts = self._client.connect_opts(
            stripe_account_id, idempotency_key=request.idempotency_key
        )

        await self._retrieve_subscription(
            request.stripe_subscription_id,
            read_opts,
        )

        sub = await self._stripe.v1.subscriptions.update_async(
            request.stripe_subscription_id,
            params=SubscriptionUpdateParams(
                pause_collection="",
                billing_cycle_anchor="unchanged",
            ),
            options=write_opts,
        )
        return self._map_subscription(sub)
