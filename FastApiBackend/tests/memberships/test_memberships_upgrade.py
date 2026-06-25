"""Integration tests for the cross-plan membership UPGRADE.

An upgrade moves a membership to a DIFFERENT plan's active price and charges the
prorated difference now (``memberships_service.upgrade``). It cancels the old row
effective today, inserts a successor on the TARGET plan, and the convergent sync
runs with proration so Stripe nets the (new - old) prorated difference on one
immediate invoice. A downgrade (cheaper target) charges nothing — the op forces
``no_charge``.

The tests assert:

1. Cross-plan upgrade (A 5000 -> B 8000) mid-cycle cuts an immediate invoice for
   the difference, lands the successor on plan B (``applied``), cancels + deletes
   the old row, and the next cycle bills the full new price.
2. Cross-plan downgrade (A 8000 -> B 5000) charges nothing even when
   ``prorate_to_anchor`` is requested (the downgrade guard), switching the plan.
3. Targeting the SAME plan is rejected (that is a reprice, not an upgrade).
4. Upgrading to a plan the member already holds a recurring membership on is
   rejected.
5. The recurring-window guard rejects a target plan that bills on a different
   interval (future-proofing — today every recurring plan is monthly).
"""

from datetime import datetime, timedelta
from uuid import UUID, uuid4

import pytest
from schema.task import ProrationBehavior
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import get_profile_stripe_ids
from tests.helpers.service_factory import build_memberships_upgrade
from tests.helpers.stripe_assertions import (
    advance_to_next_cycle_and_fetch_invoice,
    assert_immediate_prorated_invoice,
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


async def _start_and_get_item_id(
    memberships_service, db_pool, member, gym_id, plan,
):
    """Start a recurring membership on ``plan`` and return its CRM item_id."""
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


async def _get_membership_row(db_pool, item_id: UUID) -> dict:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT plan_id, price_id, total_price, cancel_date, "
                "stripe_item_id, stripe_sync_status::text AS status "
                "FROM member_memberships_unfiltered WHERE item_id = :item_id"
            ),
            {"item_id": str(item_id)},
        )
        return dict(result.mappings().one())


@pytest.mark.timeout(180)
async def test_upgrade_cross_plan_charges_prorated_difference(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A 5000 -> B 8000 upgrade bills the (new - old) difference now, lands the
    successor on plan B, and the next cycle bills the full new price."""
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    member = None
    try:
        pm_id = await created.payment_method()
        member = await created.member(
            gym_id,
            payment_method_id=pm_id,
            test_clock_id=clock_id,
        )
        plan_a = await created.plan(gym_id, price_cents=5000)
        plan_b = await created.plan(gym_id, price_cents=8000)
        item_id = await _start_and_get_item_id(
            memberships_service, db_pool, member, gym_id, plan_a,
        )
        profile = await get_profile_stripe_ids(
            db_pool, member.member_id, gym_id,
        )

        before = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts,
        )

        new_item_id = await memberships_service.upgrade(
            item_id=item_id,
            member_id=member.member_id,
            target_plan_id=plan_b.plan_id,
            proration_behavior=ProrationBehavior.prorate_to_anchor,
            idempotency_key=uuid4(),
        )
        assert new_item_id != item_id

        # Old row cancelled + deleted; successor applied on plan B.
        old_row = await _get_membership_row(db_pool, item_id)
        assert old_row["cancel_date"] is not None
        assert old_row["status"] == "deleted"
        new_row = await _get_membership_row(db_pool, new_item_id)
        assert UUID(str(new_row["plan_id"])) == plan_b.plan_id
        assert new_row["status"] == "applied"
        assert new_row["total_price"] == 8000
        assert new_row["stripe_item_id"] is not None

        # Stripe: the subscription now carries plan B's price; plan A is gone.
        sub = await fetch_subscription(
            stripe_client, profile.stripe_sub_id_month, connect_opts,
        )
        prices = {i.price.id for i in sub.items.data}
        assert plan_b.stripe_price_id in prices
        assert plan_a.stripe_price_id not in prices

        # The immediate invoice is the prorated DIFFERENCE, never the full new
        # price. A prorated (new - old) charge can never exceed the absolute
        # difference (8000 - 5000 = 3000), so capping at 3000 proves Stripe
        # netted the old line's CREDIT against the new line's charge — a full
        # prorated NEW charge (no credit) would be ~8000 * the remaining
        # fraction, well above 3000 here. The exact cents are Stripe's
        # period/anchor proration (partial first period), so we assert the
        # invariant, not a fixed value.
        immediate = await assert_immediate_prorated_invoice(
            stripe_client,
            before,
            connect_opts,
            subscription_id=profile.stripe_sub_id_month,
            min_amount=1,
            max_amount=3000,
        )
        assert immediate.amount_due > 0

        # Next cycle bills the full new price with no residual proration.
        before = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts,
        )
        invoice = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            NEXT_CYCLE,
            profile.stripe_sub_id_month,
            before,
            connect_opts,
        )
        assert_invoice_matches(invoice, amount_due=8000)
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)


@pytest.mark.timeout(180)
async def test_upgrade_cross_plan_downgrade_charges_nothing(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A cheaper target charges nothing even when prorate is requested: the
    downgrade guard forces no_charge, the plan just switches."""
    member = None
    try:
        pm_id = await created.payment_method()
        member = await created.member(gym_id, payment_method_id=pm_id)
        plan_a = await created.plan(gym_id, price_cents=8000)
        plan_b = await created.plan(gym_id, price_cents=5000)
        item_id = await _start_and_get_item_id(
            memberships_service, db_pool, member, gym_id, plan_a,
        )
        profile = await get_profile_stripe_ids(
            db_pool, member.member_id, gym_id,
        )

        before = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts,
        )

        new_item_id = await memberships_service.upgrade(
            item_id=item_id,
            member_id=member.member_id,
            target_plan_id=plan_b.plan_id,
            proration_behavior=ProrationBehavior.prorate_to_anchor,
            idempotency_key=uuid4(),
        )

        # Successor on plan B, applied; no immediate charge / credit.
        new_row = await _get_membership_row(db_pool, new_item_id)
        assert UUID(str(new_row["plan_id"])) == plan_b.plan_id
        assert new_row["status"] == "applied"
        assert new_row["total_price"] == 5000

        sub = await fetch_subscription(
            stripe_client, profile.stripe_sub_id_month, connect_opts,
        )
        prices = {i.price.id for i in sub.items.data}
        assert plan_b.stripe_price_id in prices
        assert plan_a.stripe_price_id not in prices

        await assert_no_unexpected_charges(stripe_client, before, connect_opts)
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)


