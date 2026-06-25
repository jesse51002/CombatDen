"""Integration tests for the ``invoice.paid`` discount-audit capture.

The handler retrieves the invoice with the coupon expanded (the webhook sends
only opaque ``di_`` ids) and captures ``{amount_off, stripe_coupon_id}`` per
discount into ``member_invoice_applied_discounts`` — no CRM-discount link. The
capture is best-effort (a SAVEPOINT), so a capture failure never rolls back the
invoice.
"""

from sqlalchemy import text

from tests.stripe_webhooks.conftest import FAKE_INVOICE_DISCOUNTS
from tests.stripe_webhooks.event_builders import make_invoice_paid_event


async def _audit_rows(db_pool, stripe_invoice_id: str) -> list[dict]:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT amount_off, stripe_coupon_id, discount_id "
                "FROM member_invoice_applied_discounts "
                "WHERE invoice_id = ("
                "  SELECT invoice_id FROM member_invoices "
                "  WHERE stripe_invoice_id = :id"
                ") ORDER BY amount_off"
            ),
            {"id": stripe_invoice_id},
        )
        return [dict(r) for r in result.mappings().fetchall()]


async def _invoice_exists(db_pool, stripe_invoice_id: str) -> bool:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT 1 FROM member_invoices WHERE stripe_invoice_id = :id"
            ),
            {"id": stripe_invoice_id},
        )
        return result.first() is not None


async def test_capture_writes_one_row_per_discount(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    sid = "in_test_disc_capture_1"
    FAKE_INVOICE_DISCOUNTS[sid] = [
        ("di_a", "pct_3000"),
        ("di_b", "amt_500"),
    ]
    try:
        event = make_invoice_paid_event(
            stripe_account_id=stripe_account_id,
            stripe_item_ids=[webhook_fixture.stripe_item_id],
            amount_paid=10000,
            stripe_invoice_id=sid,
            total_discount_amounts=[
                {"amount": 3000, "discount": "di_a"},
                {"amount": 500, "discount": "di_b"},
            ],
        )
        await stripe_webhooks_service.handle_event(event)
    finally:
        FAKE_INVOICE_DISCOUNTS.pop(sid, None)

    rows = await _audit_rows(db_pool, sid)
    assert len(rows) == 2
    assert {r["stripe_coupon_id"] for r in rows} == {
        "pct_3000",
        "amt_500",
    }
    by_coupon = {r["stripe_coupon_id"]: r for r in rows}
    assert by_coupon["pct_3000"]["amount_off"] == 3000
    assert by_coupon["amt_500"]["amount_off"] == 500
    # Coupon-only: no CRM discount link.
    assert all(r["discount_id"] is None for r in rows)


async def test_capture_is_idempotent_on_replay(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    sid = "in_test_disc_capture_idem_1"
    FAKE_INVOICE_DISCOUNTS[sid] = [("di_a", "pct_2000")]
    try:
        event = make_invoice_paid_event(
            stripe_account_id=stripe_account_id,
            stripe_item_ids=[webhook_fixture.stripe_item_id],
            stripe_invoice_id=sid,
            total_discount_amounts=[{"amount": 1000, "discount": "di_a"}],
        )
        # Same event delivered twice — event-log dedup + unique(invoice,coupon).
        await stripe_webhooks_service.handle_event(event)
        await stripe_webhooks_service.handle_event(event)
    finally:
        FAKE_INVOICE_DISCOUNTS.pop(sid, None)

    rows = await _audit_rows(db_pool, sid)
    assert len(rows) == 1
    assert rows[0]["amount_off"] == 1000


async def test_no_discounts_writes_no_rows_but_records_invoice(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    sid = "in_test_disc_capture_none_1"
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        stripe_invoice_id=sid,
        # No total_discount_amounts → capture is a no-op (no Stripe retrieve).
    )
    await stripe_webhooks_service.handle_event(event)

    assert await _invoice_exists(db_pool, sid)
    assert await _audit_rows(db_pool, sid) == []


async def test_unresolved_coupon_skips_row_invoice_still_recorded(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    """A discount whose di_ doesn't resolve to a coupon is skipped; the invoice
    is still recorded (best-effort capture)."""
    sid = "in_test_disc_capture_unresolved_1"
    # The retrieve returns no discounts for this invoice → di_x unresolved.
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        stripe_invoice_id=sid,
        total_discount_amounts=[{"amount": 750, "discount": "di_x"}],
    )
    await stripe_webhooks_service.handle_event(event)

    assert await _invoice_exists(db_pool, sid)
    assert await _audit_rows(db_pool, sid) == []
