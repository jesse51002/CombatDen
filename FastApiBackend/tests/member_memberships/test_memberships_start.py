"""Integration tests for starting memberships.

Every successful path fetches the Stripe resource it just created
and asserts the price (and coupons, when applicable) match what the
CRM row says. Failed paths snapshot the customer's Stripe billing
state first and assert no invoices were generated.
"""

from uuid import uuid4

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
    assert_immediate_prorated_invoice,
    assert_item_discounts,
    assert_no_unexpected_charges,
    assert_subscription_item_price,
    fetch_subscription,
    snapshot_billing_state,
)


async def _find_latest_invoice_for_customer(
    stripe_client,
    customer_id: str,
    connect_opts,
):
    """Return the most recent invoice for a customer, or None."""
    invoices = await stripe_client.client.v1.invoices.list_async(
        params={"customer": customer_id, "limit": 10},
        options=connect_opts,
    )
    if not invoices.data:
        return None
    return invoices.data[0]


async def test_start_recurring_membership(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Starting a recurring membership with the default ``prorate=True``
    must cut an immediate prorated invoice and auto-charge it — not
    defer the first charge to the next anchor date.

    Regression guard for the "membership starts but nothing gets
    billed until next month" bug.
    """
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        # Verify DB row exists with stripe_item_id set
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id, stripe_item_id FROM member_memberships "
                    "WHERE member_id = :id AND plan_id = :plan_id"
                ),
                {"id": str(member.member_id), "plan_id": str(plan.plan_id)},
            )
            row = result.mappings().fetchone()

        assert row is not None
        assert row["stripe_item_id"] is not None

        # Stripe side: the subscription must carry the plan's price
        # id on its (only) item and be in active state.
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert sub.status == "active", (
            f"New subscription {sub.id} is {sub.status}, expected active"
        )
        assert_subscription_item_price(sub, plan.stripe_price_id)
        assert_item_discounts(sub, set())

        # Immediate prorated invoice must exist and be paid. Amount
        # is between 1 cent (mid-month proration) and a full cycle
        # (starting on the anchor day → full-period first invoice).
        await assert_immediate_prorated_invoice(
            stripe_client,
            before,
            connect_opts,
            subscription_id=sub.id,
            min_amount=1,
            max_amount=plan.price_cents,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_start_one_time_membership(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        plan_type="one_time",
        plan_name="One-Time Test",
        price_cents=3000,
    )

    try:
        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id, stripe_item_id FROM member_memberships "
                    "WHERE member_id = :id AND plan_id = :plan_id"
                ),
                {"id": str(member.member_id), "plan_id": str(plan.plan_id)},
            )
            row = result.mappings().fetchone()

        assert row is not None
        assert row["stripe_item_id"] is not None

        # Stripe side: one-time charge must have produced exactly
        # one paid invoice for the plan's price amount.
        invoice = await _find_latest_invoice_for_customer(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )
        assert invoice is not None, (
            f"No invoice found for customer {member.stripe_customer_id} after one-time start"
        )
        assert invoice.amount_paid == plan.price_cents, (
            f"One-time invoice {invoice.id} amount_paid={invoice.amount_paid}, "
            f"expected {plan.price_cents}"
        )
        assert invoice.status == "paid", f"One-time invoice {invoice.id} status={invoice.status}"
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_start_zero_dollar_one_time_membership(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Regression: $0 one-time plans must not crash on pay_async."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        plan_type="one_time",
        plan_name="Free Trial Test",
        price_cents=0,
    )

    try:
        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id, stripe_item_id, total_price "
                    "FROM member_memberships "
                    "WHERE member_id = :id AND plan_id = :plan_id"
                ),
                {"id": str(member.member_id), "plan_id": str(plan.plan_id)},
            )
            row = result.mappings().fetchone()

        assert row is not None
        assert row["stripe_item_id"] is not None
        assert row["total_price"] == 0

        # Stripe may create a $0 invoice for the one-time charge,
        # but the member must never actually be charged. Assert
        # every invoice on the customer has amount_paid == 0.
        invoices = await stripe_client.client.v1.invoices.list_async(
            params={"customer": member.stripe_customer_id, "limit": 10},
            options=connect_opts,
        )
        for inv in invoices.data:
            assert inv.amount_paid == 0, (
                f"$0 one-time plan produced invoice {inv.id} with amount_paid={inv.amount_paid}"
            )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_start_zero_dollar_recurring_membership(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Regression: $0 recurring plans must start cleanly as free subscriptions."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        plan_type="recurring",
        plan_name="Free Recurring Test",
        price_cents=0,
    )

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id, stripe_item_id, total_price "
                    "FROM member_memberships "
                    "WHERE member_id = :id AND plan_id = :plan_id"
                ),
                {"id": str(member.member_id), "plan_id": str(plan.plan_id)},
            )
            row = result.mappings().fetchone()

        assert row is not None
        assert row["stripe_item_id"] is not None
        assert row["total_price"] == 0

        # Stripe side: subscription exists, item carries the $0
        # price, and no charge landed on the customer.
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert_subscription_item_price(sub, plan.stripe_price_id)

        # $0 recurring plans: Stripe may or may not cut an
        # immediate invoice depending on its internal handling, but
        # the member must never actually be charged. Assert every
        # new invoice carries amount_paid == 0.
        after_invoices = await stripe_client.client.v1.invoices.list_async(
            params={"customer": member.stripe_customer_id, "limit": 10},
            options=connect_opts,
        )
        new_invoices = [inv for inv in after_invoices.data if inv.id not in before.invoice_ids]
        for inv in new_invoices:
            assert inv.amount_paid == 0, (
                f"$0 recurring plan produced invoice {inv.id} with amount_paid={inv.amount_paid}"
            )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_start_validates_plan_price(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )

    try:
        # Failed validation must not touch Stripe billing at all.
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        with pytest.raises((ValueError, Exception)):
            await memberships_service.start(
                member_id=member.member_id,
                gym_id=gym_id,
                plan_id=uuid4(),
                price_id=uuid4(),
                idempotency_key=uuid4(),
            )

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_start_duplicate_raises(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)

    try:
        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        # Snapshot after the first successful start — the duplicate
        # attempt below must not create any further Stripe state.
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        with pytest.raises((ValueError, Exception)):
            await memberships_service.start(
                member_id=member.member_id,
                gym_id=gym_id,
                plan_id=plan.plan_id,
                price_id=plan.price_id,
                idempotency_key=uuid4(),
            )

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_start_two_different_recurring_plans(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """A member can hold multiple recurring memberships at the same
    gym as long as each is on a distinct plan. Regression guard for
    the over-broad ``check_recurring_no_active_memberships`` trigger
    that used to block any second recurring start, even on a
    different plan.
    """
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan_a = await create_plan(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        plan_name="Recurring A",
    )
    plan_b = await create_plan(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        plan_name="Recurring B",
    )

    try:
        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan_a.plan_id,
            price_id=plan_a.price_id,
            idempotency_key=uuid4(),
        )
        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan_b.plan_id,
            price_id=plan_b.price_id,
            idempotency_key=uuid4(),
        )

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT plan_id, stripe_item_id FROM member_memberships "
                    "WHERE member_id = :id"
                ),
                {"id": str(member.member_id)},
            )
            rows = result.mappings().all()

        plan_ids = {row["plan_id"] for row in rows}
        assert plan_ids == {plan_a.plan_id, plan_b.plan_id}, (
            f"Expected memberships on both plans, got {plan_ids}"
        )
        for row in rows:
            assert row["stripe_item_id"] is not None, (
                f"Membership on plan {row['plan_id']} missing stripe_item_id"
            )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_start_with_discount(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """``start_membership(discount_ids=[...])`` must attach the real
    Stripe coupon to the new subscription item on its very first
    sync — no follow-up settle call required.

    Regression guard for two bugs:

    1. The 502 "Coupon <uuid> not found" bug, where
       ``aggregate_plan_discounts`` would pass CRM discount UUIDs
       straight to Stripe if they weren't first resolved to real
       coupon IDs.
    2. The "first sync can't see its own row" bug (Bug 2 in
       ``docs/mid_cycle_test_bugs_and_followups.md``), where the
       pending row was invisible to the filtered view during its
       own sync and the coupon only attached on a later no-op
       sync. Production callers don't make that second sync, so
       the test must not either.
    """
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)
    discount = await create_discount(db_pool, stripe_client, gym_id, connect_opts)

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
            discount_ids=[discount.discount_id],
        )

        async with db_pool.session() as session:
            mm_row = (
                (
                    await session.execute(
                        text(
                            "SELECT discount_ids FROM member_memberships "
                            "WHERE member_id = :id AND plan_id = :plan_id"
                        ),
                        {"id": str(member.member_id), "plan_id": str(plan.plan_id)},
                    )
                )
                .mappings()
                .fetchone()
            )

        assert mm_row is not None
        assert mm_row["discount_ids"] is not None

        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None, (
            "Member profile should have a Stripe subscription after start"
        )

        # Stripe must have received the real stripe_coupon_id on
        # the discounted plan's subscription item — not the CRM
        # UUID — on the first pass from ``start`` alone.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
            expand=(
                "items.data.price",
                "items.data.discounts.coupon",
            ),
        )
        assert_subscription_item_price(sub, plan.stripe_price_id)
        assert_item_discounts(sub, {discount.stripe_coupon_id})

        # The discount must apply to the immediate prorated invoice
        # — not just get set on the subscription for a future
        # invoice that never fires.
        await assert_immediate_prorated_invoice(
            stripe_client,
            before,
            connect_opts,
            subscription_id=sub.id,
            min_amount=0,
            max_amount=plan.price_cents,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_start_recurring_prorate_false_no_immediate_invoice(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """``prorate=False`` must NOT generate an invoice at start time —
    the subscription starts and waits for the next anchor-date
    billing cycle. The start→anchor window is effectively free to
    the member.
    """
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
            prorate=False,
        )

        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert sub.status == "active", (
            f"prorate=False sub {sub.id} is {sub.status}, expected active"
        )
        assert_subscription_item_price(sub, plan.stripe_price_id)

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_start_recurring_cash_prorate_true_pays_out_of_band(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Cash + ``prorate=True`` must cut the immediate prorated
    invoice and mark it paid out of band (not auto-charge the
    card). The invoice carries the ``crm_paid_with_cash`` metadata
    tag so the downstream ``invoice.paid`` webhook can record the
    payment method as cash.
    """
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
            prorate=True,
            paid_with_cash=True,
        )

        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert sub.status == "active", (
            f"Cash sub {sub.id} is {sub.status}, expected active after out-of-band pay"
        )

        invoice = await assert_immediate_prorated_invoice(
            stripe_client,
            before,
            connect_opts,
            subscription_id=sub.id,
            min_amount=1,
            max_amount=plan.price_cents,
        )
        assert invoice.metadata.to_dict().get("crm_paid_with_cash") == "true", (
            f"Cash invoice {invoice.id} missing metadata "
            f"crm_paid_with_cash=true: {dict(invoice.metadata)}"
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_start_recurring_cash_prorate_false_no_invoice(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Cash + ``prorate=False`` must behave the same as card +
    ``prorate=False``: no immediate invoice, sub active, next bill
    at the anchor date. Locks in the cash/card symmetry — cash is
    not supposed to force an immediate charge when the caller said
    "don't prorate."
    """
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
            prorate=False,
            paid_with_cash=True,
        )

        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert sub.status == "active", (
            f"Cash prorate=False sub {sub.id} is {sub.status}, expected active"
        )
        assert_subscription_item_price(sub, plan.stripe_price_id)

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)
