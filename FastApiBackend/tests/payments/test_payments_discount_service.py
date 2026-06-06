"""Integration tests for PaymentsStripeDiscountService.

Coupons are created under a **caller-supplied deterministic id** (the sync's
value signature) and carry no CRM metadata. Every success path independently
re-fetches the coupon from Stripe to catch response-mapper drift (service claims
X, Stripe says Y).
"""

from uuid import uuid4

import pytest
import stripe

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_discount_schema import (
    PaymentsDiscountCreateRequest,
    PaymentsDiscountDeleteRequest,
)
from src.payments.schema.payments_enums import StripeCouponDuration


def _coupon_id(prefix: str = "test") -> str:
    """A unique deterministic-style coupon id (unique per run, no leftovers)."""
    return f"{prefix}_{uuid4().hex[:16]}"


async def test_create_percentage_discount(
    discount_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    coupon_id = _coupon_id("pct")
    resp = await discount_service.create_discount(
        PaymentsDiscountCreateRequest(
            coupon_id=coupon_id,
            discount_name="10% Off",
            percentage_off=10.0,
            duration=StripeCouponDuration.forever,
        ),
        stripe_account_id,
    )
    created.track_coupon(resp.stripe_coupon_id)

    assert resp.stripe_coupon_id == coupon_id
    assert resp.name == "10% Off"
    assert resp.percentage_off == 10.0
    assert resp.amount_off is None
    assert resp.valid is True
    assert resp.duration == StripeCouponDuration.forever

    coupon = await stripe_client.client.v1.coupons.retrieve_async(
        resp.stripe_coupon_id,
        options=connect_opts,
    )
    assert coupon.valid is True
    assert coupon.percent_off == 10.0
    assert coupon.amount_off is None
    assert coupon.duration == "forever"


async def test_create_amount_discount(
    discount_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    coupon_id = _coupon_id("amt")
    resp = await discount_service.create_discount(
        PaymentsDiscountCreateRequest(
            coupon_id=coupon_id,
            discount_name="$5 Off",
            amount_off=500,
            currency="usd",
            duration=StripeCouponDuration.once,
        ),
        stripe_account_id,
    )
    created.track_coupon(resp.stripe_coupon_id)

    assert resp.stripe_coupon_id == coupon_id
    assert resp.amount_off == 500
    assert resp.percentage_off is None
    assert resp.currency == "usd"
    assert resp.duration == StripeCouponDuration.once

    coupon = await stripe_client.client.v1.coupons.retrieve_async(
        resp.stripe_coupon_id,
        options=connect_opts,
    )
    assert coupon.amount_off == 500
    assert coupon.percent_off is None
    assert coupon.currency == "usd"
    assert coupon.duration == "once"


async def test_create_is_idempotent_on_coupon_id(
    discount_service,
    stripe_account_id,
    created,
):
    """A second create of the same deterministic id returns the existing coupon
    instead of raising — the find-or-create concurrency guarantee."""
    coupon_id = _coupon_id("idem")
    request = PaymentsDiscountCreateRequest(
        coupon_id=coupon_id,
        discount_name="Idempotent",
        percentage_off=20.0,
        duration=StripeCouponDuration.forever,
    )

    first = await discount_service.create_discount(request, stripe_account_id)
    created.track_coupon(first.stripe_coupon_id)
    second = await discount_service.create_discount(request, stripe_account_id)

    assert second.stripe_coupon_id == first.stripe_coupon_id == coupon_id
    assert second.percentage_off == 20.0


async def test_find_discount_returns_none_when_absent(
    discount_service,
    stripe_account_id,
):
    """find_discount is the non-raising lookup: absent id → None."""
    assert (
        await discount_service.find_discount(
            _coupon_id("missing"), stripe_account_id
        )
        is None
    )


async def test_find_discount_returns_mapped_when_present(
    discount_service,
    stripe_account_id,
    created,
):
    coupon_id = _coupon_id("find")
    await discount_service.create_discount(
        PaymentsDiscountCreateRequest(
            coupon_id=coupon_id,
            discount_name="Findable",
            percentage_off=15.0,
            duration=StripeCouponDuration.forever,
        ),
        stripe_account_id,
    )
    created.track_coupon(coupon_id)

    found = await discount_service.find_discount(coupon_id, stripe_account_id)
    assert found is not None
    assert found.stripe_coupon_id == coupon_id
    assert found.percentage_off == 15.0


async def test_delete_discount(
    discount_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    coupon_id = _coupon_id("del")
    created_resp = await discount_service.create_discount(
        PaymentsDiscountCreateRequest(
            coupon_id=coupon_id,
            discount_name="Delete Me",
            percentage_off=5.0,
            duration=StripeCouponDuration.forever,
        ),
        stripe_account_id,
    )
    created.track_coupon(created_resp.stripe_coupon_id)

    await discount_service.delete_discount(
        PaymentsDiscountDeleteRequest(
            stripe_coupon_id=created_resp.stripe_coupon_id,
        ),
        stripe_account_id,
    )

    # Service layer must see it as gone.
    with pytest.raises(PaymentsResourceNotFoundError):
        opts = discount_service._client.connect_opts(stripe_account_id)
        await discount_service.retrieve_discount(
            created_resp.stripe_coupon_id,
            opts,
        )

    # Independent: raw Stripe client must also 404.
    with pytest.raises(stripe.InvalidRequestError):
        await stripe_client.client.v1.coupons.retrieve_async(
            created_resp.stripe_coupon_id,
            options=connect_opts,
        )


async def test_delete_nonexistent_raises(discount_service, stripe_account_id):
    with pytest.raises(PaymentsResourceNotFoundError):
        await discount_service.delete_discount(
            PaymentsDiscountDeleteRequest(
                stripe_coupon_id="coupon_nonexistent_000",
            ),
            stripe_account_id,
        )
