"""Integration tests for PaymentsStripeSubscriptionService."""

import pytest

from src.payments.schema.payments_discount_schema import (
    PaymentsDiscountCreateRequest,
)
from src.payments.schema.payments_enums import StripeCouponDuration
from src.payments.schema.payments_membership_schema import (
    PaymentsMembershipCreateRequest,
    PaymentsMembershipPriceItem,
)
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerCreateRequest,
    PaymentsSubscriptionCancelRequest,
    PaymentsSubscriptionCreateRequest,
    PaymentsSubscriptionDesiredItem,
    PaymentsSubscriptionFreezeRequest,
    PaymentsSubscriptionUnfreezeRequest,
    PaymentsSubscriptionUpdateRequest,
    SubscriptionItemDiscount,
)

from schema.membership_plan import DurationUnit, PlanType

from tests.helpers.data_factory import create_payment_method
from tests.helpers.stripe_assertions import _coerce_coupon_id


# ── Helpers ─────────────────────────────────────────────────────


async def _setup_customer(members_service, stripe_client, stripe_account_id, connect_opts):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    resp = await members_service.create_customer(
        PaymentsCustomerCreateRequest(name="Sub Test", payment_method_id=pm_id),
        stripe_account_id,
    )
    return resp.stripe_customer_id


async def _setup_price(membership_service, stripe_account_id):
    resp = await membership_service.create_membership(
        PaymentsMembershipCreateRequest(
            plan_name="Sub Plan",
            prices=[
                PaymentsMembershipPriceItem(
                    unit_amount=5000,
                    plan_type=PlanType.recurring,
                    recurring_interval=DurationUnit.month,
                    recurring_interval_count=1,
                    is_default=True,
                ),
            ],
        ),
        stripe_account_id,
    )
    return resp.prices[0].stripe_price_id


# ── Tests ───────────────────────────────────────────────────────


