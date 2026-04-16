import stripe
from stripe.params._subscription_update_params import (
    SubscriptionUpdateParams,
)

from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionResponse,
    PaymentsSubscriptionUpdateRequest,
)
from src.payments.service.payments_stripe_mappers import (
    map_invoice_preview,
)
from src.payments.service.subscription.payments_subscription_base import (
    PaymentsSubscriptionBase,
)


class PaymentsSubscriptionUpdate(PaymentsSubscriptionBase):
    """Update existing Stripe subscriptions."""

    async def _build_update_params(
        self,
        request: PaymentsSubscriptionUpdateRequest,
        stripe_account_id: str,
    ) -> tuple[SubscriptionUpdateParams, stripe.Subscription, stripe.RequestOptions]:
        """Validate, consolidate, and build all params for update."""
        opts = self._client.connect_opts(stripe_account_id)

        sub = await self._retrieve_subscription(
            request.stripe_subscription_id,
            opts,
        )

        await self._validate_subscription_request(
            request,
            stripe_account_id,
        )
        consolidated = self._consolidate_items(request.items)
        items = self._build_reconcile_items(consolidated, sub)

        update_params = SubscriptionUpdateParams(
            items=items,
            proration_behavior=request.proration_behavior,
        )
        update_params["discounts"] = self._build_subscription_discounts(
            request.subscription_discounts,
        )
        if request.metadata is not None:
            update_params["metadata"] = request.metadata

        return update_params, sub, opts

    async def update_subscription(
        self,
        request: PaymentsSubscriptionUpdateRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse:
        """Update an existing subscription to match the desired state.

        Args:
            request: Desired subscription state with subscription ID.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Updated subscription details.
        """
        update_params, _, opts = await self._build_update_params(request, stripe_account_id)

        await self._stripe.v1.subscriptions.update_async(
            request.stripe_subscription_id,
            params=update_params,
            options=opts,
        )

        sub = await self._retrieve_subscription(
            request.stripe_subscription_id,
            opts,
        )
        return self._map_subscription(sub)

    async def preview_update_subscription(
        self,
        request: PaymentsSubscriptionUpdateRequest,
        stripe_account_id: str,
    ) -> PaymentsInvoicePreviewResponse:
        """Preview the next invoice after updating a subscription.

        Args:
            request: Desired subscription state with subscription ID.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Invoice preview with amount due and line items.
        """
        update_params, _, opts = await self._build_update_params(request, stripe_account_id)

        invoice = await self._stripe.v1.invoices.create_preview_async(
            params=update_params,
            options=opts,
        )
        return map_invoice_preview(invoice)
