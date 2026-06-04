"""Integration tests for PaymentsStripeDiscountService.

Every success path independently re-fetches the coupon from Stripe
to catch response-mapper drift (service claims X, Stripe says Y).
"""

from uuid import uuid4

import pytest
import stripe

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.metadata.stripe_coupon_metadata import (
    StripeCouponMetadata,
)
from src.payments.schema.payments_discount_schema import (
    PaymentsDiscountCreateRequest,
    PaymentsDiscountDeleteRequest,
    PaymentsDiscountUpdateRequest,
)
from src.payments.schema.payments_enums import StripeCouponDuration


def _coupon_metadata() -> StripeCouponMetadata:
    return StripeCouponMetadata(
        crm_discount_id=uuid4(),
        gym_id=uuid4(),
    )


async def test_create_percentage_discount(
    discount_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
):
    resp = await discount_service.create_discount(
        PaymentsDiscountCreateRequest(
            discount_name="10% Off",
            percentage_off=10.0,
            duration=StripeCouponDuration.forever,
            metadata=_coupon_metadata(),
        ),
        stripe_account_id,
    )

    assert resp.stripe_coupon_id
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
):
    resp = await discount_service.create_discount(
        PaymentsDiscountCreateRequest(
            discount_name="$5 Off",
            amount_off=500,
            currency="usd",
            duration=StripeCouponDuration.once,
            metadata=_coupon_metadata(),
        ),
        stripe_account_id,
    )

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


async def test_update_discount_name(
    discount_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
):
    created = await discount_service.create_discount(
        PaymentsDiscountCreateRequest(
            discount_name="Original Name",
            percentage_off=15.0,
            duration=StripeCouponDuration.forever,
            metadata=_coupon_metadata(),
        ),
        stripe_account_id,
    )

    resp = await discount_service.update_discount(
        PaymentsDiscountUpdateRequest(
            stripe_coupon_id=created.stripe_coupon_id,
            discount_name="Updated Name",
            metadata=_coupon_metadata(),
        ),
        stripe_account_id,
    )

    assert resp.name == "Updated Name"
    assert resp.percentage_off == 15.0

    # Stripe allows updating the name in place on a coupon — verify.
    coupon = await stripe_client.client.v1.coupons.retrieve_async(
        created.stripe_coupon_id,
        options=connect_opts,
    )
    assert coupon.name == "Updated Name"
    assert coupon.percent_off == 15.0


async def test_delete_discount(
    discount_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
):
    created = await discount_service.create_discount(
        PaymentsDiscountCreateRequest(
            discount_name="Delete Me",
            percentage_off=5.0,
            duration=StripeCouponDuration.forever,
            metadata=_coupon_metadata(),
        ),
        stripe_account_id,
    )

    await discount_service.delete_discount(
        PaymentsDiscountDeleteRequest(
            stripe_coupon_id=created.stripe_coupon_id,
        ),
        stripe_account_id,
    )

    # Service layer must see it as gone.
    with pytest.raises(PaymentsResourceNotFoundError):
        opts = discount_service._client.connect_opts(stripe_account_id)
        await discount_service.retrieve_discount(
            created.stripe_coupon_id,
            opts,
        )

    # Independent: raw Stripe client must also 404.
    with pytest.raises(stripe.InvalidRequestError):
        await stripe_client.client.v1.coupons.retrieve_async(
            created.stripe_coupon_id,
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
