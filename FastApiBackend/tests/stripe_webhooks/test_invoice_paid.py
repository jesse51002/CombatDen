"""Integration tests for the ``invoice.paid`` handler.

Verifies that a successful subscription renewal:
  - upserts a ``user_gym_invoices`` row to ``status='paid'``
  - updates ``member_memberships.last_paid_date`` / ``next_due_date``
  - inserts a ``user_gym_charges`` row with
    ``kind='payment', status='succeeded'``
"""

from datetime import UTC, datetime, timedelta

from sqlalchemy import text

from tests.stripe_webhooks.event_builders import make_invoice_paid_event


async def _fetch_invoice(db_pool, stripe_invoice_id: str) -> dict | None:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT status, total_amount, currency, crm_user_id, "
                "stripe_payment_intent_id "
                "FROM user_gym_invoices "
                "WHERE stripe_invoice_id = :id"
            ),
            {"id": stripe_invoice_id},
        )
        row = result.mappings().fetchone()
    return dict(row) if row else None


async def _fetch_charge(db_pool, stripe_charge_id: str) -> dict | None:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT kind, status, amount, currency "
                "FROM user_gym_charges "
                "WHERE stripe_charge_id = :id"
            ),
            {"id": stripe_charge_id},
        )
        row = result.mappings().fetchone()
    return dict(row) if row else None


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


async def test_invoice_paid_writes_invoice_charge_and_dates(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    paid_at = int(datetime(2026, 4, 1, 12, 0, tzinfo=UTC).timestamp())
    period_end = int(datetime(2026, 5, 1, 12, 0, tzinfo=UTC).timestamp())
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        amount_paid=5000,
        stripe_charge_id="ch_test_paid_happy_1",
        paid_at=paid_at,
        period_end=period_end,
    )

    await stripe_webhooks_service.handle_event(event)

    # Invoice upserted to paid
    invoice = await _fetch_invoice(db_pool, event["data"]["object"]["id"])
    assert invoice is not None
    assert invoice["status"] == "paid"
    assert invoice["total_amount"] == 5000
    assert invoice["currency"] == "usd"
    assert str(invoice["crm_user_id"]) == str(webhook_fixture.crm_user_id)
    assert invoice["stripe_payment_intent_id"] is not None

    # Charge row inserted
    charge = await _fetch_charge(db_pool, "ch_test_paid_happy_1")
    assert charge is not None
    assert charge["kind"] == "payment"
    assert charge["status"] == "succeeded"
    assert charge["amount"] == 5000
    assert charge["currency"] == "usd"

    # Membership dates advanced
    dates = await _fetch_membership_dates(db_pool, webhook_fixture.item_id)
    assert dates is not None
    assert dates["last_paid_date"] == datetime.fromtimestamp(paid_at, tz=UTC).date()
    assert dates["next_due_date"] == datetime.fromtimestamp(period_end, tz=UTC).date()


async def test_invoice_paid_skips_when_no_matching_membership(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,  # ensure the gym exists even though we don't match it
):
    """A line for an unknown subscription_item must not explode — just skip."""
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=["si_test_does_not_exist"],
        amount_paid=1000,
        stripe_charge_id="ch_test_unknown_item_1",
    )

    await stripe_webhooks_service.handle_event(event)

    # No invoice row created (we never resolved a crm_user_id).
    invoice = await _fetch_invoice(db_pool, event["data"]["object"]["id"])
    assert invoice is None

    # And no charge row.
    charge = await _fetch_charge(db_pool, "ch_test_unknown_item_1")
    assert charge is None

    # Webhook event IS still recorded (dedup).
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT COUNT(*) AS n FROM stripe_webhook_events WHERE event_id = :id"),
            {"id": event["id"]},
        )
        row = result.mappings().fetchone()
    assert int(row["n"]) == 1


async def test_invoice_paid_zero_amount_no_charge_row(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    """100%-off trial invoices have amount_paid=0 and no charge id.

    We should still upsert the invoice and advance membership dates,
    but NOT insert a charge row (the table constraint requires a
    charge id for payment rows).
    """
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        amount_paid=0,
        stripe_charge_id=None,
    )

    await stripe_webhooks_service.handle_event(event)

    invoice = await _fetch_invoice(db_pool, event["data"]["object"]["id"])
    assert invoice is not None
    assert invoice["status"] == "paid"
    assert invoice["total_amount"] == 0

    # No charge row.
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT COUNT(*) AS n FROM user_gym_charges "
                "WHERE invoice_id IN ("
                "  SELECT invoice_id FROM user_gym_invoices "
                "  WHERE stripe_invoice_id = :id"
                ")"
            ),
            {"id": event["data"]["object"]["id"]},
        )
        row = result.mappings().fetchone()
    assert int(row["n"]) == 0

    # Dates still advanced.
    dates = await _fetch_membership_dates(db_pool, webhook_fixture.item_id)
    assert dates["last_paid_date"] is not None
    assert dates["next_due_date"] is not None


async def test_invoice_paid_is_idempotent_on_repeat(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        amount_paid=5000,
        stripe_charge_id="ch_test_idempotent_1",
    )

    await stripe_webhooks_service.handle_event(event)
    await stripe_webhooks_service.handle_event(event)
    await stripe_webhooks_service.handle_event(event)

    # Exactly one invoice, one charge, one event row, regardless of replays.
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT "
                " (SELECT COUNT(*) FROM user_gym_invoices WHERE gym_id = :g) AS inv,"
                " (SELECT COUNT(*) FROM user_gym_charges WHERE gym_id = :g) AS chg,"
                " (SELECT COUNT(*) FROM stripe_webhook_events WHERE gym_id = :g) AS evt"
            ),
            {"g": str(gym_id)},
        )
        row = result.mappings().fetchone()
    assert int(row["inv"]) == 1
    assert int(row["chg"]) == 1
    assert int(row["evt"]) == 1


async def test_invoice_paid_advances_two_different_period_ends(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    stripe_client,
    connect_opts,
    gym_id,
    webhook_fixture,
):
    """Two events with different period_ends should update the
    membership to the latest value each time."""
    first_end = int(datetime(2026, 6, 1, tzinfo=UTC).timestamp())
    second_end = int(datetime(2026, 7, 1, tzinfo=UTC).timestamp())

    evt_1 = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        period_end=first_end,
        stripe_charge_id="ch_test_advance_1",
    )
    evt_2 = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        period_end=second_end,
        stripe_charge_id="ch_test_advance_2",
    )

    await stripe_webhooks_service.handle_event(evt_1)
    dates_1 = await _fetch_membership_dates(db_pool, webhook_fixture.item_id)
    assert dates_1["next_due_date"] == datetime.fromtimestamp(first_end, tz=UTC).date()

    await stripe_webhooks_service.handle_event(evt_2)
    dates_2 = await _fetch_membership_dates(db_pool, webhook_fixture.item_id)
    assert dates_2["next_due_date"] == datetime.fromtimestamp(second_end, tz=UTC).date()

    # Proximity sanity — the delta is roughly a month.
    assert dates_2["next_due_date"] - dates_1["next_due_date"] >= timedelta(days=28)
