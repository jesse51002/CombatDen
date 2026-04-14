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


async def test_start_zero_dollar_one_time_membership(
    memberships_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    """Regression: $0 one-time plans must not crash on pay_async."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(
        db_pool, stripe_client, gym_id, connect_opts,
        plan_type="one_time",
        plan_name="Free Trial Test",
        price_cents=0,
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
                    "SELECT item_id, stripe_item_id, total_price "
                    "FROM member_memberships "
                    "WHERE crm_user_id = :id AND plan_id = :plan_id"
                ),
                {"id": str(member.crm_user_id), "plan_id": str(plan.plan_id)},
            )
            row = result.mappings().fetchone()

        assert row is not None
        assert row["stripe_item_id"] is not None
        assert row["total_price"] == 0
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_start_zero_dollar_recurring_membership(
    memberships_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    """Regression: $0 recurring plans must start cleanly as free subscriptions."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(
        db_pool, stripe_client, gym_id, connect_opts,
        plan_type="recurring",
        plan_name="Free Recurring Test",
        price_cents=0,
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
                    "SELECT item_id, stripe_item_id, total_price "
                    "FROM member_memberships "
                    "WHERE crm_user_id = :id AND plan_id = :plan_id"
                ),
                {"id": str(member.crm_user_id), "plan_id": str(plan.plan_id)},
            )
            row = result.mappings().fetchone()

        assert row is not None
        assert row["stripe_item_id"] is not None
        assert row["total_price"] == 0
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
    memberships_service, payment_sync_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    """Resyncing a member with an active membership that carries
    ``discount_ids`` must pass real Stripe coupon IDs — not CRM
    discount UUIDs — to Stripe.

    Regression guard for the 502 "Coupon <uuid> not found" bug caused
    by ``aggregate_plan_discounts`` passing CRM UUIDs straight to
    Stripe. The first ``start`` alone can't trip this path because the
    ``member_memberships`` view filters ``stripe_item_id IS NOT NULL``,
    hiding the pending row during its own sync. It's the next sync —
    when the row is visible and its ``discount_ids`` feed back through
    aggregation — that used to crash. We trigger that next sync with
    an explicit no-op ``update_payments_recurring`` call.
    """
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)
    discount = await create_discount(db_pool, stripe_client, gym_id, connect_opts)

    try:
        # First start: inserts row with discount_ids, triggers sync
        # while the row is still stripe_item_id IS NULL (invisible).
        await memberships_service.start(
            crm_user_id=member.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            discount_ids=[discount.discount_id],
        )

        # Force a second sync. The prior row is now visible through
        # the filtered view, so aggregate_plan_discounts will see
        # its discount_ids and must resolve them to real Stripe
        # coupon IDs. Previously this 502'd with
        # "Coupon <crm-uuid> not found".
        await payment_sync_service.update_payments_recurring(
            crm_user_id=member.crm_user_id,
            add_ids=[],
            cancel_ids=[],
        )

        async with db_pool.session() as session:
            mm_row = (
                await session.execute(
                    text(
                        "SELECT discount_ids FROM member_memberships "
                        "WHERE crm_user_id = :id AND plan_id = :plan_id"
                    ),
                    {"id": str(member.crm_user_id), "plan_id": str(plan.plan_id)},
                )
            ).mappings().fetchone()
            profile_row = (
                await session.execute(
                    text(
                        "SELECT stripe_sub_id_month FROM user_gym_profiles "
                        "WHERE crm_user_id = :id AND gym_id = :gym_id"
                    ),
                    {"id": str(member.crm_user_id), "gym_id": str(gym_id)},
                )
            ).mappings().fetchone()

        assert mm_row is not None
        assert mm_row["discount_ids"] is not None
        assert profile_row is not None
        stripe_sub_id = profile_row["stripe_sub_id_month"]
        assert stripe_sub_id is not None, (
            "Parent profile should have a Stripe subscription after start"
        )

        # Stripe must have received the real stripe_coupon_id on the
        # discounted plan's subscription item — not the CRM UUID.
        # Expand the per-item discount references so we can read
        # their coupons directly.
        sub = await stripe_client.client.v1.subscriptions.retrieve_async(
            stripe_sub_id,
            params={"expand": ["items.data.discounts.coupon"]},
            options=connect_opts,
        )
        # Stripe returns per-item discounts as expanded Discount
        # objects with the coupon reference nested under ``source``:
        # ``{"id": "di_...", "source": {"coupon": "<coupon_id>", ...}}``.
        applied_coupons: set[str] = set()
        sub_dict = sub.to_dict()
        for item in sub_dict.get("items", {}).get("data", []):
            for item_discount in item.get("discounts") or []:
                if isinstance(item_discount, str):
                    applied_coupons.add(item_discount)
                    continue
                source = item_discount.get("source") or {}
                coupon = source.get("coupon") or item_discount.get("coupon")
                if coupon is None:
                    continue
                if isinstance(coupon, dict):
                    applied_coupons.add(coupon.get("id", ""))
                else:
                    applied_coupons.add(coupon)

        assert discount.stripe_coupon_id in applied_coupons, (
            f"Expected Stripe subscription item to reference coupon "
            f"{discount.stripe_coupon_id}, got {applied_coupons}"
        )
        assert str(discount.discount_id) not in applied_coupons, (
            "CRM discount_id UUID must never be sent to Stripe as a coupon id"
        )
    finally:
        await delete_member_data(db_pool, member.crm_user_id)
