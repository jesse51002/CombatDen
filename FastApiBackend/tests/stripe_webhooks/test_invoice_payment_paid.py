"""Integration tests for the ``invoice_payment.paid`` handler.

This handler is the CRM's charge recorder. Verifies that a payment against a
recorded invoice:
  - inserts a ``member_charges`` ``payment`` row (``status='succeeded'``)
  - resolves the Stripe charge id from the payment's PaymentIntent
    (``latest_charge``) for card/bank, or records cash for out-of-band
  - attributes the charge to the invoice's member
  - retries (raises) when the invoice row isn't recorded yet
  - is idempotent on replay

The PaymentIntent retrieve is faked in these tests (``FakePaymentsStripeClient``
→ ``fake_charge_id_for``); the live E2E exercises the real Stripe retrieve.
"""

import pytest
from sqlalchemy import text

from src.stripe_webhooks.stripe_webhooks_exceptions import (
    InvoiceNotYetRecordedError,
)
from tests.stripe_webhooks.conftest import fake_charge_id_for
from tests.stripe_webhooks.event_builders import (
    make_invoice_paid_event,
    make_invoice_payment_paid_event,
)


async def _record_invoice(
    stripe_webhooks_service,
    stripe_account_id: str,
    webhook_fixture,
    *,
    stripe_invoice_id: str,
    amount: int = 5000,
) -> None:
    """Dispatch invoice.paid so the member_invoices row exists first."""
    await stripe_webhooks_service.handle_event(
        make_invoice_paid_event(
            stripe_account_id=stripe_account_id,
            stripe_item_ids=[webhook_fixture.stripe_item_id],
            amount_paid=amount,
            stripe_invoice_id=stripe_invoice_id,
        )
    )


async def _fetch_charge_for_invoice(db_pool, stripe_invoice_id: str) -> dict | None:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT kind, status, amount, currency, member_id, "
                "payment_method_type, stripe_charge_id "
                "FROM member_charges "
                "WHERE invoice_id = ("
                "  SELECT invoice_id FROM member_invoices "
                "  WHERE stripe_invoice_id = :id"
                ")"
            ),
            {"id": stripe_invoice_id},
        )
        row = result.mappings().fetchone()
    return dict(row) if row else None


async def _count_charges_for_invoice(db_pool, stripe_invoice_id: str) -> int:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT COUNT(*) AS n FROM member_charges "
                "WHERE invoice_id = ("
                "  SELECT invoice_id FROM member_invoices "
                "  WHERE stripe_invoice_id = :id"
                ")"
            ),
            {"id": stripe_invoice_id},
        )
        row = result.mappings().fetchone()
    return int(row["n"])


async def test_card_payment_records_succeeded_charge(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    sid = "in_test_inpay_card_1"
    pi = "pi_test_inpay_card_1"
    await _record_invoice(
        stripe_webhooks_service, stripe_account_id, webhook_fixture,
        stripe_invoice_id=sid, amount=5000,
    )

    await stripe_webhooks_service.handle_event(
        make_invoice_payment_paid_event(
            stripe_account_id=stripe_account_id,
            stripe_invoice_id=sid,
            amount_paid=5000,
            payment_intent_id=pi,
        )
    )

    charge = await _fetch_charge_for_invoice(db_pool, sid)
    assert charge is not None
    assert charge["kind"] == "payment"
    assert charge["status"] == "succeeded"
    assert charge["amount"] == 5000
    assert charge["currency"] == "usd"
    assert charge["payment_method_type"] is None
    assert charge["stripe_charge_id"] == fake_charge_id_for(pi)
    assert str(charge["member_id"]) == str(webhook_fixture.member_id)


async def test_out_of_band_payment_records_cash_charge(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    sid = "in_test_inpay_cash_1"
    await _record_invoice(
        stripe_webhooks_service, stripe_account_id, webhook_fixture,
        stripe_invoice_id=sid, amount=4200,
    )

    await stripe_webhooks_service.handle_event(
        make_invoice_payment_paid_event(
            stripe_account_id=stripe_account_id,
            stripe_invoice_id=sid,
            amount_paid=4200,
            payment_type="out_of_band",
        )
    )

    charge = await _fetch_charge_for_invoice(db_pool, sid)
    assert charge is not None
    assert charge["kind"] == "payment"
    assert charge["status"] == "succeeded"
    assert charge["amount"] == 4200
    assert charge["payment_method_type"] == "cash"
    assert charge["stripe_charge_id"] is None


async def test_payment_before_invoice_recorded_raises_for_retry(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    """If the invoice row isn't recorded yet, raise so the router retries.

    Nothing is written (the transaction rolls back), so the event is not
    logged either — a later retry can succeed once invoice.paid lands.
    """
    sid = "in_test_inpay_orphan_1"
    event = make_invoice_payment_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_invoice_id=sid,
        amount_paid=5000,
        payment_intent_id="pi_test_inpay_orphan_1",
    )

    with pytest.raises(InvoiceNotYetRecordedError):
        await stripe_webhooks_service.handle_event(event)

    assert await _count_charges_for_invoice(db_pool, sid) == 0

    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT COUNT(*) AS n FROM stripe_webhook_events WHERE event_id = :id"),
            {"id": event["id"]},
        )
        row = result.mappings().fetchone()
    assert int(row["n"]) == 0


async def test_payment_paid_is_idempotent_on_repeat(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    sid = "in_test_inpay_idem_1"
    await _record_invoice(
        stripe_webhooks_service, stripe_account_id, webhook_fixture,
        stripe_invoice_id=sid,
    )
    event = make_invoice_payment_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_invoice_id=sid,
        amount_paid=5000,
        payment_intent_id="pi_test_inpay_idem_1",
    )

    await stripe_webhooks_service.handle_event(event)
    await stripe_webhooks_service.handle_event(event)
    await stripe_webhooks_service.handle_event(event)

    assert await _count_charges_for_invoice(db_pool, sid) == 1
