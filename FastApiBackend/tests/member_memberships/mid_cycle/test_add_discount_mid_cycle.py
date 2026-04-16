"""Mid-cycle add-discount tests using Stripe Test Clocks.

There is no first-class "attach discount to an active membership"
router today — discount changes flow through the payment-sync layer.
These tests mirror that reality: they set ``discount_ids`` on the
CRM row directly and trigger ``update_payments_recurring`` to drive
the Stripe-side mutation, then assert both the immediate subscription
state and the next renewal invoice.
"""

import json
from datetime import datetime, timedelta
from uuid import UUID

import pytest
from sqlalchemy import text

from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import (
    create_discount,
    create_member,
    create_payment_method,
    create_plan,
)
from tests.helpers.db_reads import get_profile_stripe_ids
from tests.helpers.stripe_assertions import (
    advance_to_next_cycle_and_fetch_invoice,
    assert_item_discounts,
    assert_no_unexpected_charges,
    fetch_subscription,
    snapshot_billing_state,
)
from tests.helpers.stripe_clock import (
    create_test_clock,
    delete_test_clock,
)


CLOCK_START = datetime(2026, 1, 15, 0, 0, 0)
NEXT_CYCLE = CLOCK_START + timedelta(days=35)


async def _start_membership(memberships_service, member, gym_id, plan):
    """Start a recurring membership with no discounts attached."""
    await memberships_service.start(
        crm_user_id=member.crm_user_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
    )


async def _set_discount_ids(db_pool, member, plan, discount_ids: list[UUID]) -> None:
    """Write the JSONB ``discount_ids`` array on an active membership row.

    Emulates the only path that currently exists for changing the
    discount set on a live membership — production code only writes
    this column during ``start`` or via the discount-cascade removal.
    """
    payload = json.dumps([str(d) for d in discount_ids]) if discount_ids else None
    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE member_memberships_unfiltered "
                "SET discount_ids = CAST(:ids AS jsonb) "
                "WHERE crm_user_id = :crm_user_id AND plan_id = :plan_id"
            ),
            {
                "ids": payload,
                "crm_user_id": str(member.crm_user_id),
                "plan_id": str(plan.plan_id),
            },
        )
        await session.commit()


def _find_item_index_by_price(sub, stripe_price_id: str) -> int:
    for idx, item in enumerate(sub.items.data):
        if item.price.id == stripe_price_id:
            return idx
    raise AssertionError(
        f"No item on subscription {sub.id} uses price {stripe_price_id}; "
        f"items={[i.price.id for i in sub.items.data]}"
    )


# ── Tests ───────────────────────────────────────────────────────


