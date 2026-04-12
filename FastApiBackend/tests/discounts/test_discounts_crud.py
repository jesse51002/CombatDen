"""Integration tests for DiscountsService (lighter coverage)."""

from starlette.background import BackgroundTasks

from schema.gym_discount import DiscountType

from src.discounts.schema.discounts_schema import (
    DiscountCreateRequest,
    DiscountUpdateData,
    DiscountUpdateRequest,
)
from src.payments.schema.payments_enums import StripeCouponDuration


async def test_create_percentage_discount(discounts_service, gym_id):
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


async def test_create_dollar_discount(discounts_service, gym_id):
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


async def test_update_discount_name(discounts_service, gym_id):
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
        reconciliation_service=None,
    )

    assert resp.discount_name == "New Name"


async def test_delete_discount(discounts_service, db_pool, gym_id):
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
        reconciliation_service=None,
    )

    # Verify the discount is soft-deleted (is_deleted = true)
    from sqlalchemy import text

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
