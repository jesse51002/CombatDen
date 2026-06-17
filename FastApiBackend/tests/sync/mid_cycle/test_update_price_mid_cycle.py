"""Mid-cycle price change tests using Stripe Test Clocks.

Every test creates a test clock, attaches a member's Stripe customer
to it, starts a membership, performs a mid-cycle ``update_price``,
and then advances the clock past the current period to verify the
next renewal invoice bills the expected amount.

Three flows are covered:

1. ``prorate=False`` — no invoice created mid-cycle, next cycle bills
   the new price.
2. ``prorate=True`` (upgrade) — an immediate prorated invoice IS cut
   at edit time (Stripe ``always_invoice`` behavior), and the next
   cycle bills a plain full-price invoice with no residual proration.
3. ``prorate=False`` downgrade — no invoice created, next cycle bills
   the cheaper price.
"""

from datetime import datetime, timedelta
from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from src.plans.plans_schema import MembershipPlanPriceRequest
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import (
    get_profile_stripe_ids,
)
from tests.helpers.stripe_assertions import (
    advance_to_next_cycle_and_fetch_invoice,
    assert_immediate_prorated_invoice,
    assert_invoice_matches,
    assert_no_unexpected_charges,
    assert_subscription_item_price,
    fetch_subscription,
    snapshot_billing_state,
)
from tests.helpers.stripe_clock import (
    create_test_clock,
    delete_test_clock,
)

CLOCK_START = datetime(2026, 1, 15, 0, 0, 0)
NEXT_CYCLE = CLOCK_START + timedelta(days=35)


async def _start_and_get_item_id(memberships_service, db_pool, member, gym_id, plan):
    """Start a membership and return its CRM item_id."""
    await memberships_service.start(
        MemberMembershipsStartRequest(
            payer_member_id=member.member_id,
            gym_id=gym_id,
            idempotency_key=uuid4(),
            memberships=[
                MemberMembershipsStartItem(
                    member_id=member.member_id,
                    price_id=plan.price_id,
                ),
            ],
        )
    )
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT item_id FROM member_memberships "
                "WHERE member_id = :id AND plan_id = :plan_id"
            ),
            {"id": str(member.member_id), "plan_id": str(plan.plan_id)},
        )
        row = result.mappings().fetchone()
    return UUID(str(row["item_id"]))


def _find_item_by_price(sub, stripe_price_id: str):
    """Return the subscription item whose price matches ``stripe_price_id``."""
    for idx, item in enumerate(sub.items.data):
        if item.price.id == stripe_price_id:
            return idx, item
    raise AssertionError(
        f"No item on subscription {sub.id} uses price {stripe_price_id}; "
        f"items={[i.price.id for i in sub.items.data]}"
    )


def _line_price_id(line) -> str | None:
    """Pull the Stripe price id off an invoice line.

    Newer Stripe API versions moved ``line.price`` onto
    ``line.pricing.price_details.price``. Read both shapes so the
    helpers work regardless of which API version the account is on.
    """
    legacy = getattr(line, "price", None) if not isinstance(line, dict) else line.get("price")
    if legacy is not None:
        if isinstance(legacy, str):
            return legacy
        maybe_id = (
            getattr(legacy, "id", None) if not isinstance(legacy, dict) else legacy.get("id")
        )
        if maybe_id:
            return maybe_id

    pricing = getattr(line, "pricing", None) if not isinstance(line, dict) else line.get("pricing")
    if pricing is None:
        return None
    details = (
        getattr(pricing, "price_details", None)
        if not isinstance(pricing, dict)
        else pricing.get("price_details")
    )
    if details is None:
        return None
    price = (
        getattr(details, "price", None) if not isinstance(details, dict) else details.get("price")
    )
    if price is None:
        return None
    if isinstance(price, str):
        return price
    return getattr(price, "id", None) if not isinstance(price, dict) else price.get("id")


def _invoice_line_for_price(invoice, stripe_price_id: str):
    """Return the first line on ``invoice`` for ``stripe_price_id``, or None."""
    for line in invoice.lines.data:
        if _line_price_id(line) == stripe_price_id:
            return line
    return None


# ── Tests ───────────────────────────────────────────────────────


