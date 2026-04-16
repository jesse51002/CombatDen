"""Mid-cycle linked-discount tests using Stripe Test Clocks.

Linked discounts are a family-level sliding scale: each gym plan
can publish several ``DiscountType.linked`` rows with ascending
``linked_discount_num`` values, and the payment-sync layer
auto-assigns them to the sorted list of qualifying linked
children. These tests pin down two behaviors that matter in
production:

1. When one linked child's membership is cancelled mid-cycle,
   the allocator recomputes on the cancel's own sync and the
   remaining children end up with (possibly shifted) linked
   coupons on the Stripe subscription — one per surviving
   qualifying child — and the parent's subscription is NOT
   cancelled as a side effect (regression guard for the
   shared-price family-cancel bug).
2. The discounts service refuses to delete a ``linked`` discount
   via the normal delete path — the operation must raise and the
   Stripe subscription must remain untouched (negative test).
"""

from datetime import datetime, timedelta
from uuid import UUID

import pytest
from schema.gym_discount import DiscountType
from sqlalchemy import text
from starlette.background import BackgroundTasks

from src.discounts.schema.discounts_schema import DiscountCreateRequest
from src.payments.schema.payments_enums import StripeCouponDuration

from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import (
    create_member,
    create_payment_method,
    create_plan,
)
from tests.helpers.db_reads import (
    get_active_membership_item_id,
    get_profile_stripe_ids,
)
from tests.helpers.stripe_assertions import (
    _coerce_coupon_id,
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
CYCLE_AFTER_NEXT = CLOCK_START + timedelta(days=70)


async def _create_linked_child(
    db_pool,
    stripe_client,
    connect_opts,
    parent_crm_user_id: UUID,
    gym_id: UUID,
    label: str,
) -> UUID:
    """Create a linked-child profile that is still visible through
    the filtered ``user_gym_profiles`` view.

    The view filters on ``stripe_customer_id IS NOT NULL`` — linked
    children therefore still need their own Stripe customer record
    (they just don't get subscriptions, cards, or freeze dates, per
    the ``linked_account_no_stripe`` constraint). We lean on
    ``data_factory.create_member`` to produce a well-formed row and
    then attach the link in a second UPDATE.
    """
    child = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="Child",
        last_name=label,
    )
    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE user_gym_profiles_unfiltered "
                "SET account_linked_to_id = :parent "
                "WHERE crm_user_id = :id"
            ),
            {
                "parent": str(parent_crm_user_id),
                "id": str(child.crm_user_id),
            },
        )
        await session.commit()
    return child.crm_user_id


async def _start_child_membership(
    memberships_service, crm_user_id: UUID, gym_id: UUID, plan,
) -> None:
    """Start a recurring membership on a linked child with the
    linked-discount flag on.
    """
    await memberships_service.start(
        crm_user_id=crm_user_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
        include_linked_discount=True,
    )


async def _create_linked_discount(
    discounts_service,
    gym_id: UUID,
    plan_id: UUID,
    *,
    name: str,
    linked_num: int,
    dollar_off: int,
):
    return await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name=name,
            discount_type=DiscountType.linked,
            dollar_off=dollar_off,
            membership_plan_id=plan_id,
            linked_discount_num=linked_num,
            duration=StripeCouponDuration.forever,
        ),
    )


def _collect_sub_coupons(sub) -> set[str]:
    """Pull coupon ids off the subscription-level ``discounts`` field.

    Linked discounts are applied at the subscription level (not on
    individual items) by ``allocate_linked_discounts`` in
    ``payment_sync_discount_allocator.py``, so this is where tests
    must look to verify them.
    """
    found: set[str] = set()
    for disc in getattr(sub, "discounts", None) or []:
        coupon_id = _coerce_coupon_id(disc)
        if coupon_id is not None:
            found.add(coupon_id)
    return found


# ── Tests ───────────────────────────────────────────────────────


