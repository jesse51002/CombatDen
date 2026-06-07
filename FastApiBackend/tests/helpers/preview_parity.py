"""Assert that a preview's totals match the actual Stripe invoice that
was cut (or will be cut at the next renewal) for the same operation.

Standalone module — no pytest imports, no fixture dependencies.

Typical flow for an immediate-billing op (e.g. start, prorate=True
update_price, one-time charge):

    before = await snapshot_billing_state(stripe_client, customer_id, opts)
    preview = await service.preview_X(...)
    await service.X(...)
    invoice = await assert_immediate_prorated_invoice(
        stripe_client, before, opts, subscription_id=sub_id, min_amount=0,
    )
    assert_preview_matches_invoice(preview, invoice)

Typical flow for a next-cycle op (e.g. prorate=False update_price,
cancel-from-multi, discount change, link/unlink):

    preview = await service.preview_X(...)
    await service.X(...)
    before = await snapshot_billing_state(stripe_client, customer_id, opts)
    invoice = await advance_to_next_cycle_and_fetch_invoice(
        stripe_client, clock_id, NEXT_CYCLE, sub_id, before, opts,
    )
    assert_preview_matches_invoice(preview, invoice)
"""

from __future__ import annotations

import stripe

from src.payments.schema.payments_invoice_schema import PreviewInvoice
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from tests.helpers.stripe_assertions import BillingSnapshot


def assert_preview_matches_invoice(
    preview: PreviewInvoice,
    invoice: stripe.Invoice,
) -> None:
    """Assert preview totals equal the realised invoice totals.

    Compares ``amount_due``, ``subtotal``, ``total``, and ``currency``.
    Stripe's preview API and finalised invoice math are deterministic,
    so exact equality is the right bar — any drift means the preview
    code path and the real code path are computing the bill from
    different inputs.

    Raises:
        AssertionError with a labelled diff for the first field that
        does not match.
    """
    diffs: list[str] = []
    if preview.amount_due != invoice.amount_due:
        diffs.append(f"amount_due: preview={preview.amount_due} invoice={invoice.amount_due}")
    if preview.subtotal != invoice.subtotal:
        diffs.append(f"subtotal: preview={preview.subtotal} invoice={invoice.subtotal}")
    if preview.total != invoice.total:
        diffs.append(f"total: preview={preview.total} invoice={invoice.total}")
    if preview.currency.lower() != invoice.currency.lower():
        diffs.append(f"currency: preview={preview.currency} invoice={invoice.currency}")
    assert not diffs, (
        f"Preview vs invoice {invoice.id} mismatch — "
        f"preview path and real billing path disagree:\n  " + "\n  ".join(diffs)
    )


async def fetch_only_new_invoice(
    stripe_client: PaymentsStripeClient,
    before: BillingSnapshot,
    connect_opts: stripe.RequestOptions,
) -> stripe.Invoice:
    """Return the single new invoice for ``before.customer_id``.

    Counterpart of :func:`assert_immediate_prorated_invoice` for
    one-time charges that are not tied to a subscription. Asserts
    exactly one new invoice id appeared since the snapshot, then
    fetches and returns it.

    Raises:
        AssertionError: If zero or more than one new invoice exists.
    """
    invoices = await stripe_client.client.v1.invoices.list_async(
        params={"customer": before.customer_id, "limit": 100},
        options=connect_opts,
    )
    new_ids = [inv.id for inv in invoices.data if inv.id not in before.invoice_ids]
    assert len(new_ids) == 1, (
        f"Expected exactly one new invoice for customer "
        f"{before.customer_id}, got {sorted(new_ids)}"
    )
    return await stripe_client.client.v1.invoices.retrieve_async(
        new_ids[0],
        options=connect_opts,
    )
