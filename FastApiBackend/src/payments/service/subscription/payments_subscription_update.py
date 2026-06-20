import stripe
from stripe.params._invoice_create_preview_params import (
    InvoiceCreatePreviewParams,
)
from stripe.params._subscription_update_params import (
    SubscriptionUpdateParams,
)

from src.payments.schema.payments_invoice_schema import (
    PreviewInvoice,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionResponse,
    PaymentsSubscriptionUpdateRequest,
)
from src.payments.service.payments_stripe_mappers import (
    map_preview_invoice,
    proration_behavior_to_stripe,
)
from src.payments.service.subscription.payments_subscription_base import (
    PaymentsSubscriptionBase,
)


class PaymentsSubscriptionUpdate(PaymentsSubscriptionBase):
    """Update existing Stripe subscriptions.

    On the **card path** (``pay_first_invoice_out_of_band`` is False) the update
    is sent with ``payment_behavior='error_if_incomplete'``: a proration charge
    that the card can't cover 402s the update and is rolled back, so a decline
    fails the op rather than silently adding the member behind an open unpaid
    proration invoice. The **cash path** is excluded — its proration invoice is
    settled out of band later — and a ``proration_behavior='none'`` update
    generates no invoice, so the behavior is a no-op there.
    """

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

        # No price/coupon re-validation on update. It discarded its return here
        # (the recurring interval is only needed by create, for the monthly
        # billing_cycle_anchor) and looped a price+product retrieve over EVERY
        # item on the sub, so re-syncing an N-item family cost 2N wasted Stripe
        # round-trips that grew with family size. The items are already-live
        # (validated when first added) or freshly added from memberships whose
        # prices were validated at start, and their coupons were just
        # find-or-created by this same sync. _build_reconcile_items still raises
        # if a desired item's stripe_item_id is missing from the live sub
        # (out-of-sync detection); a genuinely bad price now surfaces as a Stripe
        # error on the update itself. (Create still validates + reactivates an
        # archived price.)
        consolidated = self._consolidate_items(request.items)
        items = self._build_reconcile_items(consolidated, sub)

        update_params = SubscriptionUpdateParams(
            items=items,
            proration_behavior=proration_behavior_to_stripe(
                request.proration_behavior
            ),
        )
        update_params["metadata"] = request.metadata.to_stripe_metadata()

        if not request.pay_first_invoice_out_of_band:
            # Card path: a proration that prorate-bills now (or an
            # always_invoice update) generates an invoice that auto-collects
            # silently today. error_if_incomplete makes Stripe 402 the update
            # if that proration charge can't be paid — and roll the item
            # changes back — so a decline fails the op instead of leaving the
            # member added but unpaid. A cash family
            # (``pay_first_invoice_out_of_band``) is excluded: their card may
            # be missing or failing on purpose and their open proration invoice
            # is settled later out of band (mark_paid_cash), so it must NOT
            # error here. A proration_behavior='none' update generates no
            # invoice, so this is a no-op there.
            update_params["payment_behavior"] = "error_if_incomplete"

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
    ) -> PreviewInvoice:
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
        return map_preview_invoice(invoice)
