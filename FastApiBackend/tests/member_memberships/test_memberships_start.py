"""Integration tests for starting memberships."""

from uuid import uuid4

import pytest
from sqlalchemy import text

from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import (
    create_discount,
    create_member,
    create_payment_method,
    create_plan,
)


async def test_start_recurring_membership(
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

        # Verify DB row exists with stripe_item_id set
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id, stripe_item_id FROM member_memberships "
                    "WHERE crm_user_id = :id AND plan_id = :plan_id"
                ),
                {"id": str(member.crm_user_id), "plan_id": str(plan.plan_id)},
            )
            row = result.mappings().fetchone()

        assert row is not None
        assert row["stripe_item_id"] is not None
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_start_one_time_membership(
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
        plan_name="One-Time Test",
        price_cents=3000,
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
                    "SELECT item_id, stripe_item_id FROM member_memberships "
                    "WHERE crm_user_id = :id AND plan_id = :plan_id"
                ),
                {"id": str(member.crm_user_id), "plan_id": str(plan.plan_id)},
            )
            row = result.mappings().fetchone()

        assert row is not None
        assert row["stripe_item_id"] is not None
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_start_validates_plan_price(
    memberships_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        payment_method_id=pm_id,
    )

    try:
        with pytest.raises((ValueError, Exception)):
            await memberships_service.start(
                crm_user_id=member.crm_user_id,
                gym_id=gym_id,
                plan_id=uuid4(),
                price_id=uuid4(),
            )
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_start_duplicate_raises(
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

        with pytest.raises((ValueError, Exception)):
            await memberships_service.start(
                crm_user_id=member.crm_user_id,
                gym_id=gym_id,
                plan_id=plan.plan_id,
                price_id=plan.price_id,
            )
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_start_with_discount(
    memberships_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)
    discount = await create_discount(db_pool, stripe_client, gym_id, connect_opts)

    try:
        await memberships_service.start(
            crm_user_id=member.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            discount_ids=[discount.discount_id],
        )

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT discount_ids FROM member_memberships "
                    "WHERE crm_user_id = :id AND plan_id = :plan_id"
                ),
                {"id": str(member.crm_user_id), "plan_id": str(plan.plan_id)},
            )
            row = result.mappings().fetchone()

        assert row is not None
        assert row["discount_ids"] is not None
    finally:
        await delete_member_data(db_pool, member.crm_user_id)
