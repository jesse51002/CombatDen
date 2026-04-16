"""Integration tests for freezing/unfreezing memberships.

Every test fetches the Stripe subscription after the freeze/unfreeze
and asserts that ``pause_collection`` is in the expected state AND
that no surprise charges landed on the member while the freeze was
in effect.
"""

import pytest
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


async def test_freeze_account(
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
        await memberships_service.start(
            crm_user_id=member.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
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

        await memberships_service.freeze(member.crm_user_id, gym_id, 2)

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT freeze_start_date, freeze_end_date "
                    "FROM user_gym_profiles_unfiltered "
                    "WHERE crm_user_id = :id"
                ),
                {"id": str(member.crm_user_id)},
            )
            row = result.mappings().fetchone()

        assert row["freeze_start_date"] is not None
        assert row["freeze_end_date"] is not None

        # Stripe side: pause_collection must be set on the
        # subscription, and no new invoices may have been generated.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert sub.pause_collection is not None, (
            f"Subscription {profile.stripe_sub_id_month} is not paused after freeze"
        )
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_freeze_updates_end_date(
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
        await memberships_service.start(
            crm_user_id=member.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.crm_user_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        await memberships_service.freeze(member.crm_user_id, gym_id, 1)

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT freeze_end_date FROM user_gym_profiles_unfiltered "
                    "WHERE crm_user_id = :id"
                ),
                {"id": str(member.crm_user_id)},
            )
            first_end = result.mappings().fetchone()["freeze_end_date"]

        # Snapshot between the two freeze calls. Extending a freeze
        # must not generate any charge or upcoming invoice.
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        # Re-freeze with different duration
        await memberships_service.freeze(member.crm_user_id, gym_id, 3)

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT freeze_end_date FROM user_gym_profiles_unfiltered "
                    "WHERE crm_user_id = :id"
                ),
                {"id": str(member.crm_user_id)},
            )
            second_end = result.mappings().fetchone()["freeze_end_date"]

        assert second_end > first_end

        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert sub.pause_collection is not None, (
            "Subscription must still be paused after re-freeze"
        )
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_unfreeze_account(
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
        await memberships_service.start(
            crm_user_id=member.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.crm_user_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        await memberships_service.freeze(member.crm_user_id, gym_id, 2)

        # Snapshot while frozen — the unfreeze itself must not
        # invoice the member, it only clears pause_collection.
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.unfreeze(member.crm_user_id, gym_id)

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT freeze_start_date, freeze_end_date "
                    "FROM user_gym_profiles_unfiltered "
                    "WHERE crm_user_id = :id"
                ),
                {"id": str(member.crm_user_id)},
            )
            row = result.mappings().fetchone()

        assert row["freeze_start_date"] is None
        assert row["freeze_end_date"] is None

        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert sub.pause_collection is None, (
            f"Subscription {profile.stripe_sub_id_month} still paused after unfreeze"
        )
        assert sub.status == "active"
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_freeze_zero_months_raises(
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
        await memberships_service.start(
            crm_user_id=member.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.crm_user_id,
            gym_id,
        )

        # Validation error must not touch Stripe at all.
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        with pytest.raises(ValueError):
            await memberships_service.freeze(member.crm_user_id, gym_id, 0)

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
        if profile.stripe_sub_id_month is not None:
            sub = await fetch_subscription(
                stripe_client,
                profile.stripe_sub_id_month,
                connect_opts,
            )
            assert sub.pause_collection is None, "Failed validation must not pause the Stripe sub"
    finally:
        await delete_member_data(db_pool, member.crm_user_id)
