"""Integration tests for updating membership price tiers."""

from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

from src.membership_plans.membership_plans_schemas import MembershipPlanPriceRequest
from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import (
    create_member,
    create_payment_method,
    create_plan,
)


async def _start_and_get_item_id(memberships_service, db_pool, member, gym_id, plan):
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


async def test_update_price_tier(
    memberships_service, plans_service, db_pool, gym_id,
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

        # Use the production service to create a second price tier
        new_price = await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id,
                gym_id=gym_id,
                price=8000,
            ),
        )

        await memberships_service.update_price(
            item_id=item_id,
            crm_user_id=member.crm_user_id,
            new_price_id=new_price.price_id,
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
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_update_cancelled_raises(
    memberships_service, plans_service, db_pool, gym_id,
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

        new_price = await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id,
                gym_id=gym_id,
                price=8000,
            ),
        )
        await memberships_service.cancel(item_id, member.crm_user_id)

        with pytest.raises((ValueError, Exception)):
            await memberships_service.update_price(
                item_id=item_id,
                crm_user_id=member.crm_user_id,
                new_price_id=new_price.price_id,
            )
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_update_invalid_price_raises(
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

        with pytest.raises((ValueError, Exception)):
            await memberships_service.update_price(
                item_id=item_id,
                crm_user_id=member.crm_user_id,
                new_price_id=uuid4(),
            )
    finally:
        await delete_member_data(db_pool, member.crm_user_id)
