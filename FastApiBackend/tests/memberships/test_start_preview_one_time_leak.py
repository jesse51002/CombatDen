"""Integration: the start-preview one-time leak fix + the proration_behavior=no_charge
due_now rule.

Two bugs are guarded here, both in ``MemberMembershipsStartPreview.preview``:

1. **The one-time preview must contain ONLY the staged one-time lines.** Stripe's
   ``invoices.create_preview`` previews the customer's NEXT invoice, so a payer
   with a live recurring subscription gets the staged one-time invoice-item lines
   AND the subscription's upcoming recurring lines mixed together. The fix strips
   the subscription-derived lines (those carrying a ``stripe_subscription_item_id``
   and/or ``is_proration``) and recomputes the totals from the kept one-time lines.

2. **``due_now`` must be absent when ``proration_behavior=no_charge``.** With no proration the
   engine's ``due_now`` reuses the steady-state recurring figure, which is NOT due
   now — the start preview reports ``due_now=None`` in that case.

Real Stripe test Connect account; every test cleans up exactly what it creates.
"""

from uuid import uuid4

import pytest
from schema.task import ProrationBehavior
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from src.shared.sql_loader import load_sql
from tests.helpers.cleanup import delete_member_data
from tests.helpers.stripe_assertions import (
    assert_no_unexpected_charges,
    snapshot_billing_state,
)


async def _link_child(db_pool, child_id, parent_id) -> None:
    """Link a child to the payer via the production link SQL."""
    link_sql = load_sql(SQL_DIR / "member_memberships_link.sql")
    async with db_pool.session() as session:
        await session.execute(
            text(link_sql),
            {
                "member_id": str(child_id),
                "parent_member_id": str(parent_id),
            },
        )
        await session.commit()


async def _count_memberships(db_pool, member_id) -> int:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT COUNT(*) AS c FROM member_memberships_unfiltered "
                "WHERE member_id = :id"
            ),
            {"id": str(member_id)},
        )
        return int(result.mappings().one()["c"])


# ── Test 1 — THE LEAK REGRESSION ────────────────────────────────────


