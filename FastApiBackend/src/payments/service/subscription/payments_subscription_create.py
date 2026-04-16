from typing import Literal

import stripe
from schema.membership_plan import DurationUnit
from stripe.params._invoice_create_preview_params import (
    InvoiceCreatePreviewParams,
)
from stripe.params._invoice_pay_params import InvoicePayParams
from stripe.params._invoice_update_params import InvoiceUpdateParams
from stripe.params._subscription_create_params import (
    SubscriptionCreateParams,
    SubscriptionCreateParamsBillingCycleAnchorConfig,
)

import src.shared.db_schema_path  # noqa: F401
from src.core.config import MONTHLY_BILLING_ANCHOR_DAY
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionCreateRequest,
    PaymentsSubscriptionResponse,
)
from src.payments.service.cash_constants import (
    CRM_PAID_WITH_CASH_METADATA_KEY,
    CRM_PAID_WITH_CASH_METADATA_VALUE,
)
from src.payments.service.payments_stripe_mappers import (
    map_invoice_preview,
)
from src.payments.service.subscription.payments_subscription_base import (
    PaymentsSubscriptionBase,
)


class PaymentsSubscriptionCreate(PaymentsSubscriptionBase):
    """Create new Stripe subscriptions."""

    async def _build_create_params(
        self,
        request: PaymentsSubscriptionCreateRequest,
        stripe_account_id: str,
    ) -> tuple[SubscriptionCreateParams, stripe.RequestOptions]:
        """Validate, consolidate, and build all params for create."""
        opts = self._client.connect_opts(stripe_account_id)

        recurring_interval = await self._validate_subscription_request(
            request,
            stripe_account_id,
        )
        await self._members.retrieve_customer(
            request.stripe_customer_id,
            opts,
        )

        consolidated = self._consolidate_items(request.items)
        items = self._build_create_items(consolidated)

        # Honor the per-item ``prorate`` flag the caller set (same
        # logic the UPDATE path uses in ``payment_sync_stripe``).
        # ``always_invoice`` is the Stripe value that cuts the
        # prorated first invoice immediately; ``none`` skips the
        # prorated amount entirely and lets the first real invoice
        # fire at the anchor date.
        proration_behavior: Literal["none", "always_invoice"] = (
            "always_invoice" if any(item.prorate for item in request.items) else "none"
        )

        create_params = SubscriptionCreateParams(
            customer=request.stripe_customer_id,
            items=items,
            metadata=request.metadata,
            proration_behavior=proration_behavior,
        )

        # Cash flow: only meaningful when we actually cut a first
        # invoice (prorate=True → always_invoice). For prorate=False
        # there is no immediate invoice — the sub just starts and
        # bills normally at the next anchor, the same as the card
        # path. So the out-of-band guards are gated on
        # ``always_invoice``.
        # - ``default_incomplete`` prevents Stripe from
        #   auto-charging the card.
        # - ``expand=['latest_invoice']`` gives us the invoice id
        #   back on the create response.
        if request.pay_first_invoice_out_of_band and proration_behavior == "always_invoice":
            create_params["payment_behavior"] = "default_incomplete"
            create_params["expand"] = ["latest_invoice"]

        sub_discounts = self._build_subscription_discounts(
            request.subscription_discounts,
        )
        if sub_discounts:
            create_params["discounts"] = sub_discounts

        if recurring_interval == DurationUnit.month:
            create_params["billing_cycle_anchor_config"] = (
                SubscriptionCreateParamsBillingCycleAnchorConfig(
                    day_of_month=MONTHLY_BILLING_ANCHOR_DAY,
                )
            )

        return create_params, opts

    async def create_subscription(
        self,
        request: PaymentsSubscriptionCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse:
        """Create a new subscription with flexible billing mode.

        Args:
            request: Desired subscription state (items, discounts, metadata).
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Created subscription details.
        """
        create_params, opts = await self._build_create_params(request, stripe_account_id)

        sub = await self._stripe.v1.subscriptions.create_async(
            params=create_params,
            options=opts,
        )

        # Only pay out of band when Stripe actually cut a first
        # invoice — i.e. when the derived behavior was
        # ``always_invoice``. For ``none``, there is no first
        # invoice to pay and ``_resolve_first_invoice_id`` would
        # raise.
        if (
            request.pay_first_invoice_out_of_band
            and create_params.get("proration_behavior") == "always_invoice"
        ):
            sub = await self._pay_first_invoice_out_of_band(sub, opts)

        return self._map_subscription(sub)

    async def _pay_first_invoice_out_of_band(
        self,
        sub: stripe.Subscription,
        opts: stripe.RequestOptions,
    ) -> stripe.Subscription:
        """Mark the subscription's first invoice as paid out of band.

        The subscription was created with
        ``payment_behavior='default_incomplete'``, so its first
        invoice is ``open`` and the sub is ``incomplete``. Paying
        the invoice out of band activates the subscription without
        charging the customer's card.
        """
        invoice_id = await self._resolve_first_invoice_id(sub, opts)

        # Tag the invoice as cash so the ``invoice.paid`` webhook
        # can write ``payment_method_type='cash'`` on the CRM
        # charge row. Stripe does not persist ``paid_out_of_band``
        # on the Invoice object, so this metadata is our signal.
        await self._stripe.v1.invoices.update_async(
            invoice_id,
            params=InvoiceUpdateParams(
                metadata={
                    CRM_PAID_WITH_CASH_METADATA_KEY: (CRM_PAID_WITH_CASH_METADATA_VALUE),
                },
            ),
            options=opts,
        )

        pay_params = InvoicePayParams()
        pay_params["paid_out_of_band"] = True
        await self._stripe.v1.invoices.pay_async(
            invoice_id,
            params=pay_params,
            options=opts,
        )

        # Re-retrieve the subscription so the response reflects its
        # now-active state after out-of-band payment.
        return await self._stripe.v1.subscriptions.retrieve_async(
            sub.id,
            options=opts,
        )

    async def _resolve_first_invoice_id(
        self,
        sub: stripe.Subscription,
        opts: stripe.RequestOptions,
    ) -> str:
        """Return the id of the subscription's first invoice.

        Prefers ``sub.latest_invoice`` (populated when we pass
        ``expand=['latest_invoice']`` on create), and falls back to
        listing invoices on the subscription if Stripe did not
        populate it.
        """
        latest_invoice = sub.latest_invoice
        if latest_invoice is not None:
            return latest_invoice if isinstance(latest_invoice, str) else latest_invoice.id

        invoices = await self._stripe.v1.invoices.list_async(
            params={"subscription": sub.id, "limit": 1},
            options=opts,
        )
        if invoices.data:
            return invoices.data[0].id

        raise ValueError(f"Subscription {sub.id} has no invoice to pay out of band")

    async def preview_create_subscription(
        self,
        request: PaymentsSubscriptionCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsInvoicePreviewResponse:
        """Preview the first invoice for a new subscription.

        Args:
            request: Desired subscription state (items, discounts).
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Invoice preview with amount due and line items.
        """
        create_params, opts = await self._build_create_params(request, stripe_account_id)

        preview_params = InvoiceCreatePreviewParams(
            customer=request.stripe_customer_id,
            subscription_details={
                "items": create_params.get("items", []),
                "proration_behavior": create_params["proration_behavior"],
            },
        )
        discounts = create_params.get("discounts")
        if discounts:
            preview_params["discounts"] = discounts

        invoice = await self._stripe.v1.invoices.create_preview_async(
            params=preview_params,
            options=opts,
        )
        return map_invoice_preview(invoice)