async def test_create_subscription_single_item(
    subscription_service, members_service, membership_service,
    stripe_client, stripe_account_id, connect_opts,
):
    customer_id = await _setup_customer(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    price_id = await _setup_price(membership_service, stripe_account_id)

    resp = await subscription_service.create_subscription(
        PaymentsSubscriptionCreateRequest(
            stripe_customer_id=customer_id,
            items=[PaymentsSubscriptionDesiredItem(stripe_price_id=price_id)],
        ),
        stripe_account_id,
    )

    assert resp.stripe_subscription_id.startswith("sub_")
    assert resp.status == "active"
    assert len(resp.items) == 1
    assert resp.items[0].stripe_price_id == price_id

    sub = await stripe_client.client.v1.subscriptions.retrieve_async(
        resp.stripe_subscription_id,
        options=connect_opts,
    )
    assert sub.status == "active"
    assert len(sub["items"].data) == 1
    assert sub["items"].data[0].price.id == price_id


async def test_create_subscription_with_discount(
    subscription_service, members_service, membership_service,
    discount_service, stripe_client, stripe_account_id, connect_opts,
):
    customer_id = await _setup_customer(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    price_id = await _setup_price(membership_service, stripe_account_id)

    coupon = await discount_service.create_discount(
        PaymentsDiscountCreateRequest(
            discount_name="Sub Discount",
            percentage_off=20.0,
            duration=StripeCouponDuration.forever,
        ),
        stripe_account_id,
    )

    resp = await subscription_service.create_subscription(
        PaymentsSubscriptionCreateRequest(
            stripe_customer_id=customer_id,
            items=[PaymentsSubscriptionDesiredItem(stripe_price_id=price_id)],
            subscription_discounts=[
                SubscriptionItemDiscount(coupon=coupon.stripe_coupon_id),
            ],
        ),
        stripe_account_id,
    )

    assert resp.status == "active"
    assert len(resp.discounts) >= 1

    # Independent: retrieve the subscription with discounts expanded
    # and verify the coupon is attached. Stripe's `Subscription.discounts`
    # is a list whose elements are either raw discount ids (strings)
    # or expanded Discount objects with `.coupon` pointing at a Coupon.
    sub = await stripe_client.client.v1.subscriptions.retrieve_async(
        resp.stripe_subscription_id,
        options=connect_opts,
        params={"expand": ["discounts"]},
    )
    sub_coupon_ids: set[str] = set()
    for disc in sub.discounts or []:
        coupon_id = _coerce_coupon_id(disc)
        if coupon_id is not None:
            sub_coupon_ids.add(coupon_id)
    assert coupon.stripe_coupon_id in sub_coupon_ids, (
        f"Expected coupon {coupon.stripe_coupon_id} on subscription "
        f"{resp.stripe_subscription_id}, got {sub_coupon_ids}"
    )


async def test_update_subscription_add_item(
    subscription_service, members_service, membership_service,
    stripe_client, stripe_account_id, connect_opts,
):
    customer_id = await _setup_customer(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    price1 = await _setup_price(membership_service, stripe_account_id)
    price2 = await _setup_price(membership_service, stripe_account_id)

    created = await subscription_service.create_subscription(
        PaymentsSubscriptionCreateRequest(
            stripe_customer_id=customer_id,
            items=[PaymentsSubscriptionDesiredItem(stripe_price_id=price1)],
        ),
        stripe_account_id,
    )

    resp = await subscription_service.update_subscription(
        PaymentsSubscriptionUpdateRequest(
            stripe_subscription_id=created.stripe_subscription_id,
            stripe_customer_id=customer_id,
            items=[
                PaymentsSubscriptionDesiredItem(
                    stripe_price_id=price1,
                    stripe_item_id=created.items[0].stripe_subscription_item_id,
                ),
                PaymentsSubscriptionDesiredItem(stripe_price_id=price2),
            ],
            proration_behavior="none",
        ),
        stripe_account_id,
    )

    assert len(resp.items) == 2

    sub = await stripe_client.client.v1.subscriptions.retrieve_async(
        created.stripe_subscription_id,
        options=connect_opts,
    )
    assert len(sub["items"].data) == 2


async def test_update_subscription_remove_item(
    subscription_service, members_service, membership_service,
    stripe_client, stripe_account_id, connect_opts,
):
    customer_id = await _setup_customer(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    price1 = await _setup_price(membership_service, stripe_account_id)
    price2 = await _setup_price(membership_service, stripe_account_id)

    created = await subscription_service.create_subscription(
        PaymentsSubscriptionCreateRequest(
            stripe_customer_id=customer_id,
            items=[
                PaymentsSubscriptionDesiredItem(stripe_price_id=price1),
                PaymentsSubscriptionDesiredItem(stripe_price_id=price2),
            ],
        ),
        stripe_account_id,
    )
    assert len(created.items) == 2

    keep_item = created.items[0]
    resp = await subscription_service.update_subscription(
        PaymentsSubscriptionUpdateRequest(
            stripe_subscription_id=created.stripe_subscription_id,
            stripe_customer_id=customer_id,
            items=[
                PaymentsSubscriptionDesiredItem(
                    stripe_price_id=keep_item.stripe_price_id,
                    stripe_item_id=keep_item.stripe_subscription_item_id,
                ),
            ],
            proration_behavior="none",
        ),
        stripe_account_id,
    )

    assert len(resp.items) == 1
    assert resp.items[0].stripe_price_id == keep_item.stripe_price_id

    sub = await stripe_client.client.v1.subscriptions.retrieve_async(
        created.stripe_subscription_id,
        options=connect_opts,
    )
    assert len(sub["items"].data) == 1
    assert sub["items"].data[0].price.id == keep_item.stripe_price_id


async def test_cancel_subscription_immediately(
    subscription_service, members_service, membership_service,
    stripe_client, stripe_account_id, connect_opts,
):
    customer_id = await _setup_customer(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    price_id = await _setup_price(membership_service, stripe_account_id)

    created = await subscription_service.create_subscription(
        PaymentsSubscriptionCreateRequest(
            stripe_customer_id=customer_id,
            items=[PaymentsSubscriptionDesiredItem(stripe_price_id=price_id)],
        ),
        stripe_account_id,
    )

    resp = await subscription_service.cancel_subscription(
        PaymentsSubscriptionCancelRequest(
            stripe_subscription_id=created.stripe_subscription_id,
            cancel_at_period_end=False,
        ),
        stripe_account_id,
    )

    assert resp.status == "canceled"

    sub = await stripe_client.client.v1.subscriptions.retrieve_async(
        created.stripe_subscription_id,
        options=connect_opts,
    )
    assert sub.status == "canceled"


async def test_cancel_at_period_end(
    subscription_service, members_service, membership_service,
    stripe_client, stripe_account_id, connect_opts,
):
    customer_id = await _setup_customer(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    price_id = await _setup_price(membership_service, stripe_account_id)

    created = await subscription_service.create_subscription(
        PaymentsSubscriptionCreateRequest(
            stripe_customer_id=customer_id,
            items=[PaymentsSubscriptionDesiredItem(stripe_price_id=price_id)],
        ),
        stripe_account_id,
    )

    resp = await subscription_service.cancel_subscription(
        PaymentsSubscriptionCancelRequest(
            stripe_subscription_id=created.stripe_subscription_id,
            cancel_at_period_end=True,
        ),
        stripe_account_id,
    )

    assert resp.status == "active"
    assert resp.cancel_at_period_end is True

    sub = await stripe_client.client.v1.subscriptions.retrieve_async(
        created.stripe_subscription_id,
        options=connect_opts,
    )
    assert sub.status == "active"
    assert sub.cancel_at_period_end is True


async def test_freeze_subscription(
    subscription_service, members_service, membership_service,
    stripe_client, stripe_account_id, connect_opts,
):
    customer_id = await _setup_customer(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    price_id = await _setup_price(membership_service, stripe_account_id)

    created = await subscription_service.create_subscription(
        PaymentsSubscriptionCreateRequest(
            stripe_customer_id=customer_id,
            items=[PaymentsSubscriptionDesiredItem(stripe_price_id=price_id)],
        ),
        stripe_account_id,
    )

    resp = await subscription_service.freeze_subscription(
        PaymentsSubscriptionFreezeRequest(
            stripe_subscription_id=created.stripe_subscription_id,
        ),
        stripe_account_id,
    )

    assert resp.stripe_subscription_id == created.stripe_subscription_id
    assert resp.pause_collection_behavior is not None

    sub = await stripe_client.client.v1.subscriptions.retrieve_async(
        created.stripe_subscription_id,
        options=connect_opts,
    )
    assert sub.pause_collection is not None


async def test_unfreeze_subscription(
    subscription_service, members_service, membership_service,
    stripe_client, stripe_account_id, connect_opts,
):
    customer_id = await _setup_customer(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    price_id = await _setup_price(membership_service, stripe_account_id)

    created = await subscription_service.create_subscription(
        PaymentsSubscriptionCreateRequest(
            stripe_customer_id=customer_id,
            items=[PaymentsSubscriptionDesiredItem(stripe_price_id=price_id)],
        ),
        stripe_account_id,
    )
    await subscription_service.freeze_subscription(
        PaymentsSubscriptionFreezeRequest(
            stripe_subscription_id=created.stripe_subscription_id,
        ),
        stripe_account_id,
    )

    resp = await subscription_service.unfreeze_subscription(
        PaymentsSubscriptionUnfreezeRequest(
            stripe_subscription_id=created.stripe_subscription_id,
        ),
        stripe_account_id,
    )

    assert resp.status == "active"

    sub = await stripe_client.client.v1.subscriptions.retrieve_async(
        created.stripe_subscription_id,
        options=connect_opts,
    )
    assert sub.status == "active"
    assert sub.pause_collection is None


async def test_preview_create_subscription(
    subscription_service, members_service, membership_service,
    stripe_client, stripe_account_id, connect_opts,
):
    customer_id = await _setup_customer(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    price_id = await _setup_price(membership_service, stripe_account_id)

    # prorate=False so the preview reflects a plain full-cycle
    # invoice at the anchor date (no partial-period proration).
    # Default prorate=True would trigger ``always_invoice`` and
    # return the prorated partial-period amount instead, which
    # depends on wall-clock time and is not deterministic here.
    resp = await subscription_service.preview_create_subscription(
        PaymentsSubscriptionCreateRequest(
            stripe_customer_id=customer_id,
            items=[
                PaymentsSubscriptionDesiredItem(
                    stripe_price_id=price_id,
                    prorate=False,
                ),
            ],
        ),
        stripe_account_id,
    )

    assert resp.amount_due == 5000
    assert len(resp.lines) >= 1


async def test_get_subscription_item(
    subscription_service, members_service, membership_service,
    stripe_client, stripe_account_id, connect_opts,
):
    customer_id = await _setup_customer(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    price_id = await _setup_price(membership_service, stripe_account_id)

    created = await subscription_service.create_subscription(
        PaymentsSubscriptionCreateRequest(
            stripe_customer_id=customer_id,
            items=[PaymentsSubscriptionDesiredItem(stripe_price_id=price_id)],
        ),
        stripe_account_id,
    )
    item_id = created.items[0].stripe_subscription_item_id

    resp = await subscription_service.get_subscription_item(
        item_id,
        stripe_account_id,
    )

    assert resp.stripe_subscription_item_id == item_id
    assert resp.stripe_price_id == price_id
