"""Integration tests for the DIRECT (single) membership reprice.

The member-detail upgrade is a direct, synchronous op (NOT a task — tasks are
only for the per-plan batch): ``memberships_service.update_price`` cancels the
old row effective today, inserts a successor at the plan's active price,
converges Stripe, and RETURNS the successor's item_id (== the input id on a
no-op). The tests assert:

1. The old row is cancelled + ``deleted``, its ``price_id`` untouched
   (trigger-immutable), and the successor row is ``applied`` on the new
   price with a fresh Stripe line.
2. The Stripe subscription carries the new price; the old price is gone.
3. No surprise invoice was created (``proration_behavior=no_charge`` path).
4. An invalid (cancelled) reprice raises and mutates nothing; a no-op
   (already on the active price) returns the row's own id unchanged.
"""

from uuid import UUID, uuid4

import pytest
from schema.task import ProrationBehavior
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.discounts.schema.discounts_schema import DiscountValue
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from src.plans.plans_schema import MembershipPlanPriceRequest
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import (
    get_applied_discounts,
    get_profile_stripe_ids,
)
from tests.helpers.db_writes import authorize_payer
from tests.helpers.service_factory import build_memberships_reprice
from tests.helpers.stripe_assertions import (
    assert_no_unexpected_charges,
    assert_subscription_item_price,
    fetch_subscription,
    snapshot_billing_state,
)


async def _start_and_get_item_id(memberships_service, db_pool, member, gym_id, plan):
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
                "SELECT price_id, total_price, cancel_date, stripe_item_id, "
                "stripe_sync_status::text AS status "
                "FROM member_memberships_unfiltered WHERE item_id = :item_id"
            ),
            {"item_id": str(item_id)},
        )
        return dict(result.mappings().one())


