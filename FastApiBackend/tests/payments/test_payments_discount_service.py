"""Integration tests for PaymentsStripeDiscountService.

Coupons are minted under a **deterministic id** derived from the value
(``pct_<bps>_<mode>`` / ``amt_<cents>_<mode>``) by ``find_or_create_for_value`` —
the single value→coupon path (no public raw-create). Every success path
re-fetches the coupon from Stripe to catch response-mapper drift (service claims
X, Stripe says Y).
"""

import pytest
import stripe
from schema.gym_discount import DiscountMode

import src.shared.db_schema_path  # noqa: F401
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_discount_schema import (
    PaymentsCouponValue,
    PaymentsDiscountDeleteRequest,
)


async def test_find_or_create_percentage_coupon(
    discount_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    value = PaymentsCouponValue(
        discount_mode=DiscountMode.ongoing, percentage_off=10.0
    )
    coupon_id = await discount_service.find_or_create_for_value(
        value, stripe_account_id
    )
    created.track_coupon(coupon_id)

    assert coupon_id == "pct_1000_ongoing"
    coupon = await stripe_client.client.v1.coupons.retrieve_async(
        coupon_id, options=connect_opts
    )
    assert coupon.valid is True
    assert coupon.percent_off == 10.0
    assert coupon.amount_off is None
    assert coupon.duration == "forever"


async def test_find_or_create_amount_coupon(
    discount_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    value = PaymentsCouponValue(discount_mode=DiscountMode.once, dollar_off=500)
    coupon_id = await discount_service.find_or_create_for_value(
        value, stripe_account_id
    )
    created.track_coupon(coupon_id)

    assert coupon_id == "amt_500_once"
    coupon = await stripe_client.client.v1.coupons.retrieve_async(
        coupon_id, options=connect_opts
    )
    assert coupon.amount_off == 500
    assert coupon.percent_off is None
    assert coupon.currency == "usd"
    assert coupon.duration == "once"


async def test_find_or_create_is_idempotent(
    discount_service,
    stripe_account_id,
    created,
):
    """A second resolve of the same value returns the same coupon id, no error
    — the deterministic-id find-or-create concurrency guarantee."""
    value = PaymentsCouponValue(
        discount_mode=DiscountMode.ongoing, percentage_off=20.0
    )
    first = await discount_service.find_or_create_for_value(value, stripe_account_id)
    created.track_coupon(first)
    second = await discount_service.find_or_create_for_value(
        value, stripe_account_id
    )
    assert first == second == "pct_2000_ongoing"


async def test_find_or_create_replaces_mismatched_coupon(
    discount_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    """A coupon already under the deterministic id with the WRONG value is
    deleted + recreated correct (Stripe coupons are immutable)."""
    coupon_id = "pct_2500_ongoing"
    await stripe_client.client.v1.coupons.create_async(
        params={"id": coupon_id, "percent_off": 99.0, "duration": "forever"},
        options=discount_service._client.connect_opts(stripe_account_id),
    )
    created.track_coupon(coupon_id)

    result = await discount_service.find_or_create_for_value(
        PaymentsCouponValue(discount_mode=DiscountMode.ongoing, percentage_off=25.0),
        stripe_account_id,
    )

    assert result == coupon_id
    coupon = await stripe_client.client.v1.coupons.retrieve_async(
        coupon_id, options=connect_opts
    )
    assert coupon.percent_off == 25.0  # replaced, not the seeded 99.0


async def test_find_discount_returns_none_when_absent(
    discount_service,
    stripe_account_id,
):
    """find_discount is the non-raising lookup: absent id → None."""
    assert (
        await discount_service.find_discount(
            "amt_999999_once", stripe_account_id
        )
        is None
    )


async def test_delete_discount(
    discount_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    coupon_id = await discount_service.find_or_create_for_value(
        PaymentsCouponValue(discount_mode=DiscountMode.ongoing, percentage_off=5.0),
        stripe_account_id,
    )
    created.track_coupon(coupon_id)

    await discount_service.delete_discount(
        PaymentsDiscountDeleteRequest(stripe_coupon_id=coupon_id),
        stripe_account_id,
    )

    # Service layer must see it as gone.
    with pytest.raises(PaymentsResourceNotFoundError):
        opts = discount_service._client.connect_opts(stripe_account_id)
        await discount_service.retrieve_discount(coupon_id, opts)

    # Independent: raw Stripe client must also 404.
    with pytest.raises(stripe.InvalidRequestError):
        await stripe_client.client.v1.coupons.retrieve_async(
            coupon_id, options=connect_opts
        )


async def test_delete_nonexistent_raises(discount_service, stripe_account_id):
    with pytest.raises(PaymentsResourceNotFoundError):
        await discount_service.delete_discount(
            PaymentsDiscountDeleteRequest(stripe_coupon_id="coupon_nonexistent_000"),
            stripe_account_id,
        )
