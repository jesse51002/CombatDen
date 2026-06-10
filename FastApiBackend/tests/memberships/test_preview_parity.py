"""Preview-vs-actual-bill parity tests.

Each test runs a preview, executes the real operation, and asserts
``preview.amount_due/subtotal/total`` equals the totals of the
invoice that Stripe actually generated. Drift here means the
preview path and the real billing path are reading different
inputs — surface as a production bug per ``CLAUDE.md`` rather than
loosening the assertion.

Two billing shapes are covered:

* Immediate-billing operations (one-time charge, prorate=True
  recurring start / price change) — fetch the new invoice cut by
  the operation itself.
* Next-cycle operations (prorate=False, cancel, discount change)
  — advance a Stripe Test Clock past the period boundary and
  compare to the renewal invoice.
"""

from datetime import datetime, timedelta
from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

from src.plans.plans_schema import MembershipPlanPriceRequest
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import (
    get_active_membership_item_id,
    get_profile_stripe_ids,
)
from tests.helpers.preview_parity import (
    assert_preview_matches_invoice,
    fetch_only_new_invoice,
)
from tests.helpers.stripe_assertions import (
    advance_to_next_cycle_and_fetch_invoice,
    assert_immediate_prorated_invoice,
    snapshot_billing_state,
)
from tests.helpers.stripe_clock import (
    create_test_clock,
    delete_test_clock,
)

CLOCK_START = datetime(2026, 1, 15, 0, 0, 0)
NEXT_CYCLE = CLOCK_START + timedelta(days=35)


async def _item_id_for_plan(db_pool, member_id, gym_id, plan_id) -> UUID:
    """Resolve a member's active item_id for a specific plan."""
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT item_id FROM member_memberships "
                "WHERE member_id = :id "
                "  AND gym_id = :gym_id "
                "  AND plan_id = :plan_id "
                "  AND cancel_date IS NULL"
            ),
            {
                "id": str(member_id),
                "gym_id": str(gym_id),
                "plan_id": str(plan_id),
            },
        )
        row = result.mappings().one()
    return UUID(str(row["item_id"]))


# ── Start: one-time plan ────────────────────────────────────────────


@pytest.mark.timeout(120)
async def test_preview_start_one_time_matches_invoice(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """One-time charge: preview totals must equal the invoice the
    real ``start`` cuts via ``_charge_one_time``.
    """
    pm_id = await created.payment_method()
    member = await created.member(
        gym_id,
        payment_method_id=pm_id,
    )
    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        plan_name="Parity One-Time",
        price_cents=4500,
    )

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        preview = await memberships_service.preview_start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )
        assert preview is not None

        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        invoice = await fetch_only_new_invoice(
            stripe_client,
            before,
            connect_opts,
        )
        # A one-time charge is entirely due now; nothing recurs.
        assert_preview_matches_invoice(preview.due_now, invoice)
        assert preview.recurring is None
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Start: recurring plan ───────────────────────────────────────────


