from datetime import datetime
from typing import Literal
from zoneinfo import ZoneInfo

import stripe
from dateutil.relativedelta import relativedelta
from schema.membership_plan import DurationUnit
from stripe.params._invoice_create_preview_params import (
    InvoiceCreatePreviewParams,
)
from stripe.params._invoice_pay_params import InvoicePayParams
from stripe.params._invoice_update_params import InvoiceUpdateParams
from stripe.params._subscription_create_params import (
    SubscriptionCreateParams,
)

import src.shared.db_schema_path  # noqa: F401
from src.core.config import MONTHLY_BILLING_ANCHOR_DAY
from src.payments.schema.metadata.stripe_subscription_metadata import (
    StripeSubscriptionMetadata,
)
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
        *,
        for_preview: bool,
    ) -> tuple[SubscriptionCreateParams, stripe.RequestOptions]:
        """Validate, consolidate, and build all params for create.

        ``for_preview=True`` returns read-only opts because preview does
        not mutate Stripe. Writes use the request's idempotency key.
        """
        if for_preview:
            opts = self._client.connect_opts_readonly(stripe_account_id)
        else:
            opts = self._client.connect_opts(
                stripe_account_id, idempotency_key=request.idempotency_key
            )

        recurring_interval = await self._validate_subscription_request(
            request,
            stripe_account_id,
        )
        customer = await self._members.retrieve_customer(
            request.stripe_customer_id,
            opts,
        )

        consolidated = self._consolidate_items(request.items)
        items = self._build_create_items(consolidated)

        proration_behavior: Literal["none", "always_invoice"] = (
            request.proration_behavior
        )

        create_params = SubscriptionCreateParams(
            customer=request.stripe_customer_id,
            items=items,
            metadata=request.metadata.to_stripe_metadata(),
            proration_behavior=proration_behavior,
        )

        if request.pay_first_invoice_out_of_band and proration_behavior == "always_invoice":
            create_params["payment_behavior"] = "default_incomplete"
            create_params["expand"] = ["latest_invoice"]

        if recurring_interval == DurationUnit.month:
            create_params["billing_cycle_anchor"] = await self._next_monthly_anchor_timestamp(
                request.gym_timezone,
                customer,
                opts,
            )

        return create_params, opts

    async def _next_monthly_anchor_timestamp(
        self,
        gym_timezone: str,
        customer: stripe.Customer,
        opts: stripe.RequestOptions,
    ) -> int:
        """Next MONTHLY_BILLING_ANCHOR_DAY as a unix timestamp.

        Pins the next anchor to midnight of MONTHLY_BILLING_ANCHOR_DAY in
        the gym's configured timezone. We pass this explicit timestamp on
        both the real subscription create AND the invoice preview so the
        two paths share identical proration inputs. Stripe's
        ``billing_cycle_anchor_config.day_of_month`` uses its own
        day-precision math that the preview API cannot replicate (it only
        accepts a timestamp), which produced ~1% drift between preview
        totals and the real first invoice.

        If the customer is attached to a Stripe test clock, "now" is the
        clock's ``frozen_time``; otherwise real wall-clock time. Without
        this, test-clocked customers in the past would get an anchor
        beyond Stripe's next natural billing date and fail.
        """
        now = await self._customer_now(customer, gym_timezone, opts)
        candidate = now.replace(
            day=MONTHLY_BILLING_ANCHOR_DAY,
            hour=0,
            minute=0,
            second=0,
            microsecond=0,
        )
        if candidate <= now:
            candidate = candidate + relativedelta(months=1)
        return int(candidate.timestamp())

    async def _customer_now(
        self,
        customer: stripe.Customer,
        gym_timezone: str,
        opts: stripe.RequestOptions,
    ) -> datetime:
        """Return the customer's current time, honoring test clocks."""
        tz = ZoneInfo(gym_timezone)
        test_clock_id = getattr(customer, "test_clock", None)
        if not test_clock_id:
            return datetime.now(tz)
        clock = await self._stripe.v1.test_helpers.test_clocks.retrieve_async(
            test_clock_id,
            options=opts,
        )
        return datetime.fromtimestamp(clock.frozen_time, tz=tz)

    async def create_subscription(
        self,
        request: PaymentsSubscriptionCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse:
        """Create a new subscription with flexible billing mode."""
        create_params, opts = await self._build_create_params(
            request, stripe_account_id, for_preview=False
        )

        sub = await self._stripe.v1.subscriptions.create_async(
            params=create_params,
            options=opts,
        )

        if (
            request.pay_first_invoice_out_of_band
            and create_params.get("proration_behavior") == "always_invoice"
        ):
            sub = await self._pay_first_invoice_out_of_band(
                sub,
                stripe_account_id,
                idempotency_key=request.idempotency_key,
                metadata=request.metadata,
            )

        return self._map_subscription(sub)

    async def _pay_first_invoice_out_of_band(
        self,
        sub: stripe.Subscription,
        stripe_account_id: str,
        *,
        idempotency_key: str,
        metadata: StripeSubscriptionMetadata,
    ) -> stripe.Subscription:
        """Mark the subscription's first invoice as paid out of band.

        The subscription was created with
        ``payment_behavior='default_incomplete'``, so its first
        invoice is ``open`` and the sub is ``incomplete``. Paying
        the invoice out of band activates the subscription without
        charging the customer's card.
        """
        read_opts = self._client.connect_opts_readonly(stripe_account_id)
        tag_opts = self._client.connect_opts(
            stripe_account_id, idempotency_key=f"{idempotency_key}:invoice:tag"
        )
        pay_opts = self._client.connect_opts(
            stripe_account_id, idempotency_key=f"{idempotency_key}:invoice:pay"
        )

        invoice_id = await self._resolve_first_invoice_id(sub, read_opts)

        cash_metadata = metadata.model_copy(
            update={"crm_paid_with_cash": True},
        )

        await self._stripe.v1.invoices.update_async(
            invoice_id,
            params=InvoiceUpdateParams(
                metadata=cash_metadata.to_stripe_metadata(),
            ),
            options=tag_opts,
        )

        pay_params = InvoicePayParams()
        pay_params["paid_out_of_band"] = True
        await self._stripe.v1.invoices.pay_async(
            invoice_id,
            params=pay_params,
            options=pay_opts,
        )

        return await self._stripe.v1.subscriptions.retrieve_async(
            sub.id,
            options=read_opts,
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
        """Preview the first invoice for a new subscription."""
        create_params, opts = await self._build_create_params(
            request, stripe_account_id, for_preview=True
        )

        subscription_details: dict = {
            "items": create_params.get("items", []),
            "proration_behavior": create_params["proration_behavior"],
        }
        if "billing_cycle_anchor" in create_params:
            subscription_details["billing_cycle_anchor"] = create_params["billing_cycle_anchor"]

        preview_params = InvoiceCreatePreviewParams(
            customer=request.stripe_customer_id,
            subscription_details=subscription_details,
        )
        discounts = create_params.get("discounts")
        if discounts:
            preview_params["discounts"] = discounts

        invoice = await self._stripe.v1.invoices.create_preview_async(
            params=preview_params,
            options=opts,
        )
        return map_invoice_preview(invoice)
