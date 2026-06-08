"""Integration tests for the ``customer.subscription.deleted`` handler.

The prompt path for Stripe-side cancellation: the handler reads ``member_id`` from
the cancelled sub's metadata and calls the shared (CRM-only)
``SubscriptionCancellationAbsorber``. Covers the metadata guards (missing /
malformed member_id are acked, never 500) and the happy path (an active recurring
membership is cancelled and the parent's ``stripe_sub_id_month`` is nulled).
"""

from uuid import UUID, uuid4

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


async def test_absorbs_cancellation(
    stripe_webhooks_service, db_pool, stripe_account_id, gym_id, created
):
    """A real cancelled sub → the member's membership is cancelled + sub id nulled."""
    member = await created.member(gym_id)
    plan = await created.plan(gym_id)

    # An applied recurring membership + a live sub id on the member. start_date a
    # week back so the absorber's gym-tz cancel_date keeps daterange(start, cancel)
    # valid regardless of the UTC boundary.
    insert_sql = """
        INSERT INTO member_memberships_unfiltered (
            member_id, gym_id, plan_id, price_id,
            start_date, stripe_item_id, total_price, stripe_sync_status
        ) VALUES (
            :member_id, :gym_id, :plan_id, :price_id,
            CURRENT_DATE - 7, :stripe_item_id, 5000, 'applied'
        )
        RETURNING item_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(insert_sql),
            {
                "member_id": str(member.member_id),
                "gym_id": str(gym_id),
                "plan_id": str(plan.plan_id),
                "price_id": str(plan.price_id),
                "stripe_item_id": f"si_fake_{uuid4().hex[:12]}",
            },
        )
        item_id = UUID(str(result.mappings().fetchone()["item_id"]))
        await session.execute(
            text(
                "UPDATE members SET stripe_sub_id_month = :sub "
                "WHERE member_id = :id"
            ),
            {"sub": f"sub_fake_{uuid4().hex[:12]}", "id": str(member.member_id)},
        )
        await session.commit()

    event = make_customer_subscription_deleted_event(
        stripe_account_id=stripe_account_id,
        member_id=str(member.member_id),
    )
    await stripe_webhooks_service.handle_event(event)

    async with db_pool.session() as session:
        row = (
            await session.execute(
                text(
                    "SELECT cancel_date, stripe_sync_status "
                    "FROM member_memberships_unfiltered WHERE item_id = :id"
                ),
                {"id": str(item_id)},
            )
        ).mappings().fetchone()
        sub_row = (
            await session.execute(
                text(
                    "SELECT stripe_sub_id_month FROM members "
                    "WHERE member_id = :id"
                ),
                {"id": str(member.member_id)},
            )
        ).mappings().fetchone()

    assert row["cancel_date"] is not None
    assert row["stripe_sync_status"] == "deleted"
    assert sub_row["stripe_sub_id_month"] is None
    assert await _event_recorded(db_pool, event["id"]) is True
