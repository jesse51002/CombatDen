"""Integration tests for the ``customer.subscription.deleted`` handler.

The prompt path for Stripe-side cancellation: the handler reads ``member_id`` from
the cancelled sub's metadata and runs ``bulk_payment_sync`` for the family. The
sync, finding the subscription gone, records the cancellation — that end-to-end
behavior is covered by ``tests/member_memberships/test_payment_sync_cancel.py``
against a real Connect account. Here we cover the handler's own job: the metadata
guards (missing / malformed member_id are acked, never 500) and that a valid event
hands the family to the sync.
"""

from uuid import uuid4

from sqlalchemy import text

from tests.stripe_webhooks.event_builders import (
    make_customer_subscription_deleted_event,
)


async def _event_recorded(db_pool, event_id: str) -> bool:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT 1 FROM stripe_webhook_events WHERE event_id = :id"
            ),
            {"id": event_id},
        )
        return result.fetchone() is not None


async def test_missing_member_id_is_acked(
    stripe_webhooks_service, db_pool, stripe_account_id, gym_id
):
    """A sub with no member_id in metadata is acked (logged), not a 500."""
    event = make_customer_subscription_deleted_event(
        stripe_account_id=stripe_account_id, member_id=None
    )
    await stripe_webhooks_service.handle_event(event)  # must not raise
    assert await _event_recorded(db_pool, event["id"]) is True


async def test_malformed_member_id_is_acked(
    stripe_webhooks_service, db_pool, stripe_account_id, gym_id
):
    """A malformed member_id is guarded (acked), not an uncaught ValueError."""
    event = make_customer_subscription_deleted_event(
        stripe_account_id=stripe_account_id, member_id="not-a-uuid"
    )
    await stripe_webhooks_service.handle_event(event)  # guard prevents a 500
    assert await _event_recorded(db_pool, event["id"]) is True


async def test_deleted_sub_triggers_family_sync(
    stripe_webhooks_service,
    customer_subscription_deleted_handler,
    db_pool,
    stripe_account_id,
    gym_id,
    monkeypatch,
):
    """A valid event hands the family (its member_id) to bulk_payment_sync.

    Spies on the sync so the assertion is about the handler's dispatch, not the
    sync's cancel (covered elsewhere) — and so it doesn't need the webhook
    fixtures' synthetic Connect account to be real.
    """
    member_id = uuid4()
    calls: list[list] = []

    async def _spy(member_ids):
        calls.append(member_ids)

    # Same handler instance the dispatcher uses (both module-scoped fixtures), so
    # this exercises the full dispatcher -> handler -> sync path + event logging.
    monkeypatch.setattr(
        customer_subscription_deleted_handler._payment_sync,
        "bulk_payment_sync",
        _spy,
    )

    event = make_customer_subscription_deleted_event(
        stripe_account_id=stripe_account_id, member_id=str(member_id)
    )
    await stripe_webhooks_service.handle_event(event)

    assert calls == [[member_id]]
    assert await _event_recorded(db_pool, event["id"]) is True
