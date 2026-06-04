import stripe
from stripe.params._invoice_create_preview_params import (
    InvoiceCreatePreviewParams,
)
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
        *,
        for_preview: bool,
    ) -> tuple[SubscriptionUpdateParams, stripe.Subscription, stripe.RequestOptions]:
        """Validate, consolidate, and build all params for update."""
        read_opts = self._client.connect_opts_readonly(stripe_account_id)
        if for_preview:
            opts = read_opts
        else:
            opts = self._client.connect_opts(
                stripe_account_id, idempotency_key=request.idempotency_key
            )

        sub = await self._retrieve_subscription(
            request.stripe_subscription_id,
            read_opts,
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
        update_params["metadata"] = request.metadata.to_stripe_metadata()

        return update_params, sub, opts

    async def update_subscription(
        self,
        request: PaymentsSubscriptionUpdateRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse:
        """Update an existing subscription to match the desired state."""
        update_params, _, opts = await self._build_update_params(
            request, stripe_account_id, for_preview=False
        )

        await self._stripe.v1.subscriptions.update_async(
            request.stripe_subscription_id,
            params=update_params,
            options=opts,
        )

        read_opts = self._client.connect_opts_readonly(stripe_account_id)
        sub = await self._retrieve_subscription(
            request.stripe_subscription_id,
            read_opts,
        )
        return self._map_subscription(sub)

    async def preview_update_subscription(
        self,
        request: PaymentsSubscriptionUpdateRequest,
        stripe_account_id: str,
    ) -> PaymentsInvoicePreviewResponse:
        """Preview the next invoice after updating a subscription."""
        update_params, _, opts = await self._build_update_params(
            request, stripe_account_id, for_preview=True
        )

        preview_params = InvoiceCreatePreviewParams(
            customer=request.stripe_customer_id,
            subscription=request.stripe_subscription_id,
            subscription_details={
                "items": update_params.get("items", []),
                "proration_behavior": update_params["proration_behavior"],
            },
        )
        discounts = update_params.get("discounts")
        if discounts:
            preview_params["discounts"] = discounts

        invoice = await self._stripe.v1.invoices.create_preview_async(
            params=preview_params,
            options=opts,
        )
        return map_invoice_preview(invoice)