@pytest.mark.timeout(180)
async def test_add_discount_to_active_sub_next_invoice_discounted(
    memberships_service,
    payment_sync_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Attaching a percent-off discount mid-cycle propagates the
    coupon onto the Stripe subscription item and reduces the next
    cycle's invoice total. No new invoice is generated at edit time.
    """
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    member = None
    try:
        pm_id = await create_payment_method(stripe_client, connect_opts)
        member = await create_member(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            payment_method_id=pm_id,
            test_clock_id=clock_id,
        )
        plan = await create_plan(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            price_cents=5000,
        )
        discount = await create_discount(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            name="Mid-cycle 10% Off",
            percentage_off=10.0,
        )

        await _start_membership(memberships_service, member, gym_id, plan)
        profile = await get_profile_stripe_ids(
            db_pool, member.crm_user_id, gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        before = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts,
        )

        await _set_discount_ids(db_pool, member, plan, [discount.discount_id])
        await payment_sync_service.update_payments_recurring(
            member.crm_user_id,
            add_ids=[],
            cancel_ids=[],
        )

        # Stripe side: coupon is on the correct subscription item and
        # the edit itself did not charge the customer.
        sub = await fetch_subscription(
            stripe_client, profile.stripe_sub_id_month, connect_opts,
        )
        idx = _find_item_index_by_price(sub, plan.stripe_price_id)
        assert_item_discounts(sub, {discount.stripe_coupon_id}, index=idx)
        await assert_no_unexpected_charges(
            stripe_client, before, connect_opts,
        )

        # Next cycle: invoice total should reflect the percent-off
        # coupon applied against the full plan price.
        invoice = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            NEXT_CYCLE,
            profile.stripe_sub_id_month,
            before,
            connect_opts,
        )
        expected = int(round(5000 * 0.9))
        assert invoice.amount_due == expected, (
            f"Next-cycle invoice {invoice.id} should bill the discounted "
            f"amount {expected}, got {invoice.amount_due}"
        )
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.crm_user_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)


@pytest.mark.timeout(240)
async def test_add_percentage_discount_then_amount_discount(
    memberships_service,
    payment_sync_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Attach a percent discount, then stack a flat-dollar discount
    on top. Both coupons end up on the Stripe subscription item and
    the next invoice reflects both reductions.
    """
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    member = None
    try:
        pm_id = await create_payment_method(stripe_client, connect_opts)
        member = await create_member(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            payment_method_id=pm_id,
            test_clock_id=clock_id,
        )
        plan = await create_plan(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            price_cents=10000,
        )
        pct_discount = await create_discount(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            name="Stacked 20% Off",
            percentage_off=20.0,
        )
        flat_discount = await create_discount(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            name="Stacked $5 Off",
            percentage_off=None,
            dollar_off=500,
        )

        await _start_membership(memberships_service, member, gym_id, plan)
        profile = await get_profile_stripe_ids(
            db_pool, member.crm_user_id, gym_id,
        )

        # Step 1 — attach percent coupon.
        before_step1 = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts,
        )
        await _set_discount_ids(
            db_pool, member, plan, [pct_discount.discount_id],
        )
        await payment_sync_service.update_payments_recurring(
            member.crm_user_id, add_ids=[], cancel_ids=[],
        )
        await assert_no_unexpected_charges(
            stripe_client, before_step1, connect_opts,
        )

        sub = await fetch_subscription(
            stripe_client, profile.stripe_sub_id_month, connect_opts,
        )
        idx = _find_item_index_by_price(sub, plan.stripe_price_id)
        assert_item_discounts(sub, {pct_discount.stripe_coupon_id}, index=idx)

        # Step 2 — stack the flat-dollar coupon alongside it.
        before_step2 = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts,
        )
        await _set_discount_ids(
            db_pool,
            member,
            plan,
            [pct_discount.discount_id, flat_discount.discount_id],
        )
        await payment_sync_service.update_payments_recurring(
            member.crm_user_id, add_ids=[], cancel_ids=[],
        )
        await assert_no_unexpected_charges(
            stripe_client, before_step2, connect_opts,
        )

        sub = await fetch_subscription(
            stripe_client, profile.stripe_sub_id_month, connect_opts,
        )
        idx = _find_item_index_by_price(sub, plan.stripe_price_id)
        assert_item_discounts(
            sub,
            {pct_discount.stripe_coupon_id, flat_discount.stripe_coupon_id},
            index=idx,
        )

        # Next cycle: both coupons must have been applied. Stripe's
        # stacking order between a percent-off coupon and a flat
        # dollar-off coupon is not stable — we've observed both
        # orderings on the same sandbox run-to-run:
        #
        #   percent first → (10000 * 0.8) - 500       = 7500
        #   flat first    → (10000 - 500) * 0.8       = 7600
        #
        # Either is acceptable for billing; what matters is that
        # BOTH coupons were applied. Assert the amount lands on one
        # of the two valid totals, and separately pin down that the
        # invoice's ``total_discount_amounts`` has exactly two lines.
        invoice = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            NEXT_CYCLE,
            profile.stripe_sub_id_month,
            before_step2,
            connect_opts,
        )
        percent_first = int(round(10000 * 0.8)) - 500
        flat_first = int(round((10000 - 500) * 0.8))
        assert invoice.amount_due in {percent_first, flat_first}, (
            f"Stacked discounts should bill {percent_first} or "
            f"{flat_first} on renewal, got {invoice.amount_due} on "
            f"{invoice.id}"
        )
        discount_lines = invoice.total_discount_amounts or []
        assert len(discount_lines) == 2, (
            f"Renewal invoice {invoice.id} should show two discount "
            f"lines (percent + flat), got {len(discount_lines)}"
        )
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.crm_user_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)
