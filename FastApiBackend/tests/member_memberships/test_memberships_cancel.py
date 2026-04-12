"""Integration tests for cancelling memberships."""

from uuid import UUID

import pytest
from sqlalchemy import text

from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import (
    create_member,
    create_payment_method,
    create_plan,
)


async def _start_and_get_item_id(
    memberships_service, db_pool, member, gym_id, plan,
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


async def test_cancel_active_membership(
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
        item_id = await _start_and_get_item_id(
            memberships_service, db_pool, member, gym_id, plan,
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
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_cancel_already_cancelled_noop(
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
        item_id = await _start_and_get_item_id(
            memberships_service, db_pool, member, gym_id, plan,
        )

        await memberships_service.cancel(item_id, member.crm_user_id)
        # Second cancel should be a no-op
        await memberships_service.cancel(item_id, member.crm_user_id)
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_cancel_one_time_raises(
    memberships_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(
        db_pool, stripe_client, gym_id, connect_opts,
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

        with pytest.raises((ValueError, Exception)):
            await memberships_service.cancel(item_id, member.crm_user_id)
    finally:
        await delete_member_data(db_pool, member.crm_user_id)
