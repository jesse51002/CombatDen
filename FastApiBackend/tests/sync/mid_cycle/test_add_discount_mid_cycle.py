"""Mid-cycle add-discount tests using Stripe Test Clocks.

Exercises the applied-discount add path (``POST /member_memberships/discounts/add``
-> ``memberships_service.add_discounts``). Adding a regular discount INSERTs an
applied-discount row and re-syncs; the sync computes the consolidated line's
coupon, attaches it, and writes the resolved stripe_coupon_id back. Editing or
deleting the source preset never touches these rows.

Requires a migrated local DB (the member_membership_applied_discounts table +
the gym_discounts lifetime columns) and the shared Stripe test account.
"""

from datetime import datetime, timedelta
from uuid import uuid4

import pytest

from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import (
    get_active_membership_item_id,
    get_applied_discounts,
    get_profile_stripe_ids,
)
from tests.helpers.stripe_assertions import (
    advance_to_next_cycle_and_fetch_invoice,
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
CYCLE_AFTER_NEXT = CLOCK_START + timedelta(days=70)


async def _start_membership(memberships_service, member, gym_id, plan):
    """Start a recurring membership with no discounts attached."""
    await memberships_service.start(
        member_id=member.member_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
        idempotency_key=uuid4(),
    )


def _discount_coupon_id(disc) -> str | None:
    """Coupon id referenced by a Stripe sub-item Discount, or None.

    The coupon lives at ``discount.source.coupon`` (a coupon-id string) in the
    current Stripe shape; the legacy ``discount.coupon`` object is null. A bare
    ``di_`` id means the expansion hasn't materialized (read-after-write) — treat
    it as "not yet readable" rather than mistaking it for a coupon.
    """
    if isinstance(disc, str):
        return None
    source = getattr(disc, "source", None)
    cid = getattr(source, "coupon", None) if source is not None else None
    if cid is None:
        coupon = getattr(disc, "coupon", None)
        cid = getattr(coupon, "id", coupon)
    if isinstance(cid, str) and not cid.startswith("di_"):
        return cid
    return None


def _line_coupon_ids(sub, stripe_price_id: str) -> set[str]:
    """Coupon ids on the subscription item using ``stripe_price_id``."""
    for item in sub.items.data:
        if item.price.id != stripe_price_id:
            continue
        found: set[str] = set()
        for disc in getattr(item, "discounts", None) or []:
            cid = _discount_coupon_id(disc)
            if cid is not None:
                found.add(cid)
        return found
    raise AssertionError(f"No item on {sub.id} uses price {stripe_price_id}")


# ── Tests ───────────────────────────────────────────────────────


@pytest.mark.timeout(180)
async def test_add_ongoing_discount_writes_applied_row_and_discounts_next_invoice(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Applying an ongoing percent discount INSERTs an applied-discount row,
    the sync computes + attaches the coupon and writes its id back, and the
    next cycle bills the discounted amount. No invoice is cut at edit time.
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
            name="Mid-cycle 10% Off",
            percentage_off=10.0,
            discount_mode="ongoing",
        )

        await _start_membership(memberships_service, member, gym_id, plan)
        profile = await get_profile_stripe_ids(db_pool, member.member_id, gym_id)
        assert profile.stripe_sub_id_month is not None
        item_id = await get_active_membership_item_id(db_pool, member.member_id, gym_id)

        before = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts
        )

        await memberships_service.add_discounts(
            item_id=item_id,
            member_id=member.member_id,
            discount_ids=[discount.discount_id],
            idempotency_key=uuid4(),
        )

        # An applied-discount row was written, copying the preset intent + provenance.
        snaps = await get_applied_discounts(db_pool, item_id)
        assert len(snaps) == 1
        snap = snaps[0]
        assert snap["discount_type"] == "preset"
        assert snap["discount_id"] == discount.discount_id
        assert snap["percentage_off"] == 10.0
        assert snap["discount_mode"] == "ongoing"
        # The sync resolved + wrote back the coupon id (the contract).
        assert snap["stripe_coupon_id"] is not None

        # The resolved coupon is on the right line; no charge at edit time.
        sub = await fetch_subscription(stripe_client, profile.stripe_sub_id_month, connect_opts)
        assert snap["stripe_coupon_id"] in _line_coupon_ids(sub, plan.stripe_price_id)
        await assert_no_unexpected_charges(stripe_client, before, connect_opts)

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
            f"Next-cycle invoice {invoice.id} should bill {expected}, got {invoice.amount_due}"
        )
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)


