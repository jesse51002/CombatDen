"""Integration tests for updating membership price tiers.

Every test snapshots the customer's Stripe billing state before
calling ``update_price`` and asserts afterwards that:

1. The Stripe subscription item now uses the new price id.
2. No surprise invoice was created (``prorate=False`` path).
3. Failed validation paths don't mutate Stripe at all.
"""

from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

from src.plans.plans_schema import MembershipPlanPriceRequest
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import get_profile_stripe_ids
from tests.helpers.stripe_assertions import (
    assert_no_unexpected_charges,
    assert_subscription_item_price,
    fetch_subscription,
    snapshot_billing_state,
)


async def _start_and_get_item_id(memberships_service, db_pool, member, gym_id, plan):
    await memberships_service.start(
        member_id=member.member_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
        idempotency_key=uuid4(),
    )
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT item_id FROM member_memberships "
                "WHERE member_id = :id AND plan_id = :plan_id"
            ),
            {"id": str(member.member_id), "plan_id": str(plan.plan_id)},
        )
        row = result.mappings().fetchone()
    return UUID(str(row["item_id"]))


def _find_item_by_price(sub, stripe_price_id: str):
    """Return the subscription item whose price matches ``stripe_price_id``."""
    for idx, item in enumerate(sub.items.data):
        if item.price.id == stripe_price_id:
            return idx, item
    raise AssertionError(
        f"No item on subscription {sub.id} uses price {stripe_price_id}; "
        f"items={[i.price.id for i in sub.items.data]}"
    )


async def test_update_price_tier(
    memberships_service,
    plans_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(gym_id)

    try:
        item_id = await _start_and_get_item_id(
            memberships_service,
            db_pool,
            member,
            gym_id,
            plan,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        # Use the production service to create a second price tier
        new_price = await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id,
                gym_id=gym_id,
                price=8000,
            ),
        )

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.update_price(
            item_id=item_id,
            member_id=member.member_id,
            idempotency_key=uuid4(),
            prorate=False,
        )

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT price_id, total_price "
                    "FROM member_memberships_unfiltered "
                    "WHERE item_id = :item_id"
                ),
                {"item_id": str(item_id)},
            )
            row = result.mappings().fetchone()

        assert UUID(str(row["price_id"])) == new_price.price_id
        assert row["total_price"] == 8000

        # Stripe side: the subscription must now carry the new price
        # id on exactly one item, and no new invoice may have been
        # created (prorate=False is the existing contract).
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        idx, _ = _find_item_by_price(sub, new_price.stripe_price_id)
        assert_subscription_item_price(
            sub,
            new_price.stripe_price_id,
            index=idx,
        )
        # Old price must be gone.
        remaining_prices = {item.price.id for item in sub.items.data}
        assert plan.stripe_price_id not in remaining_prices, (
            f"Old price {plan.stripe_price_id} still on subscription "
            f"{profile.stripe_sub_id_month} after update"
        )

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_update_cancelled_raises(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(gym_id)

    try:
        item_id = await _start_and_get_item_id(
            memberships_service,
            db_pool,
            member,
            gym_id,
            plan,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )

        await memberships_service.cancel(item_id, member.member_id, idempotency_key=uuid4())

        # Snapshot after cancel — the failed update_price below must
        # not create any invoice or leave a partially-mutated Stripe
        # subscription item behind.
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        with pytest.raises((ValueError, Exception)):
            await memberships_service.update_price(
                item_id=item_id,
                member_id=member.member_id,
                idempotency_key=uuid4(),
            )

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)