@pytest.mark.timeout(180)
async def test_update_price_mid_cycle_no_double_charge_prorate_none(
    memberships_service,
    plans_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """prorate=False swaps the item and defers the new amount to
    the next cycle — no mid-cycle invoice is generated."""
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    member = None
    try:
        pm_id = await created.payment_method()
        member = await created.member(
            gym_id,
            payment_method_id=pm_id,
            test_clock_id=clock_id,
        )
        plan = await created.plan(
            gym_id,
            price_cents=5000,
        )

        item_id = await _start_and_get_item_id(
            memberships_service,
            db_pool,
            member,
            gym_id,
            plan,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        # New higher tier price for the swap.
        new_price = await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id,
                gym_id=gym_id,
                price=8000,
            ),
        )

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.update_price(
            item_id=item_id,
            member_id=member.member_id,
            prorate=False,
        )

        # Stripe side: item points at new price, no mid-cycle invoice.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        idx, _ = _find_item_by_price(sub, new_price.stripe_price_id)
        assert_subscription_item_price(
            sub,
            new_price.stripe_price_id,
            index=idx,
        )
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )

        # Advance past period end — next invoice must be at the new price
        # and must not contain any lingering proration lines.
        invoice = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            NEXT_CYCLE,
            profile.stripe_sub_id_month,
            before,
            connect_opts,
        )
        assert_invoice_matches(invoice, amount_due=8000)

        new_line = _invoice_line_for_price(invoice, new_price.stripe_price_id)
        assert new_line is not None, (
            f"Next-cycle invoice {invoice.id} missing a line at the new "
            f"price {new_price.stripe_price_id}"
        )
        assert new_line.amount == 8000

        # No line should still be at the old archived price.
        old_line = _invoice_line_for_price(invoice, plan.stripe_price_id)
        assert old_line is None, (
            f"Next-cycle invoice {invoice.id} still has a line at the "
            f"old price {plan.stripe_price_id} (prorate=False should have "
            f"swapped cleanly)"
        )
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)


@pytest.mark.timeout(180)
async def test_update_price_mid_cycle_with_prorate_true(
    memberships_service,
    plans_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """prorate=True creates a prorated invoice mid-cycle, and the next
    cycle settles at the new full price with no residual proration."""
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    member = None
    try:
        pm_id = await created.payment_method()
        member = await created.member(
            gym_id,
            payment_method_id=pm_id,
            test_clock_id=clock_id,
        )
        plan = await created.plan(
            gym_id,
            price_cents=5000,
        )
        item_id = await _start_and_get_item_id(
            memberships_service,
            db_pool,
            member,
            gym_id,
            plan,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )

        new_price = await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id,
                gym_id=gym_id,
                price=8000,
            ),
        )

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.update_price(
            item_id=item_id,
            member_id=member.member_id,
            prorate=True,
        )

        # Stripe side: item swapped to new price.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        idx, _ = _find_item_by_price(sub, new_price.stripe_price_id)
        assert_subscription_item_price(
            sub,
            new_price.stripe_price_id,
            index=idx,
        )

        # With proration_behavior="always_invoice", Stripe cuts a
        # standalone invoice for the proration delta at edit time.
        # We assert on that immediate invoice here; the renewal
        # invoice later is a plain full-cycle bill at the new price.
        immediate = await assert_immediate_prorated_invoice(
            stripe_client,
            before,
            connect_opts,
            subscription_id=profile.stripe_sub_id_month,
            min_amount=1,
            max_amount=8000,
        )
        assert immediate.amount_due > 0, (
            f"Immediate proration invoice {immediate.id} should have "
            f"a positive amount_due, got {immediate.amount_due}"
        )

        # Refresh the snapshot so advance_to_next_cycle_and_fetch_invoice
        # can distinguish the renewal invoice from the immediate
        # proration invoice we just asserted on.
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        # Advance the clock — the renewal invoice is now a plain
        # full-cycle bill at the new price. Proration already settled
        # on the immediate invoice above, so there should be no
        # residual proration lines here.
        invoice = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            NEXT_CYCLE,
            profile.stripe_sub_id_month,
            before,
            connect_opts,
        )
        assert_invoice_matches(invoice, amount_due=8000)

        new_line = _invoice_line_for_price(invoice, new_price.stripe_price_id)
        assert new_line is not None, (
            f"Renewal invoice {invoice.id} missing a line at the new "
            f"price {new_price.stripe_price_id}"
        )
        assert new_line.amount == 8000
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)


@pytest.mark.timeout(180)
async def test_update_price_to_cheaper_tier_mid_cycle(
    memberships_service,
    plans_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Downgrade with prorate=False — no mid-cycle invoice, next
    cycle bills at the cheaper price."""
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    member = None
    try:
        pm_id = await created.payment_method()
        member = await created.member(
            gym_id,
            payment_method_id=pm_id,
            test_clock_id=clock_id,
        )
        plan = await created.plan(
            gym_id,
            price_cents=8000,
        )
        item_id = await _start_and_get_item_id(
            memberships_service,
            db_pool,
            member,
            gym_id,
            plan,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )

        cheaper_price = await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id,
                gym_id=gym_id,
                price=3000,
            ),
        )

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.update_price(
            item_id=item_id,
            member_id=member.member_id,
            prorate=False,
        )

        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        idx, _ = _find_item_by_price(sub, cheaper_price.stripe_price_id)
        assert_subscription_item_price(
            sub,
            cheaper_price.stripe_price_id,
            index=idx,
        )
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )

        invoice = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            NEXT_CYCLE,
            profile.stripe_sub_id_month,
            before,
            connect_opts,
        )
        assert_invoice_matches(invoice, amount_due=3000)
        new_line = _invoice_line_for_price(invoice, cheaper_price.stripe_price_id)
        assert new_line is not None
        assert new_line.amount == 3000
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)
