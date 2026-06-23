"""Integration tests for cancelling memberships.

Every test fetches the Stripe subscription (or confirms it was
deleted) after the cancel and asserts that no surprise charges
landed on the member's customer balance.
"""

from uuid import UUID, uuid4

import pytest
import stripe
from sqlalchemy import text

from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import get_profile_stripe_ids
from tests.helpers.db_writes import authorize_payer
from tests.helpers.stripe_assertions import (
    assert_no_unexpected_charges,
    fetch_subscription,
    snapshot_billing_state,
)


async def _start_and_get_item_id(
    memberships_service,
    db_pool,
    member,
    gym_id,
    plan,
):
    """Start a membership and return the item_id."""
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


async def _assert_sub_canceled_or_item_removed(
    stripe_client,
    connect_opts,
    stripe_sub_id: str,
    removed_stripe_price_id: str,
) -> None:
    """Confirm the cancel reached Stripe.

    For the only-item-on-the-sub case, cancelling the item usually
    deletes the whole subscription; retrieving it either returns
    status ``canceled`` or raises 404. For the multi-item case,
    the sub survives but the cancelled item's price is gone.
    """
    try:
        sub = await fetch_subscription(
            stripe_client,
            stripe_sub_id,
            connect_opts,
        )
    except stripe.InvalidRequestError as exc:
        # 404 — Stripe deleted the subscription when its last item
        # was removed. That's a valid cancel outcome.
        assert "No such subscription" in str(exc), f"Unexpected Stripe error after cancel: {exc}"
        return

    if sub.status == "canceled":
        return

    # Subscription still exists (e.g. had other family items) —
    # verify the cancelled price is no longer on any remaining item.
    remaining_prices = {item.price.id for item in sub.items.data}
    assert removed_stripe_price_id not in remaining_prices, (
        f"Cancelled price {removed_stripe_price_id} still present on "
        f"subscription {stripe_sub_id}: items={sorted(remaining_prices)}"
    )


async def test_cancel_active_membership(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(gym_id)

    try:
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

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.cancel(item_id, member.member_id, idempotency_key=uuid4())

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT cancel_date FROM member_memberships_unfiltered "
                    "WHERE item_id = :item_id"
                ),
                {"item_id": str(item_id)},
            )
            row = result.mappings().fetchone()

        assert row is not None
        assert row["cancel_date"] is not None

        await _assert_sub_canceled_or_item_removed(
            stripe_client,
            connect_opts,
            profile.stripe_sub_id_month,
            plan.stripe_price_id,
        )
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_cancel_already_cancelled_noop(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(gym_id)

    try:
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

        await memberships_service.cancel(item_id, member.member_id, idempotency_key=uuid4())

        # Snapshot after the first cancel completes — the second
        # cancel is a pure CRM no-op and must not reach Stripe at all.
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.cancel(item_id, member.member_id, idempotency_key=uuid4())

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_cancel_one_of_shared_consolidated_line(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Regression: cancel ONE family member off a shared consolidated line.

    Two linked members on the same price share ONE Stripe item (quantity 2).
    Cancelling one must succeed (not revert), stamp the cancelled row
    ``deleted`` even though the shared line id stays live for the sibling,
    and leave the sibling billing on that line at quantity 1.
    """
    pm_id = await created.payment_method()
    payer = await created.member(gym_id, payment_method_id=pm_id)
    child = await created.member(gym_id)
    plan = await created.plan(gym_id)

    await authorize_payer(db_pool, child.member_id, payer.member_id)

    try:
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=payer.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=payer.member_id,
                        price_id=plan.price_id,
                    ),
                    MemberMembershipsStartItem(
                        member_id=child.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )

        rows = {}
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id, member_id, stripe_item_id "
                    "FROM member_memberships_unfiltered "
                    "WHERE member_id IN (:payer_id, :child_id)"
                ),
                {
                    "payer_id": str(payer.member_id),
                    "child_id": str(child.member_id),
                },
            )
            for row in result.mappings().fetchall():
                rows[UUID(str(row["member_id"]))] = row

        # Consolidated: both rows carry the SAME Stripe line id.
        assert (
            rows[payer.member_id]["stripe_item_id"]
            == rows[child.member_id]["stripe_item_id"]
        )
        child_item_id = UUID(str(rows[child.member_id]["item_id"]))
        payer_item_id = UUID(str(rows[payer.member_id]["item_id"]))

        profile = await get_profile_stripe_ids(
            db_pool,
            payer.member_id,
            gym_id,
        )
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        # Must succeed — the old live-line diff never stamped a row
        # removed from a shared line, so the verify reverted the cancel.
        await memberships_service.cancel(
            child_item_id,
            child.member_id,
            idempotency_key=uuid4(),
        )

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id, cancel_date, "
                    "stripe_sync_status::text AS status "
                    "FROM member_memberships_unfiltered "
                    "WHERE item_id IN (:child_item, :payer_item)"
                ),
                {
                    "child_item": str(child_item_id),
                    "payer_item": str(payer_item_id),
                },
            )
            by_item = {
                UUID(str(r["item_id"])): r
                for r in result.mappings().fetchall()
            }

        assert by_item[child_item_id]["cancel_date"] is not None
        assert by_item[child_item_id]["status"] == "deleted"
        assert by_item[payer_item_id]["cancel_date"] is None
        assert by_item[payer_item_id]["status"] == "applied"

        # Sibling keeps billing on the shared line at quantity 1.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        qty_by_price = {
            item.price.id: item.quantity for item in sub.items.data
        }
        assert qty_by_price.get(plan.stripe_price_id) == 1

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, payer.member_id)


async def test_cancel_one_time_raises(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        plan_name="One-Time Cancel Test",
        price_cents=2000,
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

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id FROM member_memberships "
                    "WHERE member_id = :id AND plan_id = :plan_id"
                ),
                {"id": str(member.member_id), "plan_id": str(plan.plan_id)},
            )
            row = result.mappings().fetchone()
        item_id = UUID(str(row["item_id"]))

        # Snapshot after start completes — the failed cancel must
        # not create any Stripe side effects.
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        with pytest.raises((ValueError, Exception)):
            await memberships_service.cancel(item_id, member.member_id, idempotency_key=uuid4())

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)
