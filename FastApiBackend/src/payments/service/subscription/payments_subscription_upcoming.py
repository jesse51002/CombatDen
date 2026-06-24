"""Fetch the upcoming (preview) invoice for an existing subscription."""

import logging

import stripe
from stripe.params._invoice_create_preview_params import (
    InvoiceCreatePreviewParams,
)

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_invoice_schema import PreviewInvoice
from src.payments.service.payments_stripe_mappers import map_preview_invoice
from src.payments.service.subscription.payments_subscription_base import (
    PaymentsSubscriptionBase,
)

logger = logging.getLogger(__name__)


class PaymentsSubscriptionUpcoming(PaymentsSubscriptionBase):
    """Retrieve the next invoice preview for an existing subscription."""

    async def fetch_upcoming(
        self,
        stripe_subscription_id: str,
        stripe_account_id: str,
    ) -> PreviewInvoice:
        """Fetch the next (upcoming) invoice preview for a subscription.

        This uses ``invoices.create_preview`` with the existing
        ``subscription`` argument so Stripe returns the actual
        post-discount line items that will be billed next cycle.

        Args:
            stripe_subscription_id: The live Stripe subscription ID.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Upcoming invoice with per-subscription-item post-discount
            totals and the overall ``amount_due``.

        Raises:
            PaymentsResourceNotFoundError: If the subscription cannot
                be previewed (deleted, invalid, no upcoming invoice).
        """
        opts = self._client.connect_opts_readonly(stripe_account_id)

        try:
            invoice = await self._stripe.v1.invoices.create_preview_async(
                params=InvoiceCreatePreviewParams(
                    subscription=stripe_subscription_id,
                ),
                options=opts,
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsResourceNotFoundError(
                f"Upcoming invoice not found for subscription {stripe_subscription_id}",
                resource_id=stripe_subscription_id,
                resource_type=StripeResourceType.subscription,
            ) from exc

        preview = map_preview_invoice(invoice)
        # Keep only the steady-state recurring sub-item lines (drop
        # prorations / one-offs) so the upcoming view reflects the next
        # full cycle, not a one-time adjustment.
        recurring_lines = [
            line
            for line in preview.lines
            if not line.is_proration and line.stripe_subscription_item_id
        ]
        return PreviewInvoice(
            amount_due=preview.amount_due,
            subtotal=preview.subtotal,
            total=preview.total,
            currency=preview.currency,
            lines=recurring_lines,
        )

    async def upcoming_applied_coupon_ids(
        self,
        stripe_subscription_id: str,
        stripe_account_id: str,
    ) -> set[str]:
        """Coupon ids ACTUALLY APPLIED on the subscription's next invoice.

        The authoritative consumed-vs-pending signal for a ``once`` discount:
        Stripe will not re-apply a redeemed ``once``, so a ``once`` coupon
        attached to the sub but ABSENT from the next invoice's applied discounts
        has been consumed — **even though its discount object lingers on the
        item** (it does whenever another discount coexists, so the
        coupon-still-attached check misreads it as pending). Reads
        ``invoices.create_preview`` and resolves each applied discount to its
        coupon (handling the dahlia ``discount.source.coupon`` shape).

        Returns an empty set when there is no upcoming invoice (the subscription
        is deleted / has no next cycle), so an idle or cancelled sub's ``once``
        discounts settle as done.
        """
        opts = self._client.connect_opts_readonly(stripe_account_id)
        try:
            invoice = await self._stripe.v1.invoices.create_preview_async(
                params={
                    "subscription": stripe_subscription_id,
                    "expand": [
                        "lines.data.discount_amounts.discount",
                        "total_discount_amounts.discount",
                    ],
                },
                options=opts,
            )
        except stripe.InvalidRequestError:
            return set()

        coupon_ids: set[str] = set()
        for amount in getattr(invoice, "total_discount_amounts", None) or []:
            cid = self._coupon_id_from_discount(amount.discount)
            if cid is not None:
                coupon_ids.add(cid)
        for line in invoice.lines.data:
            for amount in getattr(line, "discount_amounts", None) or []:
                cid = self._coupon_id_from_discount(amount.discount)
                if cid is not None:
                    coupon_ids.add(cid)
        return coupon_ids