@pytest.mark.timeout(300)
async def test_linked_discount_child_loses_qualification_tiers_shift_up(
    memberships_service,
    payment_sync_service,
    discounts_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Remove one child's linked-discount qualification mid-cycle
    and verify the remaining children still hold linked coupons
    (one per qualifying child) on the Stripe subscription.

    Exact assignment by crm_user_id ordering is an implementation
    detail of ``calculate_linked_discount_ids`` — what matters for
    billing correctness is the invariant: after the allocator runs
    again, the number of live linked coupons on the subscription
    equals the number of remaining qualifying children, and each
    coupon is drawn from the pool of linked discounts we set up
    on the plan.
    """
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    parent = None
    child_ids: list[UUID] = []
    try:
        pm_id = await create_payment_method(stripe_client, connect_opts)
        parent = await create_member(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            payment_method_id=pm_id,
            test_clock_id=clock_id,
            first_name="Parent",
            last_name="Linked",
        )
        plan = await create_plan(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            price_cents=10000,
        )

        # Three linked-discount tiers on the plan. The concrete
        # dollar amounts are chosen so the allocator's "largest
        # discount wins" ranking has a clean ordering.
        tier_1 = await _create_linked_discount(
            discounts_service, gym_id, plan.plan_id,
            name="Linked Tier 1", linked_num=1, dollar_off=3000,
        )
        tier_2 = await _create_linked_discount(
            discounts_service, gym_id, plan.plan_id,
            name="Linked Tier 2", linked_num=2, dollar_off=2000,
        )
        tier_3 = await _create_linked_discount(
            discounts_service, gym_id, plan.plan_id,
            name="Linked Tier 3", linked_num=3, dollar_off=1000,
        )
        tier_coupon_ids = {
            tier_1.stripe_coupon_id,
            tier_2.stripe_coupon_id,
            tier_3.stripe_coupon_id,
        }

        # Parent first (no linked discount) so they seed the
        # family's Stripe subscription.
        await memberships_service.start(
            crm_user_id=parent.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )

        # Three linked children — each starts a membership on the
        # same plan with ``include_linked_discount=True`` so the
        # allocator assigns them a linked coupon.
        for label in ("Alpha", "Bravo", "Charlie"):
            child_id = await _create_linked_child(
                db_pool, stripe_client, connect_opts,
                parent.crm_user_id, gym_id, label,
            )
            child_ids.append(child_id)
            await _start_child_membership(
                memberships_service, child_id, gym_id, plan,
            )

        profile = await get_profile_stripe_ids(
            db_pool, parent.crm_user_id, gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        sub = await fetch_subscription(
            stripe_client, profile.stripe_sub_id_month, connect_opts,
            expand=(
                "items.data.price",
                "items.data.discounts.coupon",
                "discounts",
            ),
        )
        live_coupons_before = _collect_sub_coupons(sub)
        # Exactly three linked coupons must be attached — one per
        # qualifying child — and every one must come from the
        # pool we created.
        assert len(live_coupons_before) == 3, (
            f"Expected 3 linked coupons on {sub.id}, got "
            f"{sorted(live_coupons_before)}"
        )
        assert live_coupons_before.issubset(tier_coupon_ids), (
            f"Unexpected coupon ids on {sub.id}: "
            f"{sorted(live_coupons_before - tier_coupon_ids)}"
        )

        plan_price = 10000
        # Allocator applies the largest tiers to the qualifying
        # children. With top 3 tiers available: tier_1 ($3000)
        # for the 1st child, tier_2 ($2000) for the 2nd, tier_3
        # ($1000) for the 3rd.
        # ── Settle the first invoice cycle ─────────────────────
        # Advance through the first cycle so all the mid-cycle
        # prorations from the child adds land on a single
        # invoice the test doesn't have to reason about. What
        # it cares about is the *next* invoice after the cancel
        # being clean.
        before_first_cycle = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts,
        )
        first_cycle_invoice = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            NEXT_CYCLE,
            profile.stripe_sub_id_month,
            before_first_cycle,
            connect_opts,
        )
        # Sanity: first cycle invoice did apply all three linked
        # coupons. We only check ``discount_total`` since the
        # subtotal on this invoice includes proration churn from
        # the mid-cycle adds.
        full_linked_off = 3000 + 2000 + 1000
        assert_invoice_matches(
            first_cycle_invoice,
            discount_total=full_linked_off,
        )

        before = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts,
        )

        # Drop one child out of the qualifying set by cancelling
        # their membership. This goes through the real cancel
        # path — including the ``(crm_user_id, plan_id)`` filter
        # at the service layer, which must NOT drop the parent's
        # or the other siblings' rows on this shared family plan.
        dropped_item_id = await get_active_membership_item_id(
            db_pool, child_ids[0], gym_id,
        )
        await memberships_service.cancel(
            item_id=dropped_item_id,
            crm_user_id=child_ids[0],
        )

        await assert_no_unexpected_charges(
            stripe_client, before, connect_opts,
        )

        sub = await fetch_subscription(
            stripe_client, profile.stripe_sub_id_month, connect_opts,
            expand=(
                "items.data.price",
                "items.data.discounts.coupon",
                "discounts",
            ),
        )

        # Regression guard: cancelling one child on a shared
        # family plan must NOT cancel the parent's whole sub.
        assert sub.status == "active", (
            f"Parent subscription {sub.id} was {sub.status} after "
            f"cancelling a single child — shared-plan cancel filter "
            f"is dropping sibling rows again"
        )

        live_coupons_after = _collect_sub_coupons(sub)

        # Invariant: exactly two linked coupons now, all drawn
        # from the original tier pool. The cancelled child has
        # left the qualifying set and the allocator has reduced
        # the subscription-level coupon set accordingly.
        assert len(live_coupons_after) == 2, (
            f"Expected 2 linked coupons after cancelling one child on "
            f"{sub.id}, got {sorted(live_coupons_after)}"
        )
        assert live_coupons_after.issubset(tier_coupon_ids), (
            f"Unexpected coupon ids after cancelling one child on "
            f"{sub.id}: {sorted(live_coupons_after - tier_coupon_ids)}"
        )

        # Independent billing-amount verification — advance to
        # the cycle AFTER the cancel, then check the new invoice
        # against a calculation this test owns end-to-end. This
        # is the regression guard that would have caught the
        # shared-price family-cancel bug even if the coupon-set
        # check drifted: a silently-cancelled sibling row would
        # still show up on this invoice.
        surviving_members = 3  # parent + 2 remaining children
        # With 2 qualifying children remaining, the top 2 tiers
        # apply: tier_1 ($3000) + tier_2 ($2000).
        linked_dollar_off = 3000 + 2000
        expected_amount = plan_price * surviving_members - linked_dollar_off

        invoice = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            CYCLE_AFTER_NEXT,
            profile.stripe_sub_id_month,
            before,
            connect_opts,
        )
        assert_invoice_matches(
            invoice,
            amount_due=expected_amount,
            subtotal=plan_price * surviving_members,
            discount_total=linked_dollar_off,
        )
    finally:
        for cid in child_ids:
            await delete_member_data(db_pool, cid)
        if parent is not None:
            await delete_member_data(db_pool, parent.crm_user_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)


@pytest.mark.timeout(180)
async def test_delete_linked_discount_is_blocked_and_stripe_untouched(
    memberships_service,
    payment_sync_service,
    discounts_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """The discounts service must refuse to delete a ``linked``
    discount through the normal delete path. The exception raised
    is an invariant, and crucially the Stripe subscription must
    still carry the coupon afterwards.
    """
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    parent = None
    child_id: UUID | None = None
    try:
        pm_id = await create_payment_method(stripe_client, connect_opts)
        parent = await create_member(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            payment_method_id=pm_id,
            test_clock_id=clock_id,
            first_name="Parent",
            last_name="LinkedBlock",
        )
        plan = await create_plan(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            price_cents=6000,
        )
        tier = await _create_linked_discount(
            discounts_service, gym_id, plan.plan_id,
            name="Linked Delete Guard", linked_num=1, dollar_off=2000,
        )

        await memberships_service.start(
            crm_user_id=parent.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )
        child_id = await _create_linked_child(
            db_pool, stripe_client, connect_opts,
            parent.crm_user_id, gym_id, "Solo",
        )
        await _start_child_membership(
            memberships_service, child_id, gym_id, plan,
        )

        profile = await get_profile_stripe_ids(
            db_pool, parent.crm_user_id, gym_id,
        )
        sub = await fetch_subscription(
            stripe_client, profile.stripe_sub_id_month, connect_opts,
            expand=(
                "items.data.price",
                "items.data.discounts.coupon",
                "discounts",
            ),
        )
        assert tier.stripe_coupon_id in _collect_sub_coupons(sub), (
            f"Setup failure: linked coupon {tier.stripe_coupon_id} not "
            f"attached to subscription {sub.id} before the delete attempt"
        )

        before = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts,
        )

        with pytest.raises(ValueError, match="linked"):
            await discounts_service.delete_discount(
                tier.discount_id,
                gym_id,
                background_tasks=BackgroundTasks(),
            )

        # Stripe must be completely unaffected. The coupon must
        # still be attached, no invoice churn, no customer balance
        # movement.
        await assert_no_unexpected_charges(
            stripe_client, before, connect_opts,
        )
        sub = await fetch_subscription(
            stripe_client, profile.stripe_sub_id_month, connect_opts,
            expand=(
                "items.data.price",
                "items.data.discounts.coupon",
                "discounts",
            ),
        )
        assert tier.stripe_coupon_id in _collect_sub_coupons(sub), (
            f"Linked coupon {tier.stripe_coupon_id} vanished from "
            f"{sub.id} even though delete was supposed to be blocked"
        )

        # CRM row must still be live — delete should NOT have
        # flipped ``is_deleted`` before the guard fired.
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT is_deleted FROM gym_discounts_unfiltered "
                    "WHERE discount_id = :id"
                ),
                {"id": str(tier.discount_id)},
            )
            row = result.mappings().fetchone()
        assert row is not None
        assert row["is_deleted"] is False, (
            "Linked discount was soft-deleted despite the delete "
            "path supposedly refusing the operation"
        )
    finally:
        if child_id is not None:
            await delete_member_data(db_pool, child_id)
        if parent is not None:
            await delete_member_data(db_pool, parent.crm_user_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)
