"""Integration: the Incomplete tab lists stalled signups — and only those.

The rule (``sql/crm_views/_member_incomplete.sql``) is: a member holding NO
membership of their own who is ALSO not the payer on anyone else's. The second
half is the load-bearing one — a non-training parent who pays for their kid owns
no membership, so without it they would sit in the staff follow-up list forever
with nothing left to finish.

Runs against the real shared local Supabase DB with the real
``incomplete_view.sql`` / ``total_counts.sql``. Every assertion is scoped by a
per-run random surname passed through the list's own ``name`` filter, so the
seeded gym's own members can never make it pass or fail.
"""

from __future__ import annotations

from datetime import date
from uuid import UUID, uuid4

from sqlalchemy import text

from src.members.schema.members_crm_members_list_schema import (
    CrmMembersListRequest,
    MembersListFilters,
    MembersListView,
)
from tests.helpers.cleanup import delete_member_data


async def _attach_membership(
    db_pool,
    *,
    member_id: UUID,
    paid_by_member_id: UUID,
    gym_id: UUID,
    plan_id: UUID,
    price_id: UUID,
) -> None:
    """Insert a Stripe-synced membership row directly.

    The view reads ``member_memberships_status`` (the FILTERED view), so the row
    needs a ``stripe_item_id`` and an ``applied`` sync status to be visible.
    Going through the real start op would mean a live Stripe subscription for a
    test that is purely about a SQL predicate.
    """
    async with db_pool.session() as session:
        await session.execute(
            text(
                """
                INSERT INTO member_memberships_unfiltered (
                    member_id, paid_by_member_id, gym_id, plan_id, price_id,
                    start_date, last_paid_date, stripe_item_id, total_price,
                    quantity, stripe_sync_status
                ) VALUES (
                    CAST(:member_id AS UUID),
                    CAST(:paid_by_member_id AS UUID),
                    CAST(:gym_id AS UUID),
                    CAST(:plan_id AS UUID),
                    CAST(:price_id AS UUID),
                    CAST(:start_date AS DATE),
                    CAST(:start_date AS DATE),
                    :stripe_item_id, 5000, 1, 'applied'
                )
                """
            ),
            {
                "member_id": str(member_id),
                "paid_by_member_id": str(paid_by_member_id),
                "gym_id": str(gym_id),
                "plan_id": str(plan_id),
                "price_id": str(price_id),
                "start_date": date.today(),
                "stripe_item_id": f"si_test_{uuid4().hex[:16]}",
            },
        )
        await session.commit()


async def test_incomplete_view_lists_only_unfinished_signups(
    crm_members_list_service,
    total_counts_service,
    db_pool,
    gym_id,
    created,
) -> None:
    """Three members, one rule: only the member with nothing at all is listed.

    * ``stalled`` — a shell row, no membership, pays for nobody. LISTED.
    * ``buyer`` — holds their own membership. NOT listed.
    * ``payer`` — holds no membership but funds ``child``'s. NOT listed; this
      is the exclusion the whole predicate exists for.
    """
    surname = f"Incmpl{uuid4().hex[:8]}"
    # Baseline BEFORE any of this test's members exist — the tally is gym-wide
    # and the seeded gym has its own incomplete members, so only the delta is
    # meaningful.
    counts_before = await total_counts_service.get_total_counts(gym_id)
    plan = await created.plan(gym_id, plan_type="recurring")
    stalled = await created.member(
        gym_id, first_name="Stalled", last_name=surname,
    )
    buyer = await created.member(
        gym_id, first_name="Buyer", last_name=surname,
    )
    payer = await created.member(
        gym_id, first_name="Payer", last_name=surname,
    )
    child = await created.member(
        gym_id, first_name="Child", last_name=surname,
    )

    try:
        await _attach_membership(
            db_pool,
            member_id=buyer.member_id,
            paid_by_member_id=buyer.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )
        await _attach_membership(
            db_pool,
            member_id=child.member_id,
            paid_by_member_id=payer.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )

        response = await crm_members_list_service.get_crm_members_list(
            CrmMembersListRequest(
                gym_id=gym_id,
                view=MembersListView.incomplete,
                filters=MembersListFilters(name=surname),
                count=50,
            ),
        )
        listed = {row.member_id for row in response.data}

        assert stalled.member_id in listed, (
            "a member with no membership and no payee is an unfinished signup"
        )
        assert buyer.member_id not in listed, (
            "a member holding their own membership finished signing up"
        )
        assert payer.member_id not in listed, (
            "a non-training payer has nothing left to finish — listing them "
            "would strand them in the follow-up list forever"
        )
        assert child.member_id not in listed, (
            "the payee holds a membership, so their signup is complete"
        )
        assert listed == {stalled.member_id}

        # The row carries what staff need to chase the signup.
        row = next(r for r in response.data if r.member_id == stalled.member_id)
        assert row.view == MembersListView.incomplete
        assert row.name == f"Stalled {surname}"
        assert row.days_waiting == 0  # created moments ago, gym-local

        # The tally moves with the list: of the four members this test added,
        # exactly ONE counts as incomplete — the same predicate, so the badge
        # count and the tab can never disagree.
        counts_after = await total_counts_service.get_total_counts(gym_id)
        assert counts_after.incomplete - counts_before.incomplete == 1
    finally:
        # FK order: child's membership names payer as paid_by_member_id
        # (fk_membership_payer), so the payee's rows must go first.
        for member in (stalled, buyer, child, payer):
            await delete_member_data(db_pool, member.member_id)


async def test_incomplete_view_excludes_lapsed_members(
    crm_members_list_service,
    db_pool,
    gym_id,
    created,
) -> None:
    """A member whose only membership is CANCELLED is lapsed, not unfinished.

    Deliberate: the tab is for signups that never completed. Re-listing every
    churned member here would bury the real ones.
    """
    surname = f"Lapsed{uuid4().hex[:8]}"
    plan = await created.plan(gym_id, plan_type="recurring")
    lapsed = await created.member(
        gym_id, first_name="Lapsed", last_name=surname,
    )

    try:
        await _attach_membership(
            db_pool,
            member_id=lapsed.member_id,
            paid_by_member_id=lapsed.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )
        async with db_pool.session() as session:
            await session.execute(
                text(
                    "UPDATE member_memberships_unfiltered "
                    "SET cancel_date = CAST(:today AS DATE) "
                    "WHERE member_id = CAST(:member_id AS UUID)"
                ),
                {
                    "today": date.today(),
                    "member_id": str(lapsed.member_id),
                },
            )
            await session.commit()

        response = await crm_members_list_service.get_crm_members_list(
            CrmMembersListRequest(
                gym_id=gym_id,
                view=MembersListView.incomplete,
                filters=MembersListFilters(name=surname),
                count=50,
            ),
        )

        assert response.data == []
    finally:
        await delete_member_data(db_pool, lapsed.member_id)
