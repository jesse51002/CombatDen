"""Integration tests for the ``charge.refunded`` handler.

Verifies that a refund:
  - finds the parent ``member_charges`` row via ``stripe_charge_id``
  - inserts one ``kind='refund'`` row per entry in
    ``refunds.data``, with a **negative** amount
  - links the refund back to the parent payment via
    ``refunds_charge_id``
  - is idempotent on replay (``stripe_refund_id`` UNIQUE)

Refunds arriving for an unknown charge are logged and acked — we
can't fabricate a parent, and a 5xx would just loop Stripe retries.
"""

from sqlalchemy import text

from tests.stripe_webhooks.event_builders import (
    make_charge_refunded_event,
    make_invoice_paid_event,
)


async def _seed_parent_payment(
    stripe_webhooks_service,
    stripe_account_id,
    webhook_fixture,
    stripe_charge_id: str,
    amount: int = 5000,
) -> None:
    """Run an ``invoice.paid`` event so a parent payment row exists."""
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        amount_paid=amount,
        stripe_charge_id=stripe_charge_id,
    )
    await stripe_webhooks_service.handle_event(event)


async def _fetch_refund_rows(db_pool, gym_id) -> list[dict]:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT charge_id, kind, status, amount, currency, "
                "stripe_refund_id, refunds_charge_id, member_id "
                "FROM member_charges "
                "WHERE gym_id = :gym_id AND kind = 'refund' "
                "ORDER BY charge_time"
            ),
            {"gym_id": str(gym_id)},
        )
        rows = result.mappings().fetchall()
    return [dict(r) for r in rows]


async def _fetch_parent_charge_id(db_pool, stripe_charge_id: str):
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT charge_id FROM member_charges "
                "WHERE stripe_charge_id = :id AND kind = 'payment'"
            ),
            {"id": stripe_charge_id},
        )
        row = result.mappings().fetchone()
    return row["charge_id"] if row else None


async def test_charge_refunded_single_full_refund(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    stripe_charge_id = "ch_test_refund_full_1"
    await _seed_parent_payment(
        stripe_webhooks_service,
        stripe_account_id,
        webhook_fixture,
        stripe_charge_id,
        amount=5000,
    )
    parent_charge_id = await _fetch_parent_charge_id(db_pool, stripe_charge_id)
    assert parent_charge_id is not None

    event = make_charge_refunded_event(
        stripe_account_id=stripe_account_id,
        stripe_charge_id=stripe_charge_id,
        refund_amounts=[5000],
    )

    await stripe_webhooks_service.handle_event(event)

    refunds = await _fetch_refund_rows(db_pool, gym_id)
    assert len(refunds) == 1
    r = refunds[0]
    assert r["kind"] == "refund"
    assert r["status"] == "succeeded"
    # Amount stored negative per schema convention.
    assert r["amount"] == -5000
    assert r["currency"] == "usd"
    assert r["stripe_refund_id"] is not None
    assert str(r["refunds_charge_id"]) == str(parent_charge_id)
    assert str(r["member_id"]) == str(webhook_fixture.member_id)


async def test_charge_refunded_multi_partial_refund(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    """A single ``charge.refunded`` event can carry multiple refunds.

    Each entry in ``refunds.data`` must produce its own row with its
    own ``stripe_refund_id``.
    """
    stripe_charge_id = "ch_test_refund_multi_1"
    await _seed_parent_payment(
        stripe_webhooks_service,
        stripe_account_id,
        webhook_fixture,
        stripe_charge_id,
        amount=5000,
    )
    parent_charge_id = await _fetch_parent_charge_id(db_pool, stripe_charge_id)

    event = make_charge_refunded_event(
        stripe_account_id=stripe_account_id,
        stripe_charge_id=stripe_charge_id,
        refund_amounts=[1500, 2500],
    )

    await stripe_webhooks_service.handle_event(event)

    refunds = await _fetch_refund_rows(db_pool, gym_id)
    assert len(refunds) == 2
    amounts = sorted(r["amount"] for r in refunds)
    assert amounts == [-2500, -1500]
    # All linked to the same parent.
    for r in refunds:
        assert str(r["refunds_charge_id"]) == str(parent_charge_id)
    # All have distinct stripe_refund_ids.
    refund_ids = {r["stripe_refund_id"] for r in refunds}
    assert len(refund_ids) == 2


async def test_charge_refunded_orphan_is_logged_and_acked(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    """A refund for a charge we never recorded cannot be persisted
    (``invoice_id`` is NOT NULL). The handler must log, ack, and
    NOT raise — raising would make Stripe retry forever.
    """
    event = make_charge_refunded_event(
        stripe_account_id=stripe_account_id,
        stripe_charge_id="ch_test_orphan_refund_1",
        refund_amounts=[1000],
    )

    # Must not raise.
    await stripe_webhooks_service.handle_event(event)

    refunds = await _fetch_refund_rows(db_pool, gym_id)
    assert refunds == []

    # Event log row exists — Stripe retries are short-circuited.
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT COUNT(*) AS n FROM stripe_webhook_events WHERE event_id = :id"),
            {"id": event["id"]},
        )
        row = result.mappings().fetchone()
    assert int(row["n"]) == 1


async def test_charge_refunded_is_idempotent_on_repeat(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    """The same refund event delivered three times must not produce
    duplicate refund rows — enforced by ``stripe_refund_id`` UNIQUE
    + the outer event-log dedup."""
    stripe_charge_id = "ch_test_refund_idem_1"
    await _seed_parent_payment(
        stripe_webhooks_service,
        stripe_account_id,
        webhook_fixture,
        stripe_charge_id,
    )

    event = make_charge_refunded_event(
        stripe_account_id=stripe_account_id,
        stripe_charge_id=stripe_charge_id,
        refund_amounts=[2500],
    )

    await stripe_webhooks_service.handle_event(event)
    await stripe_webhooks_service.handle_event(event)
    await stripe_webhooks_service.handle_event(event)

    refunds = await _fetch_refund_rows(db_pool, gym_id)
    assert len(refunds) == 1
    assert refunds[0]["amount"] == -2500


async def test_charge_refunded_does_not_touch_membership_dates(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    """Refunds must not rewind ``last_paid_date`` / ``next_due_date``.

    The gym can decide separately (via a CRM action) whether to freeze
    or cancel the membership; we don't do it automatically.
    """
    stripe_charge_id = "ch_test_refund_dates_1"
    await _seed_parent_payment(
        stripe_webhooks_service,
        stripe_account_id,
        webhook_fixture,
        stripe_charge_id,
    )

    # Snapshot dates after the paid event.
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT last_paid_date, next_due_date "
                "FROM member_memberships_unfiltered "
                "WHERE item_id = :id"
            ),
            {"id": str(webhook_fixture.item_id)},
        )
        before = dict(result.mappings().fetchone())

    event = make_charge_refunded_event(
        stripe_account_id=stripe_account_id,
        stripe_charge_id=stripe_charge_id,
        refund_amounts=[5000],
    )
    await stripe_webhooks_service.handle_event(event)

    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT last_paid_date, next_due_date "
                "FROM member_memberships_unfiltered "
                "WHERE item_id = :id"
            ),
            {"id": str(webhook_fixture.item_id)},
        )
        after = dict(result.mappings().fetchone())

    assert before == after