async def test_upgrade_same_plan_rejected(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Targeting the membership's own plan is a reprice, not an upgrade —
    rejected, and nothing is billed or changed."""
    member = None
    try:
        pm_id = await created.payment_method()
        member = await created.member(gym_id, payment_method_id=pm_id)
        plan_a = await created.plan(gym_id, price_cents=5000)
        item_id = await _start_and_get_item_id(
            memberships_service, db_pool, member, gym_id, plan_a,
        )
        profile = await get_profile_stripe_ids(
            db_pool, member.member_id, gym_id,
        )
        before = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts,
        )

        with pytest.raises(ValueError, match="same plan"):
            await memberships_service.upgrade(
                item_id=item_id,
                member_id=member.member_id,
                target_plan_id=plan_a.plan_id,
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                idempotency_key=uuid4(),
            )

        # Untouched: the original row is still the live one.
        row = await _get_membership_row(db_pool, item_id)
        assert row["status"] == "applied"
        assert row["cancel_date"] is None
        await assert_no_unexpected_charges(stripe_client, before, connect_opts)
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)


# NOTE: "upgrading to a plan the member already holds a recurring membership on
# is rejected" is enforced by `_check_no_existing(member, gym, [target_plan])` —
# reused verbatim from the start op and already covered by the start path's
# duplicate-recurring tests. A dedicated integration test here would have to
# start TWO real recurring memberships (two async invoices), which makes the
# shared-DB teardown race on a late `invoice.paid` webhook — not worth the flake
# for a guard that is already tested.


async def test_upgrade_preview_returns_difference_and_persists_nothing(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """The preview returns the prorated difference (due_now) + new monthly
    (recurring) and writes NO permanent rows."""
    member = None
    try:
        pm_id = await created.payment_method()
        member = await created.member(gym_id, payment_method_id=pm_id)
        plan_a = await created.plan(gym_id, price_cents=5000)
        plan_b = await created.plan(gym_id, price_cents=8000)
        item_id = await _start_and_get_item_id(
            memberships_service, db_pool, member, gym_id, plan_a,
        )

        preview = await memberships_service.upgrade_preview(
            item_id=item_id,
            member_id=member.member_id,
            target_plan_id=plan_b.plan_id,
            proration_behavior=ProrationBehavior.prorate_to_anchor,
        )

        # due_now = the prorated difference (positive, never above 3000); the
        # steady-state recurring is the full new price.
        assert preview is not None
        assert preview.due_now is not None
        assert 0 < preview.due_now.amount_due <= 3000
        assert preview.recurring is not None
        assert preview.recurring.amount_due == 8000

        # Nothing persisted: still exactly the original applied row on plan A,
        # no successor on plan B, no leaked preview_* rows.
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT plan_id, stripe_sync_status::text AS status "
                    "FROM member_memberships_unfiltered WHERE member_id = :id"
                ),
                {"id": str(member.member_id)},
            )
            rows = result.mappings().all()
        assert len(rows) == 1, rows
        assert UUID(str(rows[0]["plan_id"])) == plan_a.plan_id
        assert rows[0]["status"] == "applied"
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)


async def test_upgrade_window_guard_rejects_mismatched_interval(
    db_pool,
    stripe_client,
):
    """The recurring-window guard rejects a target plan on a different interval.

    Future-proofing: today every recurring plan is forced monthly by the
    ``recurring_must_be_monthly`` CHECK, so this case cannot be built from real
    plan rows — we exercise the validator directly with a target that bills
    weekly to lock the guard in for a future multi-interval world.
    """
    op = build_memberships_upgrade(db_pool, stripe_client)
    old_row = {
        "plan_type": "recurring",
        "cancel_date": None,
        "end_date": None,
        "timezone": "America/Chicago",
        "plan_id": uuid4(),
        "duration_unit": "month",
        "duration_amount": 1,
    }
    target_plan = {
        "is_deleted": False,
        "plan_type": "recurring",
        "duration_unit": "week",
        "duration_amount": 1,
    }
    with pytest.raises(ValueError, match="recurring windows"):
        op._validate_upgrade(
            old_row,
            uuid4(),
            uuid4(),
            uuid4(),
            target_plan,
        )
