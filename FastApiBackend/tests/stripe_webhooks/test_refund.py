"""Integration tests for the ``refund.created`` / ``refund.updated`` handler.

Stripe's "dahlia" generation dropped the refunds list from the charge object,
so refunds arrive as their own ``refund.*`` events. Verifies that a succeeded
refund:
  - finds the parent ``member_charges`` payment row via ``refund.charge``
  - inserts a ``kind='refund'`` row with a **negative** amount, linked to the
    parent via ``refunds_charge_id``
  - records on whichever event first shows ``status='succeeded'`` and is
    idempotent across refund.created/refund.updated and on replay
  - acks (does not raise) an orphan refund for an unrecorded charge
"""

import uuid

from sqlalchemy import text

from tests.stripe_webhooks.conftest import fake_charge_id_for
from tests.stripe_webhooks.event_builders import (
    make_invoice_paid_event,
    make_invoice_payment_paid_event,
    make_refund_event,
)


async def _seed_parent_payment(
    stripe_webhooks_service,
    stripe_account_id,
    webhook_fixture,
    *,
    payment_intent_id: str,
    amount: int = 5000,
) -> str:
    """Record an invoice + its payment; return the resulting stripe_charge_id."""
    stripe_invoice_id = f"in_test_refund_{uuid.uuid4().hex[:16]}"
    await stripe_webhooks_service.handle_event(
        make_invoice_paid_event(
            stripe_account_id=stripe_account_id,
            stripe_item_ids=[webhook_fixture.stripe_item_id],
            amount_paid=amount,
            stripe_invoice_id=stripe_invoice_id,
        )
    )
    await stripe_webhooks_service.handle_event(
        make_invoice_payment_paid_event(
            stripe_account_id=stripe_account_id,
            stripe_invoice_id=stripe_invoice_id,
            amount_paid=amount,
            payment_intent_id=payment_intent_id,
        )
    )
    return fake_charge_id_for(payment_intent_id)


async def _fetch_refund_rows(db_pool, gym_id) -> list[dict]:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT charge_id, kind, status, amount, currency, "
                "stripe_refund_id, refunds_charge_id, paid_by_member_id "
                "FROM member_charges "
                "WHERE gym_id = :gym_id AND kind = 'refund' "
                "ORDER BY charge_time"
            ),
            {"gym_id": str(gym_id)},
        )
        rows = result.mappings().fetchall()
    return [dict(r) for r in rows]


async def _parent_charge_id(db_pool, stripe_charge_id: str):
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


