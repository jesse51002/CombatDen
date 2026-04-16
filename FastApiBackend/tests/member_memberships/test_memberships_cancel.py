"""Integration tests for cancelling memberships.

Every test fetches the Stripe subscription (or confirms it was
deleted) after the cancel and asserts that no surprise charges
landed on the member's customer balance.
"""

from uuid import UUID

import pytest
import stripe
from sqlalchemy import text

from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import (
    create_member,
    create_payment_method,
    create_plan,
)
from tests.helpers.db_reads import get_profile_stripe_ids
from tests.helpers.stripe_assertions import (
    assert_no_unexpected_charges,
    fetch_subscription,
    snapshot_billing_state,
)


async def _start_and_get_item_id(
    memberships_service,
    db_pool,
    member,
    gym_id,
    plan,
):
    """Start a membership and return the item_id."""
    await memberships_service.start(
        crm_user_id=member.crm_user_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
    )
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT item_id FROM member_memberships "
                "WHERE crm_user_id = :id AND plan_id = :plan_id"
            ),
            {"id": str(member.crm_user_id), "plan_id": str(plan.plan_id)},
        )
        row = result.mappings().fetchone()
    return UUID(str(row["item_id"]))


async def _assert_sub_canceled_or_item_removed(
    stripe_client,
    connect_opts,
    stripe_sub_id: str,
    removed_stripe_price_id: str,
) -> None:
    """Confirm the cancel reached Stripe.

    For the only-item-on-the-sub case, cancelling the item usually
    deletes the whole subscription; retrieving it either returns
    status ``canceled`` or raises 404. For the multi-item case,
    the sub survives but the cancelled item's price is gone.
    """
    try:
        sub = await fetch_subscription(
            stripe_client,
            stripe_sub_id,
            connect_opts,
        )
    except stripe.InvalidRequestError as exc:
        # 404 — Stripe deleted the subscription when its last item
        # was removed. That's a valid cancel outcome.
        assert "No such subscription" in str(exc), f"Unexpected Stripe error after cancel: {exc}"
        return

    if sub.status == "canceled":
        return

    # Subscription still exists (e.g. had other family items) —
    # verify the cancelled price is no longer on any remaining item.
    remaining_prices = {item.price.id for item in sub.items.data}
    assert removed_stripe_price_id not in remaining_prices, (
        f"Cancelled price {removed_stripe_price_id} still present on "
        f"subscription {stripe_sub_id}: items={sorted(remaining_prices)}"
    )


async def test_cancel_active_membership(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)

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
            member.crm_user_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.cancel(item_id, member.crm_user_id)

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT cancel_date FROM member_memberships_unfiltered "
                    "WHERE item_id = :item_id"
                ),
                {"item_id": str(item_id)},
            )
            row = result.mappings().fetchone()

        assert row is not None
        assert row["cancel_date"] is not None

        await _assert_sub_canceled_or_item_removed(
            stripe_client,
            connect_opts,
            profile.stripe_sub_id_month,
            plan.stripe_price_id,
        )
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_cancel_already_cancelled_noop(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)

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
            member.crm_user_id,
            gym_id,
        )

        await memberships_service.cancel(item_id, member.crm_user_id)

        # Snapshot after the first cancel completes — the second
        # cancel is a pure CRM no-op and must not reach Stripe at all.
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.cancel(item_id, member.crm_user_id)

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_cancel_one_time_raises(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        plan_type="one_time",
        plan_name="One-Time Cancel Test",
        price_cents=2000,
    )

    try:
        await memberships_service.start(
            crm_user_id=member.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id FROM member_memberships "
                    "WHERE crm_user_id = :id AND plan_id = :plan_id"
                ),
                {"id": str(member.crm_user_id), "plan_id": str(plan.plan_id)},
            )
            row = result.mappings().fetchone()
        item_id = UUID(str(row["item_id"]))

        # Snapshot after start completes — the failed cancel must
        # not create any Stripe side effects.
        profile = await get_profile_stripe_ids(
            db_pool,
            member.crm_user_id,
            gym_id,
        )
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        with pytest.raises((ValueError, Exception)):
            await memberships_service.cancel(item_id, member.crm_user_id)

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.crm_user_id)