@pytest.mark.timeout(180)
async def test_preview_start_recurring_matches_first_invoice(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Recurring start: preview totals must equal the first-cycle
    invoice Stripe cuts when the subscription is created. No test
    clock — the first invoice is generated immediately on start.
    """
    pm_id = await created.payment_method()
    member = await created.member(
        gym_id,
        payment_method_id=pm_id,
    )
    plan = await created.plan(
        gym_id,
        price_cents=5000,
    )

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        preview = await memberships_service.preview_start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )
        assert preview is not None

        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        invoice = await assert_immediate_prorated_invoice(
            stripe_client,
            before,
            connect_opts,
            subscription_id=profile.stripe_sub_id_month,
            min_amount=0,
        )
        # The immediate first invoice is the due-now preview; the
        # recurring half comes from a separate next-cycle preview.
        assert_preview_matches_invoice(preview.due_now, invoice)
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Update price: prorate=True (immediate invoice) ──────────────────


@pytest.mark.timeout(180)
async def test_preview_update_price_prorate_true_matches_invoice(
    memberships_service,
    plans_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """prorate=True swap: preview totals must equal the immediate
    proration invoice Stripe cuts at edit time.
    """
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
        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )
        item_id = await get_active_membership_item_id(
            db_pool,
            member.member_id,
            gym_id,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )

        await plans_service.set_price(
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

        preview = await memberships_service.preview_update_price(
            item_id=item_id,
            member_id=member.member_id,
            prorate=True,
        )
        assert preview is not None

        await memberships_service.update_price(
            item_id=item_id,
            member_id=member.member_id,
            idempotency_key=uuid4(),
            prorate=True,
        )

        invoice = await assert_immediate_prorated_invoice(
            stripe_client,
            before,
            connect_opts,
            subscription_id=profile.stripe_sub_id_month,
            min_amount=0,
        )
        assert_preview_matches_invoice(preview.due_now, invoice)
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)


# ── Update price: prorate=False (next cycle) ────────────────────────


@pytest.mark.timeout(180)
async def test_preview_update_price_prorate_false_matches_renewal(
    memberships_service,
    plans_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """prorate=False swap: preview totals must equal the next renewal
    invoice (no mid-cycle invoice is cut).
    """
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
        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )
        item_id = await get_active_membership_item_id(
            db_pool,
            member.member_id,
            gym_id,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )

        await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id,
                gym_id=gym_id,
                price=8000,
            ),
        )

        preview = await memberships_service.preview_update_price(
            item_id=item_id,
            member_id=member.member_id,
            prorate=False,
        )
        assert preview is not None

        await memberships_service.update_price(
            item_id=item_id,
            member_id=member.member_id,
            idempotency_key=uuid4(),
            prorate=False,
        )

        # Snapshot AFTER the swap so the renewal invoice is what we
        # advance into.
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
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
        assert_preview_matches_invoice(preview.recurring, invoice)
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)


# ── Cancel partial (one of two memberships) ─────────────────────────


@pytest.mark.timeout(240)
async def test_preview_cancel_partial_matches_renewal(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Cancel one of two recurring memberships: preview totals must
    equal the renewal invoice that bills only the surviving item.

    The single-item cancel returns a None preview (bucket goes to
    zero) — covered separately in ``test_memberships_preview.py``.
    """
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    member = None
    try:
        pm_id = await created.payment_method()
        member = await created.member(
            gym_id,
            payment_method_id=pm_id,
            test_clock_id=clock_id,
        )
        plan_a = await created.plan(
            gym_id,
            plan_name="Parity Plan A",
            price_cents=5000,
        )
        plan_b = await created.plan(
            gym_id,
            plan_name="Parity Plan B",
            price_cents=3000,
        )

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

        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )

        # Cancel plan B; surviving line should be plan A on renewal.
        item_id_b = await _item_id_for_plan(
            db_pool,
            member.member_id,
            gym_id,
            plan_b.plan_id,
        )

        preview = await memberships_service.preview_cancel(
            item_id_b,
            member.member_id,
        )
        assert preview is not None

        await memberships_service.cancel(
            item_id_b,
            member.member_id,
            idempotency_key=uuid4(),
        )

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
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
        assert_preview_matches_invoice(preview.recurring, invoice)
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)


# ── Update discounts (next cycle) ───────────────────────────────────


@pytest.mark.timeout(180)
async def test_preview_applied_discounts_matches_renewal(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Applied-discount preview totals must equal the renewal invoice.

    The apply path writes the applied-discount row first and re-syncs (the sync
    attaches the resolved coupon onto the live subscription). The preview then
    reads the membership's CURRENT applied-discount state, so a Stripe upcoming-invoice
    read already reflects the attached coupon. Preview-vs-renewal drift here
    means the preview and real billing paths read different inputs — surface as
    a production bug per CLAUDE.md, do not loosen the assertion.
    """
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
        discount = await created.discount(
            gym_id,
            name="Parity 15% Off",
            percentage_off=15.0,
            discount_mode="ongoing",
        )

        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )
        item_id = await get_active_membership_item_id(
            db_pool,
            member.member_id,
            gym_id,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )

        # Apply first (writes the applied-discount row + syncs the coupon onto
        # the sub), then preview the membership's current discounted state.
        await memberships_service.add_discounts(
            item_id=item_id,
            member_id=member.member_id,
            discount_ids=[discount.discount_id],
            idempotency_key=uuid4(),
        )

        # Preview the current discounted state — no further proposed change
        # (empty add/remove), so it stages nothing and reflects what's applied.
        # Preview the current discounted state — re-adding the already-
        # applied discount stages nothing (skipped), so it reflects the live bill.
        preview = await memberships_service.add_discounts(
            item_id=item_id,
            member_id=member.member_id,
            discount_ids=[discount.discount_id],
            idempotency_key=uuid4(),
            preview=True,
        )
        assert preview is not None

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
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
        assert_preview_matches_invoice(preview.recurring, invoice)
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)