@pytest.mark.timeout(240)
async def test_once_discount_lands_once_then_consumed(
    memberships_service,
    payment_sync_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A ``once`` discount bills exactly the next invoice, then is consumed:
    its end_date is stamped and it never re-applies on the following cycle.
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
        plan = await created.plan(gym_id, price_cents=5000)
        discount = await created.discount(
            gym_id,
            name="One-time $10 Off",
            percentage_off=None,
            dollar_off=1000,
            discount_mode="once",
        )

        await _start_membership(memberships_service, member, gym_id, plan)
        profile = await get_profile_stripe_ids(db_pool, member.member_id, gym_id)
        item_id = await get_active_membership_item_id(db_pool, member.member_id, gym_id)
        before = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts
        )

        await memberships_service.add_discounts(
            item_id=item_id,
            member_id=member.member_id,
            discount_ids=[discount.discount_id],
            idempotency_key=uuid4(),
        )

        snaps = await get_applied_discounts(db_pool, item_id)
        assert len(snaps) == 1
        assert snaps[0]["discount_mode"] == "once"
        # Pending once: coupon resolved + written back, end_date still null.
        assert snaps[0]["stripe_coupon_id"] is not None
        assert snaps[0]["end_date"] is None

        # Next cycle bills with the once discount applied.
        invoice = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            NEXT_CYCLE,
            profile.stripe_sub_id_month,
            before,
            connect_opts,
        )
        assert invoice.amount_due == 4000, (
            f"Once discount should bill 4000 on the next invoice, got {invoice.amount_due}"
        )

        # The cycle AFTER the once is consumed re-syncs: the coupon is gone
        # from the live sub, the applied-discount row's end_date is stamped,
        # and the following invoice bills full price.
        before2 = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts
        )
        invoice2 = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            CYCLE_AFTER_NEXT,
            profile.stripe_sub_id_month,
            before2,
            connect_opts,
        )
        assert invoice2.amount_due == 5000, (
            f"Consumed once discount must not re-apply; expected full 5000, "
            f"got {invoice2.amount_due}"
        )

        # Stripe has now invoiced (and dropped) the once coupon, but nothing
        # auto-re-syncs the CRM yet — the webhook once-settle / scheduled
        # reconciler are unbuilt (TODO sync-guide §2.4 / §10). Trigger the sync
        # the way the next membership op (or the reconciler) would: its pre-sync
        # once-settle reads the live sub, sees the coupon is gone, and stamps
        # end_date. (This is the real settle, not a workaround — it only stamps
        # because Stripe genuinely consumed the coupon.)
        await payment_sync_service.update_payments_recurring(
            member.member_id,
            idempotency_key=uuid4(),
        )

        snaps_after = await get_applied_discounts(db_pool, item_id)
        assert snaps_after[0]["end_date"] is not None, (
            "Consumed once applied-discount row should have its end_date stamped"
        )
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)


@pytest.mark.timeout(180)
async def test_apply_is_idempotent_no_duplicate_applied_row(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Applying the same preset twice leaves a single applied-discount row.

    An applied-discount row already present and still desired is left frozen
    (never re-resolved, never duplicated).
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
        plan = await created.plan(gym_id, price_cents=5000)
        discount = await created.discount(gym_id, name="Idem 10% Off", percentage_off=10.0)
        await _start_membership(memberships_service, member, gym_id, plan)
        item_id = await get_active_membership_item_id(db_pool, member.member_id, gym_id)

        for _ in range(2):
            await memberships_service.add_discounts(
                item_id=item_id,
                member_id=member.member_id,
                discount_ids=[discount.discount_id],
                idempotency_key=uuid4(),
            )

        snaps = await get_applied_discounts(db_pool, item_id)
        assert len(snaps) == 1, (
            f"Re-applying a preset must not duplicate the applied-discount row, got {len(snaps)}"
        )
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)
