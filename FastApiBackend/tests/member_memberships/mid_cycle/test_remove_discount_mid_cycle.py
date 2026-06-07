"""Mid-cycle remove-discount tests using Stripe Test Clocks.

Removing a discount is a DELETE of the membership's frozen snapshot row via the
apply path (``apply_discounts(remove_applied_ids=[...])``). The re-sync then
recomputes the line with the row gone, so the coupon leaves the Stripe item and
the next cycle bills full price.

Archiving the *source preset* is deliberately NOT a removal — predictability
means a member's bill only changes via an explicit add/remove on their own
membership. The archive-leaves-the-holder behavior is verified here too.

Requires a migrated local DB (the applied-discount snapshot table) and the
shared Stripe test account.
"""

from datetime import datetime, timedelta
from uuid import uuid4

import pytest

from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import (
    get_active_membership_item_id,
    get_applied_snapshots,
    get_profile_stripe_ids,
)
from tests.helpers.stripe_assertions import (
    advance_to_next_cycle_and_fetch_invoice,
    assert_invoice_matches,
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


async def _start_and_apply(memberships_service, db_pool, member, gym_id, plan, discount_id):
    """Start a recurring membership and apply one regular discount to it.

    Returns the membership ``item_id``.
    """
    await memberships_service.start(
        member_id=member.member_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
        idempotency_key=uuid4(),
    )
    item_id = await get_active_membership_item_id(db_pool, member.member_id, gym_id)
    await memberships_service.add_discounts(
        item_id=item_id,
        member_id=member.member_id,
        preset_ids=[discount_id],
        idempotency_key=uuid4(),
    )
    return item_id


# ── Tests ───────────────────────────────────────────────────────


@pytest.mark.timeout(240)
async def test_remove_snapshot_scrubs_coupon_and_bills_full_next_cycle(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Removing a membership's applied-discount snapshot DELETEs the row,
    scrubs the coupon off the Stripe item, and bills the next cycle at the
    full price. No invoice is cut at edit time.
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
            gym_id, name="Removable 30% Off", percentage_off=30.0
        )

        item_id = await _start_and_apply(
            memberships_service, db_pool, member, gym_id, plan, discount.discount_id
        )
        profile = await get_profile_stripe_ids(db_pool, member.member_id, gym_id)

        snaps = await get_applied_snapshots(db_pool, item_id)
        assert len(snaps) == 1
        applied_id = snaps[0]["applied_discount_id"]
        coupon_id = snaps[0]["stripe_coupon_id"]
        assert coupon_id is not None

        sub = await fetch_subscription(stripe_client, profile.stripe_sub_id_month, connect_opts)
        assert coupon_id in _line_coupon_ids(sub, plan.stripe_price_id)

        before = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts
        )

        await memberships_service.remove_discounts(
            item_id=item_id,
            member_id=member.member_id,
            applied_ids=[applied_id],
            idempotency_key=uuid4(),
        )

        # Snapshot row is gone; coupon scrubbed; no edit-time charge.
        assert await get_applied_snapshots(db_pool, item_id) == []
        sub = await fetch_subscription(stripe_client, profile.stripe_sub_id_month, connect_opts)
        assert _line_coupon_ids(sub, plan.stripe_price_id) == set()
        await assert_no_unexpected_charges(stripe_client, before, connect_opts)

        invoice = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            NEXT_CYCLE,
            profile.stripe_sub_id_month,
            before,
            connect_opts,
        )
        assert_invoice_matches(invoice, amount_due=5000)
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)


@pytest.mark.timeout(240)
async def test_archiving_preset_leaves_holder_bill_unchanged(
    memberships_service,
    discounts_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Archiving the source preset must NOT touch an active holder.

    Predictability guarantee: a member's bill only changes via an explicit
    add/remove on their own membership. After the preset is archived, the
    holder keeps their snapshot, the coupon stays on the Stripe item, and the
    next cycle still bills the discounted amount.
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
            gym_id, name="Archive-Safe 20% Off", percentage_off=20.0
        )

        item_id = await _start_and_apply(
            memberships_service, db_pool, member, gym_id, plan, discount.discount_id
        )
        profile = await get_profile_stripe_ids(db_pool, member.member_id, gym_id)
        snap_coupon = (await get_applied_snapshots(db_pool, item_id))[0]["stripe_coupon_id"]
        assert snap_coupon is not None

        before = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts
        )

        # Archive the preset (soft-delete). Must not cascade.
        await discounts_service.delete_discount(discount.discount_id)

        # Holder keeps their snapshot + coupon; no charge at archive time.
        snaps = await get_applied_snapshots(db_pool, item_id)
        assert len(snaps) == 1
        sub = await fetch_subscription(stripe_client, profile.stripe_sub_id_month, connect_opts)
        assert snap_coupon in _line_coupon_ids(sub, plan.stripe_price_id)
        await assert_no_unexpected_charges(stripe_client, before, connect_opts)

        invoice = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            NEXT_CYCLE,
            profile.stripe_sub_id_month,
            before,
            connect_opts,
        )
        assert_invoice_matches(invoice, amount_due=int(round(5000 * 0.8)))
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)
