import stripe
from schema.membership_plan import DurationUnit
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

        create_params = SubscriptionCreateParams(
            customer=request.stripe_customer_id,
            items=items,
            metadata=request.metadata,
            billing_mode={"type": "flexible"},
        )

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
        return self._map_subscription(sub)

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

        invoice = await self._stripe.v1.invoices.create_preview_async(
            params=create_params,
            options=opts,
        )
        return map_invoice_preview(invoice)
