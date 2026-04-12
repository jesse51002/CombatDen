"""Integration tests for freezing/unfreezing memberships."""

import pytest
from sqlalchemy import text

from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import (
    create_member,
    create_payment_method,
    create_plan,
)


async def test_freeze_account(
    memberships_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
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
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_freeze_updates_end_date(
    memberships_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
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
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_unfreeze_account(
    memberships_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
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
        await memberships_service.freeze(member.crm_user_id, gym_id, 2)
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
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_freeze_zero_months_raises(
    memberships_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
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

        with pytest.raises(ValueError):
            await memberships_service.freeze(member.crm_user_id, gym_id, 0)
    finally:
        await delete_member_data(db_pool, member.crm_user_id)