async def test_refund_created_records_refund(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    charge_id = await _seed_parent_payment(
        stripe_webhooks_service, stripe_account_id, webhook_fixture,
        payment_intent_id="pi_refund_full_1", amount=5000,
    )
    parent_charge_id = await _parent_charge_id(db_pool, charge_id)
    assert parent_charge_id is not None

    await stripe_webhooks_service.handle_event(
        make_refund_event(
            stripe_account_id=stripe_account_id,
            stripe_charge_id=charge_id,
            amount=5000,
        )
    )

    refunds = await _fetch_refund_rows(db_pool, gym_id)
    assert len(refunds) == 1
    r = refunds[0]
    assert r["kind"] == "refund"
    assert r["status"] == "succeeded"
    assert r["amount"] == -5000  # negative per schema convention
    assert r["currency"] == "usd"
    assert r["stripe_refund_id"] is not None
    assert str(r["refunds_charge_id"]) == str(parent_charge_id)
    assert str(r["paid_by_member_id"]) == str(webhook_fixture.member_id)


async def test_two_partial_refunds_record_two_rows(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    """Each refund is its own event in dahlia — two refunds, two rows."""
    charge_id = await _seed_parent_payment(
        stripe_webhooks_service, stripe_account_id, webhook_fixture,
        payment_intent_id="pi_refund_multi_1", amount=5000,
    )

    for amt, rid in ((1500, "re_part_a"), (2500, "re_part_b")):
        await stripe_webhooks_service.handle_event(
            make_refund_event(
                stripe_account_id=stripe_account_id,
                stripe_charge_id=charge_id,
                amount=amt,
                refund_id=rid,
            )
        )

    refunds = await _fetch_refund_rows(db_pool, gym_id)
    assert len(refunds) == 2
    assert sorted(r["amount"] for r in refunds) == [-2500, -1500]
    assert len({r["stripe_refund_id"] for r in refunds}) == 2


async def test_pending_then_succeeded_records_once(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    """A pending refund.created records nothing; the succeeded refund.updated
    records it; replaying either does not duplicate."""
    charge_id = await _seed_parent_payment(
        stripe_webhooks_service, stripe_account_id, webhook_fixture,
        payment_intent_id="pi_refund_async_1",
    )
    rid = "re_async_1"

    # Pending create → no row.
    await stripe_webhooks_service.handle_event(
        make_refund_event(
            stripe_account_id=stripe_account_id,
            stripe_charge_id=charge_id,
            amount=2500,
            refund_id=rid,
            status="pending",
            event_type="refund.created",
        )
    )
    assert await _fetch_refund_rows(db_pool, gym_id) == []

    # Succeeded update → one row.
    await stripe_webhooks_service.handle_event(
        make_refund_event(
            stripe_account_id=stripe_account_id,
            stripe_charge_id=charge_id,
            amount=2500,
            refund_id=rid,
            status="succeeded",
            event_type="refund.updated",
        )
    )
    refunds = await _fetch_refund_rows(db_pool, gym_id)
    assert len(refunds) == 1
    assert refunds[0]["amount"] == -2500


async def test_refund_is_idempotent_on_repeat(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    charge_id = await _seed_parent_payment(
        stripe_webhooks_service, stripe_account_id, webhook_fixture,
        payment_intent_id="pi_refund_idem_1",
    )
    event = make_refund_event(
        stripe_account_id=stripe_account_id,
        stripe_charge_id=charge_id,
        amount=2500,
        refund_id="re_idem_1",
    )

    await stripe_webhooks_service.handle_event(event)
    await stripe_webhooks_service.handle_event(event)
    await stripe_webhooks_service.handle_event(event)

    refunds = await _fetch_refund_rows(db_pool, gym_id)
    assert len(refunds) == 1
    assert refunds[0]["amount"] == -2500


async def test_orphan_refund_is_logged_and_acked(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    """A refund for a charge we never recorded must log, ack, and NOT raise."""
    event = make_refund_event(
        stripe_account_id=stripe_account_id,
        stripe_charge_id="ch_orphan_never_recorded",
        amount=1000,
    )

    await stripe_webhooks_service.handle_event(event)  # must not raise

    assert await _fetch_refund_rows(db_pool, gym_id) == []
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT COUNT(*) AS n FROM stripe_webhook_events WHERE event_id = :id"),
            {"id": event["id"]},
        )
        row = result.mappings().fetchone()
    assert int(row["n"]) == 1


async def test_refund_does_not_touch_membership_dates(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    charge_id = await _seed_parent_payment(
        stripe_webhooks_service, stripe_account_id, webhook_fixture,
        payment_intent_id="pi_refund_dates_1",
    )

    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT last_paid_date, next_due_date "
                "FROM member_memberships_unfiltered WHERE item_id = :id"
            ),
            {"id": str(webhook_fixture.item_id)},
        )
        before = dict(result.mappings().fetchone())

    await stripe_webhooks_service.handle_event(
        make_refund_event(
            stripe_account_id=stripe_account_id,
            stripe_charge_id=charge_id,
            amount=5000,
        )
    )

    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT last_paid_date, next_due_date "
                "FROM member_memberships_unfiltered WHERE item_id = :id"
            ),
            {"id": str(webhook_fixture.item_id)},
        )
        after = dict(result.mappings().fetchone())

    assert before == after
