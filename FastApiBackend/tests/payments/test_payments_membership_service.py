"""Integration tests for PaymentsStripeMembershipService."""

from uuid import uuid4

from schema.membership_plan import DurationUnit, PlanType

from src.payments.schema.metadata.stripe_product_metadata import (
    StripeProductMetadata,
)
from src.payments.schema.payments_membership_schema import (
    PaymentsMembershipCreateRequest,
    PaymentsMembershipDeactivateRequest,
    PaymentsMembershipPriceItem,
    PaymentsMembershipUpdateRequest,
)


def _product_metadata() -> StripeProductMetadata:
    return StripeProductMetadata(
        plan_id=uuid4(),
        gym_id=uuid4(),
    )


async def test_create_membership_with_default_price(
    membership_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    resp = await membership_service.create_membership(
        PaymentsMembershipCreateRequest(
            plan_name="Basic Monthly",
            prices=[
                PaymentsMembershipPriceItem(
                    unit_amount=5000,
                    plan_type=PlanType.recurring,
                    recurring_interval=DurationUnit.month,
                    recurring_interval_count=1,
                    is_default=True,
                ),
            ],
            metadata=_product_metadata(),
        ),
        stripe_account_id,
    )
    created.track_product(resp.stripe_product_id)
    for p in resp.prices:
        created.track_price(p.stripe_price_id)

    assert resp.stripe_product_id.startswith("prod_")
    assert resp.active is True
    assert resp.name == "Basic Monthly"
    assert len(resp.prices) == 1
    assert resp.prices[0].unit_amount == 5000

    product = await stripe_client.client.v1.products.retrieve_async(
        resp.stripe_product_id,
        options=connect_opts,
    )
    assert product.active is True
    assert product.name == "Basic Monthly"

    price = await stripe_client.client.v1.prices.retrieve_async(
        resp.prices[0].stripe_price_id,
        options=connect_opts,
    )
    assert price.active is True
    assert price.unit_amount == 5000


async def test_create_membership_multiple_prices(
    membership_service,
    stripe_account_id,
    created,
):
    resp = await membership_service.create_membership(
        PaymentsMembershipCreateRequest(
            plan_name="Tiered Plan",
            prices=[
                PaymentsMembershipPriceItem(
                    unit_amount=3000,
                    plan_type=PlanType.recurring,
                    recurring_interval=DurationUnit.month,
                    recurring_interval_count=1,
                    is_default=True,
                ),
                PaymentsMembershipPriceItem(
                    unit_amount=8000,
                    plan_type=PlanType.recurring,
                    recurring_interval=DurationUnit.month,
                    recurring_interval_count=1,
                ),
            ],
            metadata=_product_metadata(),
        ),
        stripe_account_id,
    )
    created.track_product(resp.stripe_product_id)
    for p in resp.prices:
        created.track_price(p.stripe_price_id)

    assert len(resp.prices) == 2
    amounts = {p.unit_amount for p in resp.prices}
    assert amounts == {3000, 8000}


async def test_update_membership_add_price(
    membership_service,
    stripe_account_id,
    created,
):
    created_resp = await membership_service.create_membership(
        PaymentsMembershipCreateRequest(
            plan_name="Upgradeable",
            prices=[
                PaymentsMembershipPriceItem(
                    unit_amount=4000,
                    plan_type=PlanType.recurring,
                    recurring_interval=DurationUnit.month,
                    recurring_interval_count=1,
                    is_default=True,
                ),
            ],
            metadata=_product_metadata(),
        ),
        stripe_account_id,
    )
    created.track_product(created_resp.stripe_product_id)
    for p in created_resp.prices:
        created.track_price(p.stripe_price_id)

    resp = await membership_service.update_membership(
        PaymentsMembershipUpdateRequest(
            stripe_product_id=created_resp.stripe_product_id,
            plan_name="Upgradeable",
            prices=[
                PaymentsMembershipPriceItem(
                    stripe_price_id=created_resp.prices[0].stripe_price_id,
                    is_default=True,
                ),
                PaymentsMembershipPriceItem(
                    unit_amount=9000,
                    plan_type=PlanType.recurring,
                    recurring_interval=DurationUnit.month,
                    recurring_interval_count=1,
                ),
            ],
            metadata=_product_metadata(),
        ),
        stripe_account_id,
    )
    # Track any newly created prices from the update
    existing_price_ids = {p.stripe_price_id for p in created_resp.prices}
    for p in resp.prices:
        if p.stripe_price_id not in existing_price_ids:
            created.track_price(p.stripe_price_id)

    assert len(resp.prices) == 2
    active_prices = [p for p in resp.prices if p.active]
    assert len(active_prices) == 2


async def test_update_membership_keeps_omitted_prices_active(
    membership_service,
    stripe_account_id,
    created,
):
    """update_membership never deactivates a Stripe price.

    The DB (`membership_plan_prices.is_active`) gates which price is current, so
    every Stripe price stays active — archiving an omitted price would break an
    in-progress subscription migration. An omitted price therefore stays active.
    """
    created_resp = await membership_service.create_membership(
        PaymentsMembershipCreateRequest(
            plan_name="Two Tier",
            prices=[
                PaymentsMembershipPriceItem(
                    unit_amount=3000,
                    plan_type=PlanType.recurring,
                    recurring_interval=DurationUnit.month,
                    recurring_interval_count=1,
                    is_default=True,
                ),
                PaymentsMembershipPriceItem(
                    unit_amount=6000,
                    plan_type=PlanType.recurring,
                    recurring_interval=DurationUnit.month,
                    recurring_interval_count=1,
                ),
            ],
            metadata=_product_metadata(),
        ),
        stripe_account_id,
    )
    created.track_product(created_resp.stripe_product_id)
    for p in created_resp.prices:
        created.track_price(p.stripe_price_id)

    keep_price = created_resp.prices[0]

    resp = await membership_service.update_membership(
        PaymentsMembershipUpdateRequest(
            stripe_product_id=created_resp.stripe_product_id,
            plan_name="Two Tier",
            prices=[
                PaymentsMembershipPriceItem(
                    stripe_price_id=keep_price.stripe_price_id,
                    is_default=True,
                ),
            ],
            metadata=_product_metadata(),
        ),
        stripe_account_id,
    )

    # Both prices remain active — the omitted one is NOT deactivated.
    active_ids = {p.stripe_price_id for p in resp.prices if p.active}
    assert all(p.active for p in resp.prices)
    assert keep_price.stripe_price_id in active_ids
    assert len(active_ids) == 2


async def test_deactivate_membership(
    membership_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    created_resp = await membership_service.create_membership(
        PaymentsMembershipCreateRequest(
            plan_name="Deactivate Me",
            prices=[
                PaymentsMembershipPriceItem(
                    unit_amount=2000,
                    plan_type=PlanType.recurring,
                    recurring_interval=DurationUnit.month,
                    recurring_interval_count=1,
                    is_default=True,
                ),
            ],
            metadata=_product_metadata(),
        ),
        stripe_account_id,
    )
    created.track_product(created_resp.stripe_product_id)
    for p in created_resp.prices:
        created.track_price(p.stripe_price_id)

    resp = await membership_service.deactivate_membership(
        PaymentsMembershipDeactivateRequest(
            stripe_product_id=created_resp.stripe_product_id,
        ),
        stripe_account_id,
    )

    assert resp.active is False

    product = await stripe_client.client.v1.products.retrieve_async(
        created_resp.stripe_product_id,
        options=connect_opts,
    )
    assert product.active is False