@pytest.mark.timeout(300)
async def test_one_time_preview_excludes_existing_subscription_lines(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A payer with a LIVE recurring sub previews a new one-time purchase.

    Sets the payer up on a real recurring subscription first, then previews a
    new request that contains a one-time membership (plus a second recurring
    membership for a linked child, so the mixed cart is realistic). The
    ``one_time`` half of the preview must reference ONLY the one-time plan's
    line — no line may carry a ``stripe_subscription_item_id``, none may be a
    proration, and its total must equal the one-time plan's (discounted) price.

    Before the fix the one-time preview leaked the live subscription's upcoming
    cycle lines (the payer's recurring price) mixed in with the one-time
    purchase.
    """
    pm_id = await created.payment_method()
    payer = await created.member(
        gym_id, first_name="Leak", last_name="Payer", payment_method_id=pm_id
    )
    child = await created.member(gym_id, first_name="Leak", last_name="Child")

    existing_recurring = await created.plan(
        gym_id, plan_name="Existing Monthly", price_cents=8999
    )
    one_time_plan = await created.plan(
        gym_id,
        plan_type="one_time",
        plan_name="Leak Day Pass",
        price_cents=3000,
        duration_amount=1,
        duration_unit="month",
    )
    child_recurring = await created.plan(
        gym_id, plan_name="Leak Child Monthly", price_cents=5000
    )

    try:
        await _link_child(db_pool, child.member_id, payer.member_id)

        # Stand the payer up on a LIVE recurring subscription first.
        first = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=payer.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=payer.member_id,
                        price_id=existing_recurring.price_id,
                    ),
                ],
            )
        )
        assert first.results[0].status.value == "created"

        before = await snapshot_billing_state(
            stripe_client, payer.stripe_customer_id, connect_opts
        )

        # Preview a NEW mixed cart: a one-time item + a recurring child item.
        preview = await memberships_service.preview_start(
            MemberMembershipsStartRequest(
                payer_member_id=payer.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=payer.member_id,
                        price_id=one_time_plan.price_id,
                    ),
                    MemberMembershipsStartItem(
                        member_id=child.member_id,
                        price_id=child_recurring.price_id,
                    ),
                ],
            )
        )

        assert preview.one_time is not None, "one-time half must be present"
        ot = preview.one_time

        # NO line references a subscription / is a proration — the leak guard.
        for line in ot.lines:
            assert line.stripe_subscription_item_id is None, (
                f"one-time preview leaked a subscription line: {line}"
            )
            assert line.is_proration is False, (
                f"one-time preview leaked a proration line: {line}"
            )

        # No line references the EXISTING subscription's price.
        leaked_prices = {
            line.stripe_price_id for line in ot.lines
        }
        assert existing_recurring.stripe_price_id not in leaked_prices, (
            "one-time preview leaked the existing recurring price"
        )
        assert child_recurring.stripe_price_id not in leaked_prices, (
            "one-time preview leaked the new recurring price"
        )

        # The total equals the one-time plan's (no discount) price exactly —
        # not the price + the subscription's recurring cycle.
        assert ot.total == one_time_plan.price_cents, (
            f"one_time.total={ot.total} != one-time price "
            f"{one_time_plan.price_cents} (subscription lines leaked in)"
        )
        assert ot.amount_due == one_time_plan.price_cents
        assert ot.subtotal == one_time_plan.price_cents

        # Preview wrote nothing: only the original recurring row persists.
        assert await _count_memberships(db_pool, payer.member_id) == 1
        assert await _count_memberships(db_pool, child.member_id) == 0
        await assert_no_unexpected_charges(
            stripe_client, before, connect_opts
        )
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, payer.member_id)


# ── Test 2 — proration_behavior=no_charge start preview → due_now is None ──────────


async def test_prorate_false_start_preview_due_now_is_none(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A non-prorating recurring start preview reports due_now=None.

    Nothing extra is charged now, so the misleading "reuse the recurring
    figure as due_now" is suppressed — ``due_now is None`` while ``recurring``
    is the steady-state cycle.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(gym_id, price_cents=5000)

    try:
        before = await snapshot_billing_state(
            stripe_client, member.stripe_customer_id, connect_opts
        )

        preview = await memberships_service.preview_start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.no_charge,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )

        assert preview.due_now is None, (
            "proration_behavior=no_charge start preview must report due_now=None"
        )
        assert preview.recurring is not None
        assert preview.recurring.amount_due == plan.price_cents

        assert await _count_memberships(db_pool, member.member_id) == 0
        await assert_no_unexpected_charges(
            stripe_client, before, connect_opts
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Test 3 — proration_behavior=prorate_to_anchor start preview → due_now present + real ────


async def test_prorate_true_start_preview_due_now_present(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A prorating recurring start preview reports a real proration due_now.

    ``due_now`` is present and is a genuine proration figure (>= 0 and never
    more than a full period) — not None, not the steady-state recurring amount
    reused (unless the anchor happens to land on a full period).
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(gym_id, price_cents=5000)

    try:
        before = await snapshot_billing_state(
            stripe_client, member.stripe_customer_id, connect_opts
        )

        preview = await memberships_service.preview_start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )

        assert preview.due_now is not None, (
            "proration_behavior=prorate_to_anchor start preview must carry a due_now proration"
        )
        assert preview.due_now.amount_due >= 0
        assert preview.due_now.amount_due <= plan.price_cents, (
            "the prorated first charge is never more than a full period"
        )
        assert preview.recurring is not None
        assert preview.recurring.amount_due == plan.price_cents

        assert await _count_memberships(db_pool, member.member_id) == 0
        await assert_no_unexpected_charges(
            stripe_client, before, connect_opts
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Test 4 — mixed-cart preview split is disjoint ───────────────────


@pytest.mark.timeout(240)
async def test_mixed_cart_preview_split_is_disjoint(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A mixed one-time + recurring start preview keeps the two halves disjoint.

    The ``one_time`` total must equal the one-time plan's price exactly and
    exclude the recurring amount entirely; the ``recurring`` total must equal
    the recurring plan's price. No staged-but-uncharged rows persist after the
    preview.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    one_time_plan = await created.plan(
        gym_id,
        plan_type="one_time",
        plan_name="Disjoint Day Pass",
        price_cents=3000,
        duration_amount=1,
        duration_unit="month",
    )
    recurring_plan = await created.plan(
        gym_id, plan_name="Disjoint Monthly", price_cents=7000
    )

    try:
        before = await snapshot_billing_state(
            stripe_client, member.stripe_customer_id, connect_opts
        )

        preview = await memberships_service.preview_start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=one_time_plan.price_id,
                    ),
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=recurring_plan.price_id,
                    ),
                ],
            )
        )

        assert preview.one_time is not None
        assert preview.recurring is not None

        # The one-time half is exactly the one-time price — the recurring
        # amount is entirely excluded.
        assert preview.one_time.total == one_time_plan.price_cents, (
            f"one_time.total={preview.one_time.total} must equal the one-time "
            f"price {one_time_plan.price_cents} and exclude recurring"
        )
        assert preview.one_time.total != recurring_plan.price_cents
        assert (
            preview.one_time.total
            != one_time_plan.price_cents + recurring_plan.price_cents
        ), "one_time must not include the recurring amount"

        # No one-time line carries a subscription id / proration flag.
        for line in preview.one_time.lines:
            assert line.stripe_subscription_item_id is None
            assert line.is_proration is False

        # The recurring half is the recurring plan's steady-state cycle.
        assert preview.recurring.amount_due == recurring_plan.price_cents

        assert await _count_memberships(db_pool, member.member_id) == 0
        await assert_no_unexpected_charges(
            stripe_client, before, connect_opts
        )
    finally:
        await delete_member_data(db_pool, member.member_id)
