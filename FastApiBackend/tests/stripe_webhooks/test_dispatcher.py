"""Integration tests for the StripeWebhooksService dispatcher.

Covers gym resolution, idempotency (stripe_webhook_events dedup),
unknown event types, and malformed events. Handler-specific
behavior is covered in the dedicated handler test files.
"""

import pytest
from sqlalchemy import text

from tests.stripe_webhooks.event_builders import (
    make_invoice_paid_event,
)


async def _event_log_count(db_pool, event_id: str) -> int:
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT COUNT(*) AS n FROM stripe_webhook_events WHERE event_id = :id"),
            {"id": event_id},
        )
        row = result.mappings().fetchone()
    return int(row["n"])


async def _charges_count(db_pool, gym_id) -> int:
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT COUNT(*) AS n FROM member_charges WHERE gym_id = :gym_id"),
            {"gym_id": str(gym_id)},
        )
        row = result.mappings().fetchone()
    return int(row["n"])


async def _invoices_count(db_pool, gym_id) -> int:
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT COUNT(*) AS n FROM member_invoices WHERE gym_id = :gym_id"),
            {"gym_id": str(gym_id)},
        )
        row = result.mappings().fetchone()
    return int(row["n"])


async def test_dispatcher_rejects_event_missing_id(stripe_webhooks_service):
    event = {"type": "invoice.paid", "account": "acct_test", "data": {"object": {}}}
    with pytest.raises(ValueError, match="missing id or type"):
        await stripe_webhooks_service.handle_event(event)


async def test_dispatcher_rejects_event_missing_type(stripe_webhooks_service):
    event = {"id": "evt_x", "account": "acct_test", "data": {"object": {}}}
    with pytest.raises(ValueError, match="missing id or type"):
        await stripe_webhooks_service.handle_event(event)


async def test_dispatcher_ignores_platform_event_without_account(
    stripe_webhooks_service,
    db_pool,
    gym_id,
):
    """Events with no ``account`` are platform-level; we only handle Connect."""
    event = {
        "id": "evt_test_platform_1",
        "type": "customer.updated",
        "data": {"object": {}},
    }
    await stripe_webhooks_service.handle_event(event)

    # Not recorded — the endpoint is Connect-only.
    assert await _event_log_count(db_pool, "evt_test_platform_1") == 0


async def test_dispatcher_ignores_unknown_stripe_account(
    stripe_webhooks_service,
    db_pool,
):
    """Events for a connected account we don't know about are dropped."""
    event = {
        "id": "evt_test_unknown_acct_1",
        "type": "invoice.paid",
        "account": "acct_not_in_our_db",
        "data": {"object": {"id": "in_x", "lines": {"data": []}}},
    }
    await stripe_webhooks_service.handle_event(event)

    assert await _event_log_count(db_pool, "evt_test_unknown_acct_1") == 0


async def test_dispatcher_logs_unknown_event_type_and_records_it(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
):
    """Unknown event types are a no-op but are still recorded so the
    same event isn't redispatched on Stripe retries.
    """
    event = {
        "id": "evt_test_unknown_type_1",
        "type": "customer.subscription.updated",
        "account": stripe_account_id,
        "data": {"object": {}},
    }
    await stripe_webhooks_service.handle_event(event)

    # Recorded as processed even though no handler ran.
    assert await _event_log_count(db_pool, "evt_test_unknown_type_1") == 1
    # No side effects.
    assert await _charges_count(db_pool, gym_id) == 0


async def test_dispatcher_dedupes_repeat_event_delivery(
    stripe_webhooks_service,
    db_pool,
    gym_id,
    stripe_account_id,
    webhook_fixture,
):
    """Stripe delivers an event twice — the handler must only run once."""
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        amount_paid=5000,
    )

    await stripe_webhooks_service.handle_event(event)
    await stripe_webhooks_service.handle_event(event)

    # Exactly one event-log row.
    assert await _event_log_count(db_pool, event["id"]) == 1
    # Exactly one invoice row (not two) — invoice.paid records the bill;
    # charges come from invoice_payment.paid, so there are none here.
    assert await _invoices_count(db_pool, gym_id) == 1
    assert await _charges_count(db_pool, gym_id) == 0
