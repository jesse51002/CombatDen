"""Integration tests for DiscountsService.

Every CRUD path also retrieves the Stripe coupon and asserts the
final state matches. This is the contract: if the service reports
success, the coupon on Stripe must be in the expected shape.
"""

import pytest
import stripe
from schema.gym_discount import DiscountType
from sqlalchemy import text
from starlette.background import BackgroundTasks

from src.discounts.schema.discounts_schema import (
    DiscountCreateRequest,
    DiscountUpdateData,
    DiscountUpdateRequest,
)
from src.payments.schema.payments_enums import StripeCouponDuration


async def _fetch_coupon(stripe_client, coupon_id, connect_opts):
    return await stripe_client.client.v1.coupons.retrieve_async(
        coupon_id,
        options=connect_opts,
    )


async def test_create_percentage_discount(
    discounts_service,
    gym_id,
    stripe_client,
    connect_opts,
):
    resp = await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name="20% Off",
            discount_type=DiscountType.preset,
            percentage_off=20.0,
            duration=StripeCouponDuration.forever,
        ),
    )

    assert resp.discount_id is not None
    assert resp.discount_name == "20% Off"
    assert resp.percentage_off == 20.0
    assert resp.dollar_off is None
    assert resp.stripe_coupon_id is not None

    # Stripe side: coupon must exist with the expected percent_off.
    coupon = await _fetch_coupon(
        stripe_client,
        resp.stripe_coupon_id,
        connect_opts,
    )
    assert coupon.valid is True
    assert coupon.percent_off == 20.0
    assert coupon.amount_off is None
    assert coupon.duration == StripeCouponDuration.forever.value


async def test_create_dollar_discount(
    discounts_service,
    gym_id,
    stripe_client,
    connect_opts,
):
    resp = await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name="$10 Off",
            discount_type=DiscountType.preset,
            dollar_off=1000,
            duration=StripeCouponDuration.once,
        ),
    )

    assert resp.dollar_off == 1000
    assert resp.percentage_off is None

    coupon = await _fetch_coupon(
        stripe_client,
        resp.stripe_coupon_id,
        connect_opts,
    )
    assert coupon.valid is True
    assert coupon.amount_off == 1000
    assert coupon.percent_off is None
    assert coupon.duration == StripeCouponDuration.once.value


async def test_update_discount_name(
    discounts_service,
    gym_id,
    stripe_client,
    connect_opts,
):
    created = await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name="Old Name",
            discount_type=DiscountType.preset,
            percentage_off=15.0,
            duration=StripeCouponDuration.forever,
        ),
    )

    resp = await discounts_service.update_discount(
        DiscountUpdateRequest(
            discount_id=created.discount_id,
            gym_id=gym_id,
            data=DiscountUpdateData(discount_name="New Name"),
        ),
        background_tasks=BackgroundTasks(),
    )

    assert resp.discount_name == "New Name"

    # Stripe side: the service creates a fresh coupon on every update
    # (Stripe coupons are mostly immutable), so the stripe_coupon_id
    # on the response should differ from the original and the old
    # coupon should have been deleted.
    assert resp.stripe_coupon_id != created.stripe_coupon_id, (
        "update_discount should have swapped in a fresh Stripe coupon"
    )
    new_coupon = await _fetch_coupon(
        stripe_client,
        resp.stripe_coupon_id,
        connect_opts,
    )
    assert new_coupon.name == "New Name", (
        f"Stripe coupon {new_coupon.id} name={new_coupon.name!r} not updated"
    )
    assert new_coupon.valid is True

    with pytest.raises(stripe.InvalidRequestError):
        await _fetch_coupon(
            stripe_client,
            created.stripe_coupon_id,
            connect_opts,
        )


async def test_delete_discount(
    discounts_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    created = await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name="Delete Me",
            discount_type=DiscountType.preset,
            percentage_off=5.0,
            duration=StripeCouponDuration.forever,
        ),
    )

    await discounts_service.delete_discount(
        created.discount_id,
        gym_id,
        background_tasks=BackgroundTasks(),
    )

    # CRM side: row is soft-deleted (is_deleted = true).
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT is_deleted FROM gym_discounts_unfiltered "
                "WHERE discount_id = :id"
            ),
            {"id": str(created.discount_id)},
        )
        row = result.mappings().fetchone()

    assert row["is_deleted"] is True

    # Stripe side: coupon must be gone. Stripe ``coupons.retrieve`` on
    # a deleted coupon raises InvalidRequestError (404).
    with pytest.raises(stripe.InvalidRequestError):
        await _fetch_coupon(
            stripe_client,
            created.stripe_coupon_id,
            connect_opts,
        )
