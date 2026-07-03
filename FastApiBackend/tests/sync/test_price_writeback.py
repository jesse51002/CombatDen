"""Integration tests for per-membership total_price + parent monthly total.

These exercise the end-to-end sync writeback:

* ``member_memberships.total_price`` holds each membership's OWN
  post-discount price (its plan price minus its own discounts), written
  per ``item_id`` — NOT a plan/family total fanned across rows.
* ``members.total_monthly_recurring_price`` holds the paying parent's full
  monthly recurring charge from Stripe's upcoming invoice.

Scenarios covered:

1. Parent + linked child on the **same plan** (consolidated qty=2 line) →
   each row holds its own price, and they sum to the plan total the CRM
   derives.
2. Parent + linked child on **different plans** → each row stores its own
   plan's price; no cross-plan bleed.
3. **Cross-family isolation** → another family on the same plan is untouched
   after a mutation to the first family's subscription (the per-member write
   is keyed by ``item_id``).
4. **stripe_sub_id is None** (fully cancelled parent) → profile monthly total
   is zeroed.
"""

from uuid import UUID, uuid4

from sqlalchemy import text

from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import get_profile_stripe_ids
from tests.helpers.db_writes import authorize_payer

# ── Helpers ─────────────────────────────────────────────────────


async def _fetch_total_price(db_pool, member_id: UUID, plan_id: UUID) -> int:
    """Return total_price from the active member_memberships row."""
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT total_price FROM member_memberships "
                "WHERE member_id = :member_id "
                "  AND plan_id = :plan_id "
                "  AND cancel_date IS NULL"
            ),
            {"member_id": str(member_id), "plan_id": str(plan_id)},
        )
        row = result.mappings().fetchone()
    if row is None:
        raise AssertionError(
            f"No active membership for member_id={member_id} plan_id={plan_id}"
        )
    return int(row["total_price"])


async def _fetch_profile_monthly(db_pool, member_id: UUID) -> int:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT total_monthly_recurring_price "
                "FROM members "
                "WHERE member_id = :member_id"
            ),
            {"member_id": str(member_id)},
        )
        row = result.mappings().fetchone()
    if row is None:
        raise AssertionError(f"No members row for member_id={member_id}")
    return int(row["total_monthly_recurring_price"] or 0)


async def _fetch_item_id(db_pool, member_id: UUID, plan_id: UUID) -> UUID:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT item_id FROM member_memberships "
                "WHERE member_id = :member_id "
                "  AND plan_id = :plan_id "
                "  AND cancel_date IS NULL"
            ),
            {"member_id": str(member_id), "plan_id": str(plan_id)},
        )
        row = result.mappings().fetchone()
    if row is None:
        raise AssertionError(
            f"No active membership for member_id={member_id} plan_id={plan_id}"
        )
    return UUID(str(row["item_id"]))


# ── Scenario 1: same plan, parent + child ──────────────────────


async def test_family_same_plan_each_row_holds_own_price(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Parent + linked child on the same plan → each row holds its OWN price
    (not the family total).

    With consolidation Stripe sees one subscription item at qty=2, but each
    member_memberships row stores that member's own 5000; the two rows sum to
    the 10000 plan total the CRM derives.
    """
    pm_id = await created.payment_method()
    parent = await created.member(
        gym_id,
        first_name="FamSame",
        last_name="Parent",
        payment_method_id=pm_id,
    )
    child = await created.member(
        gym_id,
        first_name="FamSame",
        last_name="Child",
    )
    plan = await created.plan(
        gym_id,
        plan_name="Fam Same Plan",
        price_cents=5000,
    )

    try:
        await authorize_payer(db_pool, child.member_id, parent.member_id)

        # Parent starts first → qty=1, line total = 5000
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=parent.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=parent.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )

        parent_only = await _fetch_total_price(
            db_pool,
            parent.member_id,
            plan.plan_id,
        )
        assert parent_only == 5000, (
            f"After parent start, parent total_price should be 5000, got {parent_only}"
        )

        # Child joins → qty=2 on the same sub item, line total = 10000
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=parent.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=child.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )

        parent_total = await _fetch_total_price(
            db_pool,
            parent.member_id,
            plan.plan_id,
        )
        child_total = await _fetch_total_price(
            db_pool,
            child.member_id,
            plan.plan_id,
        )
        assert parent_total == 5000, (
            f"Parent row should hold its own price 5000, got {parent_total}"
        )
        assert child_total == 5000, (
            f"Child row should hold its own price 5000, got {child_total}"
        )
        # Each member's own price; together they sum to the plan total (10000).
        assert parent_total + child_total == 10000

        # Profile monthly recurring total mirrors amount_due.
        parent_monthly = await _fetch_profile_monthly(db_pool, parent.member_id)
        assert parent_monthly == 10000, (
            f"Parent profile monthly should equal amount_due 10000, got {parent_monthly}"
        )

        # Stripe subscription should exist (sanity).
        profile = await get_profile_stripe_ids(
            db_pool,
            parent.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


# ── Scenario 2: different plans, parent + child ────────────────


async def test_family_different_plans_per_row_totals(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Parent on plan A, linked child on plan B → each row holds its
    own plan's line total; the parent's row is not bumped by the
    child's plan total and vice versa.
    """
    pm_id = await created.payment_method()
    parent = await created.member(
        gym_id,
        first_name="FamDiff",
        last_name="Parent",
        payment_method_id=pm_id,
    )
    child = await created.member(
        gym_id,
        first_name="FamDiff",
        last_name="Child",
    )
    plan_a = await created.plan(
        gym_id,
        plan_name="Plan A",
        price_cents=5000,
    )
    plan_b = await created.plan(
        gym_id,
        plan_name="Plan B",
        price_cents=3000,
    )

    try:
        await authorize_payer(db_pool, child.member_id, parent.member_id)

        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=parent.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=parent.member_id,
                        price_id=plan_a.price_id,
                    ),
                ],
            )
        )
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=parent.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=child.member_id,
                        price_id=plan_b.price_id,
                    ),
                ],
            )
        )

        parent_a = await _fetch_total_price(
            db_pool,
            parent.member_id,
            plan_a.plan_id,
        )
        child_b = await _fetch_total_price(
            db_pool,
            child.member_id,
            plan_b.plan_id,
        )
        assert parent_a == 5000, (
            f"Parent row on plan A should hold plan A total 5000, got {parent_a}"
        )
        assert child_b == 3000, f"Child row on plan B should hold plan B total 3000, got {child_b}"

        # Profile monthly is the full amount_due across both plans.
        parent_monthly = await _fetch_profile_monthly(db_pool, parent.member_id)
        assert parent_monthly == 8000, (
            f"Parent profile monthly should equal amount_due 8000, got {parent_monthly}"
        )
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


