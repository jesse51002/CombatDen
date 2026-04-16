"""Time-simulation tests for subscriptions using Stripe Test Clocks."""

from datetime import datetime, timedelta

import pytest

from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionCancelRequest,
    PaymentsSubscriptionCreateRequest,
    PaymentsSubscriptionDesiredItem,
    PaymentsSubscriptionFreezeRequest,
)

from tests.helpers.data_factory import create_payment_method
from tests.helpers.stripe_assertions import (
    assert_no_unexpected_charges,
    snapshot_billing_state,
)
from tests.helpers.stripe_clock import (
    advance_clock,
    create_test_clock,
    delete_test_clock,
)


# ── Fixtures ──────────────────────────────────────────────────��─

CLOCK_START = datetime(2026, 1, 15, 0, 0, 0)


@pytest.fixture
async def test_clock(stripe_client, connect_opts):
    """Create a test clock for time-simulation tests."""
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    yield clock_id
    await delete_test_clock(stripe_client, clock_id, connect_opts)


@pytest.fixture
async def clock_customer(stripe_client, connect_opts, test_clock):
    """Create a customer attached to the test clock with a Visa card."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    customer = await stripe_client.client.v1.customers.create_async(
        params={
            "test_clock": test_clock,
            "name": "Clock Test Member",
            "payment_method": pm_id,
            "invoice_settings": {"default_payment_method": pm_id},
        },
        options=connect_opts,
    )
    return customer.id


@pytest.fixture
async def clock_price(stripe_client, connect_opts):
    """Create a recurring monthly price for clock tests."""
    product = await stripe_client.client.v1.products.create_async(
        params={"name": "Clock Test Plan"},
        options=connect_opts,
    )
    price = await stripe_client.client.v1.prices.create_async(
        params={
            "product": product.id,
            "unit_amount": 5000,
            "currency": "usd",
            "recurring": {"interval": "month", "interval_count": 1},
        },
        options=connect_opts,
    )
    return price.id


# ── Tests ───────────────────────────────────────────────────────


@pytest.mark.timeout(90)
async def test_subscription_renewal_advances_period(
    subscription_service, stripe_client,
    stripe_account_id, connect_opts,
    test_clock, clock_customer, clock_price,
):
    """Create a subscription, advance 1 month, verify the billing period moved."""
    created = await subscription_service.create_subscription(
        PaymentsSubscriptionCreateRequest(
            stripe_customer_id=clock_customer,
            items=[PaymentsSubscriptionDesiredItem(stripe_price_id=clock_price)],
        ),
        stripe_account_id,
    )
    original_period_end = created.items[0].current_period_end

    # Advance 35 days past creation to ensure renewal
    await advance_clock(
        stripe_client,
        test_clock,
        CLOCK_START + timedelta(days=35),
        connect_opts,
    )

    # Re-fetch subscription from Stripe
    sub = await stripe_client.client.v1.subscriptions.retrieve_async(
        created.stripe_subscription_id,
        options=connect_opts,
    )

    new_period_end = sub.items.data[0].current_period_end
    assert new_period_end > original_period_end
    assert sub.status == "active"


@pytest.mark.timeout(90)
async def test_cancel_at_period_end_completes(
    subscription_service, stripe_client,
    stripe_account_id, connect_opts,
    test_clock, clock_customer, clock_price,
):
    """Set cancel_at_period_end, advance past period end, verify canceled."""
    created = await subscription_service.create_subscription(
        PaymentsSubscriptionCreateRequest(
            stripe_customer_id=clock_customer,
            items=[PaymentsSubscriptionDesiredItem(stripe_price_id=clock_price)],
        ),
        stripe_account_id,
    )

    await subscription_service.cancel_subscription(
        PaymentsSubscriptionCancelRequest(
            stripe_subscription_id=created.stripe_subscription_id,
            cancel_at_period_end=True,
        ),
        stripe_account_id,
    )

    # Snapshot just before the clock advance — from this point on
    # cancelling should prevent any new invoices.
    before = await snapshot_billing_state(
        stripe_client,
        clock_customer,
        connect_opts,
    )

    # Advance past the period end (35 days should be enough for monthly)
    await advance_clock(
        stripe_client,
        test_clock,
        CLOCK_START + timedelta(days=35),
        connect_opts,
    )

    sub = await stripe_client.client.v1.subscriptions.retrieve_async(
        created.stripe_subscription_id,
        options=connect_opts,
    )

    assert sub.status == "canceled"

    # After cancel_at_period_end + clock advance past the end, no
    # additional invoice should have been created.
    await assert_no_unexpected_charges(
        stripe_client,
        before,
        connect_opts,
    )


@pytest.mark.timeout(90)
async def test_freeze_resumes_at_date(
    subscription_service, stripe_client,
    stripe_account_id, connect_opts,
    test_clock, clock_customer, clock_price,
):
    """Freeze with a resumes_at date, advance past it, verify collection resumes."""
    from datetime import date

    created = await subscription_service.create_subscription(
        PaymentsSubscriptionCreateRequest(
            stripe_customer_id=clock_customer,
            items=[PaymentsSubscriptionDesiredItem(stripe_price_id=clock_price)],
        ),
        stripe_account_id,
    )

    freeze_end = date(2026, 2, 15)
    resp = await subscription_service.freeze_subscription(
        PaymentsSubscriptionFreezeRequest(
            stripe_subscription_id=created.stripe_subscription_id,
            freeze_end_date=freeze_end,
        ),
        stripe_account_id,
    )
    assert resp.resumes_at is not None

    # Advance to a point still inside the freeze window. Stripe's
    # pause_collection.behavior="void" still *creates* renewal
    # invoices on schedule but voids them immediately, so we cannot
    # use ``assert_no_unexpected_charges`` here. Instead we assert
    # that no invoice during the pause was actually paid and that
    # the customer's balance did not move.
    before_balance = (
        await stripe_client.client.v1.customers.retrieve_async(
            clock_customer,
            options=connect_opts,
        )
    ).balance
    await advance_clock(
        stripe_client,
        test_clock,
        datetime(2026, 2, 10, 0, 0, 0),
        connect_opts,
    )
    mid_pause_invoices = await stripe_client.client.v1.invoices.list_async(
        params={"customer": clock_customer, "limit": 100},
        options=connect_opts,
    )
    paid_during_pause = [
        inv for inv in mid_pause_invoices.data if inv.status == "paid"
    ]
    # The initial create may have produced a paid invoice — freeze
    # started after that, so any *new* paid invoices would mean
    # voiding didn't work.
    assert len(paid_during_pause) <= 1, (
        f"Unexpected paid invoices during freeze window: "
        f"{[i.id for i in paid_during_pause]}"
    )
    mid_customer = await stripe_client.client.v1.customers.retrieve_async(
        clock_customer,
        options=connect_opts,
    )
    assert mid_customer.balance == before_balance, (
        f"Customer balance shifted during freeze: {before_balance} -> "
        f"{mid_customer.balance}"
    )

    # Advance past the freeze end date
    await advance_clock(
        stripe_client,
        test_clock,
        datetime(2026, 2, 16, 0, 0, 0),
        connect_opts,
    )

    sub = await stripe_client.client.v1.subscriptions.retrieve_async(
        created.stripe_subscription_id,
        options=connect_opts,
    )

    # After resumes_at, pause_collection should be cleared
    assert sub.pause_collection is None
    assert sub.status == "active"
