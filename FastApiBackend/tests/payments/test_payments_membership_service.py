"""Integration tests for PaymentsStripeMembershipService."""

from src.payments.schema.payments_membership_schema import (
    PaymentsMembershipCreateRequest,
    PaymentsMembershipDeactivateRequest,
    PaymentsMembershipPriceItem,
    PaymentsMembershipUpdateRequest,
)

from schema.membership_plan import DurationUnit, PlanType


async def test_create_membership_with_default_price(
    membership_service, stripe_account_id,
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
        ),
        stripe_account_id,
    )

    assert resp.stripe_product_id.startswith("prod_")
    assert resp.active is True
    assert resp.name == "Basic Monthly"
    assert len(resp.prices) == 1
    assert resp.prices[0].unit_amount == 5000


async def test_create_membership_multiple_prices(
    membership_service, stripe_account_id,
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
        ),
        stripe_account_id,
    )

    assert len(resp.prices) == 2
    amounts = {p.unit_amount for p in resp.prices}
    assert amounts == {3000, 8000}


async def test_update_membership_add_price(
    membership_service, stripe_account_id,
):
    created = await membership_service.create_membership(
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
        ),
        stripe_account_id,
    )

    resp = await membership_service.update_membership(
        PaymentsMembershipUpdateRequest(
            stripe_product_id=created.stripe_product_id,
            plan_name="Upgradeable",
            prices=[
                PaymentsMembershipPriceItem(
                    stripe_price_id=created.prices[0].stripe_price_id,
                    is_default=True,
                ),
                PaymentsMembershipPriceItem(
                    unit_amount=9000,
                    plan_type=PlanType.recurring,
                    recurring_interval=DurationUnit.month,
                    recurring_interval_count=1,
                ),
            ],
        ),
        stripe_account_id,
    )

    assert len(resp.prices) == 2
    active_prices = [p for p in resp.prices if p.active]
    assert len(active_prices) == 2


async def test_update_membership_deactivate_omitted_prices(
    membership_service, stripe_account_id,
):
    created = await membership_service.create_membership(
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
        ),
        stripe_account_id,
    )
    keep_price = created.prices[0]

    resp = await membership_service.update_membership(
        PaymentsMembershipUpdateRequest(
            stripe_product_id=created.stripe_product_id,
            plan_name="Two Tier",
            prices=[
                PaymentsMembershipPriceItem(
                    stripe_price_id=keep_price.stripe_price_id,
                    is_default=True,
                ),
            ],
        ),
        stripe_account_id,
    )

    active_prices = [p for p in resp.prices if p.active]
    inactive_prices = [p for p in resp.prices if not p.active]
    assert len(active_prices) == 1
    assert len(inactive_prices) == 1
    assert active_prices[0].stripe_price_id == keep_price.stripe_price_id


async def test_deactivate_membership(
    membership_service, stripe_account_id,
):
    created = await membership_service.create_membership(
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
        ),
        stripe_account_id,
    )

    resp = await membership_service.deactivate_membership(
        PaymentsMembershipDeactivateRequest(
            stripe_product_id=created.stripe_product_id,
        ),
        stripe_account_id,
    )

    assert resp.active is False