async def test_update_price_tier(
    memberships_service,
    plans_service,
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
        old_row_before = await _get_membership_row(db_pool, item_id)

        # Use the production service to create a second price tier
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

        new_item_id = await memberships_service.update_price(
            item_id=item_id,
            member_id=member.member_id,
            proration_behavior=ProrationBehavior.no_charge,
        )
        assert new_item_id != item_id

        # Old row: cancelled + deleted, identity untouched (append-only).
        old_row = await _get_membership_row(db_pool, item_id)
        assert old_row["cancel_date"] is not None
        assert old_row["status"] == "deleted"
        assert old_row["price_id"] == old_row_before["price_id"]
        assert old_row["stripe_item_id"] == old_row_before["stripe_item_id"]

        # Successor row: applied on the new price, with its OWN line.
        new_row = await _get_membership_row(db_pool, new_item_id)
        assert UUID(str(new_row["price_id"])) == new_price.price_id
        assert new_row["total_price"] == 8000
        assert new_row["status"] == "applied"
        assert new_row["stripe_item_id"] is not None
        assert new_row["stripe_item_id"] != old_row["stripe_item_id"]

        # Stripe side: the subscription must now carry the new price
        # id on exactly one item, and no new invoice may have been
        # created (proration_behavior=no_charge is the existing contract).
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        new_price_items = [
            (idx, item_)
            for idx, item_ in enumerate(sub.items.data)
            if item_.price.id == new_price.stripe_price_id
        ]
        assert len(new_price_items) == 1, (
            f"Expected exactly one item on {new_price.stripe_price_id}; "
            f"items={[i.price.id for i in sub.items.data]}"
        )
        assert_subscription_item_price(
            sub,
            new_price.stripe_price_id,
            index=new_price_items[0][0],
        )
        # Old price must be gone.
        remaining_prices = {item_.price.id for item_ in sub.items.data}
        assert plan.stripe_price_id not in remaining_prices, (
            f"Old price {plan.stripe_price_id} still on subscription "
            f"{profile.stripe_sub_id_month} after reprice"
        )

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_reprice_one_member_off_shared_consolidated_line(
    memberships_service,
    plans_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Reprice ONE family member off a shared consolidated line.

    Two linked members on one price share ONE Stripe item (quantity 2).
    Repricing one must: leave the sibling billing on the shared line at
    quantity 1, land the repriced member on a NEW sub-item at the new
    price, cancel + stamp 'deleted' the old row (a new immutable row
    carries the new line), and COPY the live applied discounts (incl. a
    custom) onto the successor while the old rows stay as records.
    """
    pm_id = await created.payment_method()
    payer = await created.member(gym_id, payment_method_id=pm_id)
    child = await created.member(gym_id)
    plan = await created.plan(gym_id)
    preset = await created.discount(gym_id, percentage_off=20)

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
                        discount_ids=[preset.discount_id],
                        custom_discounts=[
                            DiscountValue(
                                percentage_off=15.0,
                            ),
                        ],
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
                rows[UUID(str(row["member_id"]))] = dict(row)

        shared_line_id = rows[payer.member_id]["stripe_item_id"]
        assert rows[child.member_id]["stripe_item_id"] == shared_line_id
        child_item_id = UUID(str(rows[child.member_id]["item_id"]))
        payer_item_id = UUID(str(rows[payer.member_id]["item_id"]))

        old_discounts = await get_applied_discounts(db_pool, child_item_id)
        assert len(old_discounts) == 2
        old_value_ids = {str(d["value_id"]) for d in old_discounts}

        profile = await get_profile_stripe_ids(
            db_pool,
            payer.member_id,
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

        new_item_id = await memberships_service.update_price(
            item_id=child_item_id,
            member_id=child.member_id,
            proration_behavior=ProrationBehavior.no_charge,
        )

        # Old row: cancelled + deleted, identity untouched; sibling intact.
        old_row = await _get_membership_row(db_pool, child_item_id)
        assert old_row["cancel_date"] is not None
        assert old_row["status"] == "deleted"
        assert old_row["stripe_item_id"] == shared_line_id
        payer_row = await _get_membership_row(db_pool, payer_item_id)
        assert payer_row["cancel_date"] is None
        assert payer_row["status"] == "applied"
        assert payer_row["stripe_item_id"] == shared_line_id

        # Successor: new immutable row on a NEW sub-item at the new price.
        new_row = await _get_membership_row(db_pool, new_item_id)
        assert UUID(str(new_row["price_id"])) == new_price.price_id
        assert new_row["status"] == "applied"
        assert new_row["stripe_item_id"] is not None
        assert new_row["stripe_item_id"] != shared_line_id

        # Stripe: sibling stays on the shared line at quantity 1; the
        # repriced member's new price is its own quantity-1 item.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        qty_by_price = {
            i.price.id: i.quantity for i in sub.items.data
        }
        line_by_price = {
            i.price.id: i.id for i in sub.items.data
        }
        assert qty_by_price.get(plan.stripe_price_id) == 1
        assert line_by_price.get(plan.stripe_price_id) == shared_line_id
        assert qty_by_price.get(new_price.stripe_price_id) == 1
        assert line_by_price.get(new_price.stripe_price_id) == new_row["stripe_item_id"]

        # Discounts: the old applications stay pinned to the old row as
        # records; the successor carries COPIES of both (same frozen
        # value_ids, fresh rows, coupons re-resolved by the sync).
        old_after = await get_applied_discounts(db_pool, child_item_id)
        assert {str(d["value_id"]) for d in old_after} == old_value_ids
        copies = await get_applied_discounts(db_pool, new_item_id)
        assert {str(d["value_id"]) for d in copies} == old_value_ids
        old_ids = {str(d["applied_discount_id"]) for d in old_after}
        copy_ids = {str(d["applied_discount_id"]) for d in copies}
        assert old_ids.isdisjoint(copy_ids)
        assert all(d["stripe_coupon_id"] is not None for d in copies)

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, payer.member_id)


async def test_same_day_double_reprice(
    memberships_service,
    plans_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Two reprices in one day: each mints a fresh successor row."""
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

        price_v2 = await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id,
                gym_id=gym_id,
                price=8000,
            ),
        )
        second_item_id = await memberships_service.update_price(
            item_id=item_id,
            member_id=member.member_id,
            proration_behavior=ProrationBehavior.no_charge,
        )

        price_v3 = await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id,
                gym_id=gym_id,
                price=9000,
            ),
        )
        third_item_id = await memberships_service.update_price(
            item_id=second_item_id,
            member_id=member.member_id,
            proration_behavior=ProrationBehavior.no_charge,
        )

        second_row = await _get_membership_row(db_pool, second_item_id)
        assert second_row["status"] == "deleted"
        assert UUID(str(second_row["price_id"])) == price_v2.price_id
        third_row = await _get_membership_row(db_pool, third_item_id)
        assert third_row["status"] == "applied"
        assert UUID(str(third_row["price_id"])) == price_v3.price_id
        assert third_row["total_price"] == 9000
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_reprice_to_now_inactive_pinned_price(
    memberships_service,
    plans_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Reprice honors a PINNED target even after it's been deactivated.

    The batch scenario: a user starts an upgrade pinning the then-active
    price, then a newer price is created (deactivating the pinned one).
    Start on v1; create v2 then v3 (so v2 is now inactive); reprice the
    membership to v2 — it must move to v2 (the pinned target), NOT divert to
    the current active v3 and NOT fail.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(gym_id)
    reprice_service = build_memberships_reprice(db_pool, stripe_client)

    try:
        item_id = await _start_and_get_item_id(
            memberships_service, db_pool, member, gym_id, plan,
        )
        profile = await get_profile_stripe_ids(
            db_pool, member.member_id, gym_id,
        )
        v2 = await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id, gym_id=gym_id, price=8000,
            ),
        )
        # v3 becomes active, deactivating v2 (≤1 active price per plan).
        await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id, gym_id=gym_id, price=9000,
            ),
        )
        before = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts,
        )

        new_item_id = await reprice_service.reprice(
            member_id=member.member_id,
            old_item_id=item_id,
            target_price_id=v2.price_id,
            proration_behavior=ProrationBehavior.no_charge,
        )

        old_row = await _get_membership_row(db_pool, item_id)
        assert old_row["status"] == "deleted"
        new_row = await _get_membership_row(db_pool, new_item_id)
        assert UUID(str(new_row["price_id"])) == v2.price_id
        assert new_row["total_price"] == 8000
        assert new_row["status"] == "applied"

        # Stripe carries v2's price (the pinned target), not active v3.
        sub = await fetch_subscription(
            stripe_client, profile.stripe_sub_id_month, connect_opts,
        )
        prices = {i.price.id for i in sub.items.data}
        assert v2.stripe_price_id in prices

        await assert_no_unexpected_charges(
            stripe_client, before, connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_update_cancelled_raises(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Repricing a cancelled membership is rejected (direct → ValueError)."""
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

        # Snapshot after cancel — the rejected reprice below must not
        # create any invoice or mutate any membership row.
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        with pytest.raises(ValueError):
            await memberships_service.update_price(
                item_id=item_id,
                member_id=member.member_id,
            )

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_update_price_noop_unchanged(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Already on the plan's active price → a true no-op.

    ``update_price`` returns the membership's own id, touches nothing, and
    bills nothing even with proration_behavior=prorate_to_anchor (the no-op returns before
    any sync).
    """
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
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        new_item_id = await memberships_service.update_price(
            item_id=item_id,
            member_id=member.member_id,
            proration_behavior=ProrationBehavior.prorate_to_anchor,
        )
        # No-op: the returned id IS the row itself; nothing changed.
        assert new_item_id == item_id
        row = await _get_membership_row(db_pool, item_id)
        assert row["status"] == "applied"
        assert row["cancel_date"] is None

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)
