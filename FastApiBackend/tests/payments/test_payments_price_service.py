"""Integration tests for PaymentsStripePriceService."""

import pytest

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_membership_schema import (
    PaymentsMembershipCreateRequest,
    PaymentsMembershipPriceItem,
)
from src.payments.schema.payments_price_schema import (
    PaymentsPriceCreateRequest,
    PaymentsPriceDeactivateRequest,
)

from schema.membership_plan import DurationUnit, PlanType


# ── Helpers ─────────────────────────────────────────────────────


async def _create_product(membership_service, stripe_account_id):
    """Create a bare Stripe product for price tests."""
    resp = await membership_service.create_membership(
        PaymentsMembershipCreateRequest(
            plan_name="Price Test Product",
            prices=[
                PaymentsMembershipPriceItem(
                    unit_amount=1000,
                    plan_type=PlanType.recurring,
                    recurring_interval=DurationUnit.month,
                    recurring_interval_count=1,
                    is_default=True,
                ),
            ],
        ),
        stripe_account_id,
    )
    return resp.stripe_product_id


# ── Tests ───────────────────────────────────────────────────────


async def test_create_recurring_price(
    price_service, membership_service, stripe_account_id,
):
    product_id = await _create_product(membership_service, stripe_account_id)

    resp = await price_service.create_price(
        PaymentsPriceCreateRequest(
            stripe_product_id=product_id,
            unit_amount=2500,
            plan_type=PlanType.recurring,
            recurring_interval=DurationUnit.month,
            recurring_interval_count=1,
        ),
        stripe_account_id,
    )

    assert resp.stripe_price_id.startswith("price_")
    assert resp.stripe_product_id == product_id
    assert resp.unit_amount == 2500
    assert resp.active is True
    assert resp.recurring_interval == "month"
    assert resp.recurring_interval_count == 1


async def test_create_one_time_price(
    price_service, membership_service, stripe_account_id,
):
    product_id = await _create_product(membership_service, stripe_account_id)

    resp = await price_service.create_price(
        PaymentsPriceCreateRequest(
            stripe_product_id=product_id,
            unit_amount=7500,
            plan_type=PlanType.one_time,
            recurring_interval=DurationUnit.month,
            recurring_interval_count=1,
        ),
        stripe_account_id,
    )

    assert resp.unit_amount == 7500
    assert resp.active is True
    assert resp.recurring_interval is None


async def test_deactivate_price(
    price_service, membership_service, stripe_account_id,
):
    product_id = await _create_product(membership_service, stripe_account_id)
    created = await price_service.create_price(
        PaymentsPriceCreateRequest(
            stripe_product_id=product_id,
            unit_amount=3000,
            plan_type=PlanType.recurring,
            recurring_interval=DurationUnit.month,
            recurring_interval_count=1,
        ),
        stripe_account_id,
    )

    resp = await price_service.deactivate_price(
        PaymentsPriceDeactivateRequest(stripe_price_id=created.stripe_price_id),
        stripe_account_id,
    )

    assert resp.active is False
    assert resp.stripe_price_id == created.stripe_price_id


async def test_activate_price(
    price_service, membership_service, stripe_account_id,
):
    product_id = await _create_product(membership_service, stripe_account_id)
    created = await price_service.create_price(
        PaymentsPriceCreateRequest(
            stripe_product_id=product_id,
            unit_amount=4000,
            plan_type=PlanType.recurring,
            recurring_interval=DurationUnit.month,
            recurring_interval_count=1,
        ),
        stripe_account_id,
    )
    await price_service.deactivate_price(
        PaymentsPriceDeactivateRequest(stripe_price_id=created.stripe_price_id),
        stripe_account_id,
    )

    resp = await price_service.activate_price(
        created.stripe_price_id,
        stripe_account_id,
    )

    assert resp.active is True


async def test_get_price(
    price_service, membership_service, stripe_account_id,
):
    product_id = await _create_product(membership_service, stripe_account_id)
    created = await price_service.create_price(
        PaymentsPriceCreateRequest(
            stripe_product_id=product_id,
            unit_amount=5500,
            plan_type=PlanType.recurring,
            recurring_interval=DurationUnit.month,
            recurring_interval_count=1,
        ),
        stripe_account_id,
    )

    resp = await price_service.get_price(
        created.stripe_price_id,
        stripe_account_id,
    )

    assert resp.stripe_price_id == created.stripe_price_id
    assert resp.unit_amount == 5500


async def test_get_nonexistent_price_raises(price_service, stripe_account_id):
    with pytest.raises(PaymentsResourceNotFoundError):
        await price_service.get_price("price_nonexistent_000", stripe_account_id)


async def test_validate_price_active_reactivates_archived(
    price_service, membership_service, stripe_account_id,
):
    product_id = await _create_product(membership_service, stripe_account_id)
    created = await price_service.create_price(
        PaymentsPriceCreateRequest(
            stripe_product_id=product_id,
            unit_amount=6000,
            plan_type=PlanType.recurring,
            recurring_interval=DurationUnit.month,
            recurring_interval_count=1,
        ),
        stripe_account_id,
    )
    await price_service.deactivate_price(
        PaymentsPriceDeactivateRequest(stripe_price_id=created.stripe_price_id),
        stripe_account_id,
    )

    resp = await price_service.validate_price_active(
        created.stripe_price_id,
        stripe_account_id,
    )

    assert resp.active is True