# ── Scenario 3: cross-family isolation ─────────────────────────


async def test_cross_family_isolation(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Two unrelated families on the same plan. A mutation inside
    family A's subscription must never write to family B's rows.
    """
    pm_a = await created.payment_method()
    family_a = await created.member(
        gym_id,
        first_name="FamA",
        last_name="Parent",
        payment_method_id=pm_a,
    )
    pm_b = await created.payment_method()
    family_b = await created.member(
        gym_id,
        first_name="FamB",
        last_name="Parent",
        payment_method_id=pm_b,
    )
    plan = await created.plan(
        gym_id,
        plan_name="Shared Plan",
        price_cents=5000,
    )

    try:
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=family_a.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=family_a.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=family_b.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=family_b.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )

        # Both families should have independent 5000 totals.
        a_before = await _fetch_total_price(
            db_pool,
            family_a.member_id,
            plan.plan_id,
        )
        b_before = await _fetch_total_price(
            db_pool,
            family_b.member_id,
            plan.plan_id,
        )
        assert a_before == 5000
        assert b_before == 5000

        # Cancel family A's membership → triggers a writeback on A's
        # subscription. Family B's row must remain untouched.
        item_a = await _fetch_item_id(
            db_pool,
            family_a.member_id,
            plan.plan_id,
        )
        await memberships_service.cancel(
            item_a,
            family_a.member_id,
            idempotency_key=uuid4(),
        )

        b_after = await _fetch_total_price(
            db_pool,
            family_b.member_id,
            plan.plan_id,
        )
        assert b_after == 5000, (
            f"Family B row should be untouched after family A cancel, got {b_after}"
        )

        # Family B's profile monthly is also unchanged.
        b_monthly = await _fetch_profile_monthly(db_pool, family_b.member_id)
        assert b_monthly == 5000, (
            f"Family B profile monthly should be unchanged at 5000, got {b_monthly}"
        )
    finally:
        await delete_member_data(db_pool, family_a.member_id)
        await delete_member_data(db_pool, family_b.member_id)


# ── Scenario 4: full cancellation zeroes the parent monthly ────


async def test_full_cancel_zeroes_parent_monthly_total(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """When the parent's only membership is cancelled, the Stripe
    subscription goes away and the writeback must zero the profile
    monthly total (the stripe_sub_id=None code path).
    """
    pm_id = await created.payment_method()
    member = await created.member(
        gym_id,
        first_name="SoloCancel",
        last_name="Member",
        payment_method_id=pm_id,
    )
    plan = await created.plan(
        gym_id,
        plan_name="Solo Plan",
        price_cents=4500,
    )

    try:
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
        before = await _fetch_profile_monthly(db_pool, member.member_id)
        assert before == 4500

        item_id = await _fetch_item_id(
            db_pool,
            member.member_id,
            plan.plan_id,
        )
        await memberships_service.cancel(item_id, member.member_id, idempotency_key=uuid4())

        after = await _fetch_profile_monthly(db_pool, member.member_id)
        assert after == 0, f"Profile monthly should be zeroed after full cancel, got {after}"
    finally:
        await delete_member_data(db_pool, member.member_id)
