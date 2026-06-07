"""Real-Stripe regression guard for the webhook capture's ``expand`` paths.

The webhook handlers are unit-tested with a fake Stripe client; this test hits
the REAL Stripe test account once and runs the **production parsers** against
the real responses. Both captures are best-effort, so a silent Stripe shape
change (like the dahlia ``discount.coupon`` -> ``discount.source.coupon`` move)
would make them write *nothing* rather than error — this turns that into a loud
failure.

  * Discount audit — ``InvoicePaidHandler._discount_coupon_id`` must resolve a
    real expanded Discount to its coupon id.
  * Card last 4 — ``InvoicePaymentPaidHandler._read_charge_details`` must read
    ``(charge_id, 'card', last4)`` from a real expanded PaymentIntent charge.
"""

from src.stripe_webhooks.service.invoice_paid_handler import (
    InvoicePaidHandler,
)
from src.stripe_webhooks.service.invoice_payment_paid_handler import (
    InvoicePaymentPaidHandler,
)

CARD_AMOUNT = 5000
COUPON_PERCENT_OFF = 30


async def test_invoice_discount_and_charge_expand_shapes(
    stripe_client,
    connect_opts,
    created,
):
    client = stripe_client.client

    # Card on file (Visa 4242) + a customer that pays with it.
    pm = await created.payment_method()
    customer = await client.v1.customers.create_async(
        params={
            "payment_method": pm,
            "invoice_settings": {"default_payment_method": pm},
        },
        options=connect_opts,
    )
    created.track_customer(customer.id)

    # A coupon (auto id, so reruns never collide) + a discounted invoice.
    coupon = await client.v1.coupons.create_async(
        params={"percent_off": COUPON_PERCENT_OFF, "duration": "forever"},
        options=connect_opts,
    )
    created.track_coupon(coupon.id)

    # Create the draft invoice first, then attach a line item to it, so the
    # invoice actually has an amount due (and therefore a charge to inspect).
    invoice = await client.v1.invoices.create_async(
        params={
            "customer": customer.id,
            "collection_method": "charge_automatically",
            "auto_advance": False,
            "discounts": [{"coupon": coupon.id}],
        },
        options=connect_opts,
    )
    await client.v1.invoice_items.create_async(
        params={
            "customer": customer.id,
            "invoice": invoice.id,
            "amount": CARD_AMOUNT,
            "currency": "usd",
        },
        options=connect_opts,
    )
    invoice = await client.v1.invoices.finalize_invoice_async(
        invoice.id, options=connect_opts
    )
    # charge_automatically + a default PM pays on finalize; pay explicitly only
    # if it didn't, so the invoice ends up with a charge for the last-4 check.
    if invoice.status != "paid":
        invoice = await client.v1.invoices.pay_async(
            invoice.id, options=connect_opts
        )
    assert invoice.status == "paid"

    # ── Discount: the production parser must resolve real Stripe -> coupon ──
    retrieved = await client.v1.invoices.retrieve_async(
        invoice.id,
        params={"expand": ["discounts"]},
        options=connect_opts,
    )
    coupon_ids = {
        InvoicePaidHandler._discount_coupon_id(d)  # noqa: SLF001
        for d in retrieved.discounts
    }
    assert coupon.id in coupon_ids, (
        "production discount parser failed to read the coupon from a real "
        f"Stripe Discount (got {coupon_ids})"
    )
    di_ids = {d.id for d in retrieved.discounts}
    assert retrieved.total_discount_amounts, "expected a discounted line"
    for entry in retrieved.total_discount_amounts:
        # The capture maps total_discount_amounts[].discount (a di_) -> coupon
        # and stores entry.amount as amount_off — assert that shape (the value
        # is a subscription-billing concern covered by the unit tests).
        assert entry.discount in di_ids
        assert isinstance(entry.amount, int)

    # ── Card last 4: the production parser must read method + last4 ──
    # The charge carries payment_method_details directly — the same object the
    # handler reads off the PaymentIntent's expanded latest_charge.
    charges = await client.v1.charges.list_async(
        params={"customer": customer.id},
        options=connect_opts,
    )
    assert charges.data, "expected a charge for the paid invoice"
    handler = InvoicePaymentPaidHandler.__new__(InvoicePaymentPaidHandler)
    charge_id, method_type, last4 = handler._read_charge_details(  # noqa: SLF001
        charges.data[0]
    )
    assert method_type == "card"
    assert last4 == "4242"
    assert charge_id and str(charge_id).startswith("ch_")
