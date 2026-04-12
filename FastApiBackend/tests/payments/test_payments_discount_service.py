"""Integration tests for PaymentsStripeDiscountService."""

import pytest

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_discount_schema import (
    PaymentsDiscountCreateRequest,
    PaymentsDiscountUpdateRequest,
)
from src.payments.schema.payments_enums import StripeCouponDuration


async def test_create_percentage_discount(discount_service, stripe_account_id):
    resp = await discount_service.create_discount(
        PaymentsDiscountCreateRequest(
            discount_name="10% Off",
            percentage_off=10.0,
            duration=StripeCouponDuration.forever,
        ),
        stripe_account_id,
    )

    assert resp.stripe_coupon_id
    assert resp.name == "10% Off"
    assert resp.percentage_off == 10.0
    assert resp.amount_off is None
    assert resp.valid is True
    assert resp.duration == StripeCouponDuration.forever


async def test_create_amount_discount(discount_service, stripe_account_id):
    resp = await discount_service.create_discount(
        PaymentsDiscountCreateRequest(
            discount_name="$5 Off",
            amount_off=500,
            currency="usd",
            duration=StripeCouponDuration.once,
        ),
        stripe_account_id,
    )

    assert resp.amount_off == 500
    assert resp.percentage_off is None
    assert resp.currency == "usd"
    assert resp.duration == StripeCouponDuration.once


async def test_update_discount_name(discount_service, stripe_account_id):
    created = await discount_service.create_discount(
        PaymentsDiscountCreateRequest(
            discount_name="Original Name",
            percentage_off=15.0,
            duration=StripeCouponDuration.forever,
        ),
        stripe_account_id,
    )

    resp = await discount_service.update_discount(
        PaymentsDiscountUpdateRequest(
            stripe_coupon_id=created.stripe_coupon_id,
            discount_name="Updated Name",
        ),
        stripe_account_id,
    )

    assert resp.name == "Updated Name"
    assert resp.percentage_off == 15.0


async def test_delete_discount(discount_service, stripe_account_id):
    created = await discount_service.create_discount(
        PaymentsDiscountCreateRequest(
            discount_name="Delete Me",
            percentage_off=5.0,
            duration=StripeCouponDuration.forever,
        ),
        stripe_account_id,
    )

    await discount_service.delete_discount(
        created.stripe_coupon_id,
        stripe_account_id,
    )

    with pytest.raises(PaymentsResourceNotFoundError):
        opts = discount_service._client.connect_opts(stripe_account_id)
        await discount_service.retrieve_discount(
            created.stripe_coupon_id, opts,
        )


async def test_delete_nonexistent_raises(discount_service, stripe_account_id):
    with pytest.raises(PaymentsResourceNotFoundError):
        await discount_service.delete_discount(
            "coupon_nonexistent_000",
            stripe_account_id,
        )
