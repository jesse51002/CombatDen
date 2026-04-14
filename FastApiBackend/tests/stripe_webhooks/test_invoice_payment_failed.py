"""Integration tests for the ``invoice.payment_failed`` handler.

Verifies that a failed renewal:
  - upserts a ``user_gym_invoices`` row with ``status='open'``
  - inserts a ``user_gym_charges`` row with
    ``kind='payment', status='failed'`` and null ``stripe_charge_id``
  - does NOT touch ``member_memberships.last_paid_date`` /
    ``next_due_date`` (Stripe handles dunning, not us)
"""

from sqlalchemy import text

from tests.stripe_webhooks.event_builders import make_invoice_payment_failed_event


async def _fetch_invoice(db_pool, stripe_invoice_id: str) -> dict | None:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT status, total_amount, currency, crm_user_id "
                "FROM user_gym_invoices "
                "WHERE stripe_invoice_id = :id"
            ),
            {"id": stripe_invoice_id},
        )
        row = result.mappings().fetchone()
    return dict(row) if row else None


async def _fetch_failed_charges(db_pool, gym_id) -> list[dict]:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT kind, status, amount, currency, "
                "stripe_charge_id, crm_user_id "
                "FROM user_gym_charges "
                "WHERE gym_id = :gym_id AND status = 'failed' "
                "ORDER BY charge_time"
            ),
            {"gym_id": str(gym_id)},
        )
        rows = result.mappings().fetchall()
    return [dict(r) for r in rows]


async def _fetch_membership_dates(db_pool, item_id) -> dict | None:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT last_paid_date, next_due_date "
                "FROM member_memberships_unfiltered "
                "WHERE item_id = :id"
            ),
            {"id": str(item_id)},
        )
        row = result.mappings().fetchone()
    return dict(row) if row else None


async def test_invoice_payment_failed_writes_failed_charge(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    event = make_invoice_payment_failed_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        amount_due=5000,
    )

    await stripe_webhooks_service.handle_event(event)

    # Invoice upserted with status='open'.
    invoice = await _fetch_invoice(db_pool, event["data"]["object"]["id"])
    assert invoice is not None
    assert invoice["status"] == "open"
    assert invoice["total_amount"] == 5000
    assert str(invoice["crm_user_id"]) == str(webhook_fixture.crm_user_id)

    # One failed charge row with null stripe_charge_id.
    charges = await _fetch_failed_charges(db_pool, gym_id)
    assert len(charges) == 1
    charge = charges[0]
    assert charge["kind"] == "payment"
    assert charge["status"] == "failed"
    assert charge["amount"] == 5000
    assert charge["currency"] == "usd"
    assert charge["stripe_charge_id"] is None
    assert str(charge["crm_user_id"]) == str(webhook_fixture.crm_user_id)


async def test_invoice_payment_failed_does_not_touch_membership_dates(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    """Failed payments must NOT advance (or backfill) payment dates.

    The fixture starts with both dates NULL (from the autouse reset).
    After a failed payment, they must still be NULL.
    """
    event = make_invoice_payment_failed_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        amount_due=5000,
    )

    await stripe_webhooks_service.handle_event(event)

    dates = await _fetch_membership_dates(db_pool, webhook_fixture.item_id)
    assert dates is not None
    assert dates["last_paid_date"] is None
    assert dates["next_due_date"] is None


async def test_invoice_payment_failed_skips_when_no_matching_membership(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,  # gym must exist
):
    """An unknown subscription_item must not explode — just skip."""
    event = make_invoice_payment_failed_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=["si_test_unknown_failed_1"],
        amount_due=5000,
    )

    await stripe_webhooks_service.handle_event(event)

    # No invoice row — we never resolved a crm_user_id.
    invoice = await _fetch_invoice(db_pool, event["data"]["object"]["id"])
    assert invoice is None

    # No charge rows at all.
    charges = await _fetch_failed_charges(db_pool, gym_id)
    assert charges == []

    # But the event IS logged, so Stripe retries are deduped.
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT COUNT(*) AS n FROM stripe_webhook_events "
                "WHERE event_id = :id"
            ),
            {"id": event["id"]},
        )
        row = result.mappings().fetchone()
    assert int(row["n"]) == 1


async def test_invoice_payment_failed_is_idempotent_on_repeat(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    """Duplicate deliveries of the same failed-payment event must not
    produce duplicate failed charge rows."""
    event = make_invoice_payment_failed_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        amount_due=5000,
    )

    await stripe_webhooks_service.handle_event(event)
    await stripe_webhooks_service.handle_event(event)
    await stripe_webhooks_service.handle_event(event)

    charges = await _fetch_failed_charges(db_pool, gym_id)
    assert len(charges) == 1


async def test_invoice_payment_failed_then_new_attempt_creates_separate_row(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    """Two distinct Stripe retry attempts (different event ids, same
    invoice) should each produce a failed charge row — the CRM wants
    to see every attempt."""
    evt_1 = make_invoice_payment_failed_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        amount_due=5000,
        stripe_invoice_id="in_test_failed_retry",
    )
    evt_2 = make_invoice_payment_failed_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        amount_due=5000,
        stripe_invoice_id="in_test_failed_retry",
    )
    # Different event ids; same invoice.
    assert evt_1["id"] != evt_2["id"]

    await stripe_webhooks_service.handle_event(evt_1)
    await stripe_webhooks_service.handle_event(evt_2)

    charges = await _fetch_failed_charges(db_pool, gym_id)
    assert len(charges) == 2

    # Exactly one invoice row — upsert collapsed both events.
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT COUNT(*) AS n FROM user_gym_invoices "
                "WHERE stripe_invoice_id = :id"
            ),
            {"id": "in_test_failed_retry"},
        )
        row = result.mappings().fetchone()
    assert int(row["n"]) == 1
