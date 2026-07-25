"""Integration: the Incomplete tab lists stalled signups — and only those.

A member is incomplete when their row is VALID (has a ``stripe_customer_id``),
they hold no membership of their own, they are not the payer on anyone else's,
and they hold no billed-but-unconfirmed non-recurring membership. Each of those
four clauses of ``sql/crm_views/_member_incomplete.sql`` keeps a specific wrong
person OFF a staff follow-up list — most sharply the last, where the card was
already charged and "finish signing up" is the worst possible advice.

Runs the real ``incomplete_view.sql`` / ``total_counts.sql`` against the shared
local Supabase DB, whose population moves under other suites — so every
assertion is scoped by a per-run random surname through the list's own ``name``
filter, and every test also checks the tally, because tab and count share one
predicate text.
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

# High enough to hold every incomplete row the seeded gym has, so the
# tally-vs-list check below compares complete sets rather than one page.
_UNPAGINATED = 500


async def _listed_ids(service, gym_id: UUID, surname: str | None) -> set[UUID]:
    """The Incomplete tab's member ids, optionally scoped by surname.

    The surname goes through the list's own ``name`` filter — other suites add
    and remove members in this shared DB continuously, so an absolute COUNT is a
    coin flip while set membership of a specific id is not.
    """
    response = await service.get_crm_members_list(
        CrmMembersListRequest(
            gym_id=gym_id,
            view=MembersListView.incomplete,
            filters=(
                MembersListFilters(name=surname)
                if surname is not None
                else MembersListFilters()
            ),
            count=_UNPAGINATED,
        ),
    )
    return {row.member_id for row in response.data}


async def _assert_tally_matches_list(
    counts_service, list_service, gym_id: UUID
) -> int:
    """Assert the subtitle tally equals the Incomplete tab's row count.

    The invariant the shared fragment exists for: tab and tally inject ONE
    predicate text, so they cannot disagree. An equality at a single moment, not
    a before/after delta — a delta needs the gym-wide population to hold still,
    which on this shared DB it does not. Returns the agreed count.
    """
    tally = (await counts_service.get_total_counts(gym_id)).incomplete
    listed = await _listed_ids(list_service, gym_id, None)
    assert tally == len(listed), (
        f"the Incomplete tally ({tally}) and its tab ({len(listed)}) disagree "
        "— they share one predicate text, so this means the fragment was "
        "forked or one surface stopped injecting it"
    )
    return tally


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

    The view reads the FILTERED ``member_memberships_status``, so the row needs
    a ``stripe_item_id`` and an ``applied`` sync status to be visible. The real
    start op would mean a live Stripe subscription for a pure SQL-predicate test.
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


async def _attach_unconfirmed_membership(
    db_pool,
    *,
    member_id: UUID,
    paid_by_member_id: UUID,
    gym_id: UUID,
    plan_id: UUID,
    price_id: UUID,
) -> None:
    """Insert a BILLED-BUT-UNCONFIRMED membership row, as production leaves one.

    The consolidated invoice is PAID but the writeback that would stamp
    ``stripe_item_id`` / ``'applied'`` failed, and ``_verify_group
    (keep_unverified=True)`` KEEPS the row untouched — a billed line is never
    un-billed. So the row stays as inserted (NULL ids, ``'not_added'``): the
    "charged" marker is exactly what is missing, which is what makes the member
    look like an unfinished signup to every read through the filtered view.
    """
    async with db_pool.session() as session:
        await session.execute(
            text(
                """
                INSERT INTO member_memberships_unfiltered (
                    member_id, paid_by_member_id, gym_id, plan_id, price_id,
                    start_date, total_price, quantity, stripe_sync_status,
                    idempotency_key
                ) VALUES (
                    CAST(:member_id AS UUID),
                    CAST(:paid_by_member_id AS UUID),
                    CAST(:gym_id AS UUID),
                    CAST(:plan_id AS UUID),
                    CAST(:price_id AS UUID),
                    CAST(:start_date AS DATE),
                    5000, 1, 'not_added',
                    CAST(:idempotency_key AS UUID)
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
                "idempotency_key": str(uuid4()),
            },
        )
        await session.commit()


async def _insert_member_without_stripe_customer(
    db_pool,
    *,
    gym_id: UUID,
    first_name: str,
    last_name: str,
) -> UUID:
    """Insert a members row with NO ``stripe_customer_id`` — a failed create.

    ``created.member`` always provisions the Stripe customer (that is the
    invariant), so the invalid row has to be written directly: no billing
    identity, invisible to ``member_billing_profile``, unusable for every next
    step.
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                """
                INSERT INTO members (gym_id, first_name, last_name)
                VALUES (CAST(:gym_id AS UUID), :first_name, :last_name)
                RETURNING member_id
                """
            ),
            {
                "gym_id": str(gym_id),
                "first_name": first_name,
                "last_name": last_name,
            },
        )
        member_id = UUID(str(result.mappings().one()["member_id"]))
        await session.commit()
    return member_id


async def test_incomplete_view_lists_only_unfinished_signups(
    crm_members_list_service,
    total_counts_service,
    db_pool,
    gym_id,
    created,
) -> None:
    """Only the member with nothing at all is listed.

    ``stalled`` (a shell row) is LISTED; ``buyer`` (own membership) is not; and
    ``payer`` — no membership, but funds ``child``'s — is not, the exclusion the
    payer half of the predicate exists for.
    """
    surname = f"Incmpl{uuid4().hex[:8]}"
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

        # Tally == tab (one predicate text, two surfaces) plus set membership
        # for the per-member behaviour. Never a gym-wide count delta: this DB is
        # shared and its population moves mid-test.
        unfiltered = await _listed_ids(crm_members_list_service, gym_id, None)
        assert stalled.member_id in unfiltered
        for excluded in (buyer, payer, child):
            assert excluded.member_id not in unfiltered
        await _assert_tally_matches_list(
            total_counts_service, crm_members_list_service, gym_id,
        )
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
    """A member whose only membership is CANCELLED is lapsed, not unfinished —
    re-listing every churned member here would bury the real ones."""
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


async def test_incomplete_view_excludes_billed_but_unconfirmed_memberships(
    crm_members_list_service,
    total_counts_service,
    db_pool,
    gym_id,
    created,
) -> None:
    """Someone who already PAID is never an unfinished signup.

    A charged one-time row whose writeback failed is deliberately kept
    ``'not_added'`` (a billed line is never un-billed) and the
    ``member_memberships`` view hides exactly that status — so without this
    exclusion the member reads as owning nothing and staff chase someone whose
    card was already charged. Both directions covered: the predicate
    disqualifies a member as SUBJECT or as PAYER.
    """
    surname = f"Unconf{uuid4().hex[:8]}"
    pack = await created.plan(gym_id, plan_type="one_time")
    buyer = await created.member(gym_id, first_name="Buyer", last_name=surname)
    payer = await created.member(gym_id, first_name="Payer", last_name=surname)
    child = await created.member(gym_id, first_name="Child", last_name=surname)
    control = await created.member(
        gym_id, first_name="Control", last_name=surname,
    )

    try:
        # Bought their own pack; the charge went through, the writeback did not.
        await _attach_unconfirmed_membership(
            db_pool,
            member_id=buyer.member_id,
            paid_by_member_id=buyer.member_id,
            gym_id=gym_id,
            plan_id=pack.plan_id,
            price_id=pack.price_id,
        )
        # Paid for their kid's pack; same failure.
        await _attach_unconfirmed_membership(
            db_pool,
            member_id=child.member_id,
            paid_by_member_id=payer.member_id,
            gym_id=gym_id,
            plan_id=pack.plan_id,
            price_id=pack.price_id,
        )

        listed = await _listed_ids(crm_members_list_service, gym_id, surname)

        assert buyer.member_id not in listed, (
            "the buyer's card was charged — they need reconciliation, not a "
            "signup follow-up"
        )
        assert payer.member_id not in listed, (
            "the payer's card was charged for their kid's pack; same thing "
            "from the payer side"
        )
        assert child.member_id not in listed, (
            "the child's pack is billed, so their signup is not unfinished"
        )
        assert listed == {control.member_id}, (
            "only the member with genuinely nothing on file is listed"
        )

        # The TALLY excludes them too, not just the tab — a fix to one surface
        # alone would leave staff a count that disagrees with the list.
        unfiltered = await _listed_ids(crm_members_list_service, gym_id, None)
        assert control.member_id in unfiltered
        for excluded in (buyer, payer, child):
            assert excluded.member_id not in unfiltered
        await _assert_tally_matches_list(
            total_counts_service, crm_members_list_service, gym_id,
        )
    finally:
        # FK order: the child's row names payer as paid_by_member_id, so the
        # payee goes before the payer.
        for member in (control, buyer, child, payer):
            await delete_member_data(db_pool, member.member_id)


async def test_incomplete_view_excludes_members_with_no_stripe_customer(
    crm_members_list_service,
    total_counts_service,
    db_pool,
    gym_id,
    created,
) -> None:
    """A row with no ``stripe_customer_id`` is INVALID and shown nowhere.

    The id is provisioned at creation and immutable after
    (``trg_prevent_stripe_customer_id_overwrite``), so NULL means the create
    never completed: ``member_billing_profile`` filters on exactly this column,
    so nothing can be sold to the row and every next step is rejected. The valid
    member alongside proves the exclusion is about the missing id, not the
    fixture's insert path.
    """
    surname = f"NoCust{uuid4().hex[:8]}"
    valid = await created.member(gym_id, first_name="Valid", last_name=surname)
    broken_id = await _insert_member_without_stripe_customer(
        db_pool, gym_id=gym_id, first_name="Broken", last_name=surname,
    )

    try:
        listed = await _listed_ids(crm_members_list_service, gym_id, surname)

        assert broken_id not in listed, (
            "a member with no stripe_customer_id is an invalid row, not an "
            "unfinished signup"
        )
        assert valid.member_id in listed, (
            "the valid shell member IS an unfinished signup — the exclusion "
            "must be about the missing customer id, nothing else"
        )
        assert listed == {valid.member_id}

        # The tally excludes it too, and agrees with the tab.
        unfiltered = await _listed_ids(crm_members_list_service, gym_id, None)
        assert valid.member_id in unfiltered
        assert broken_id not in unfiltered
        await _assert_tally_matches_list(
            total_counts_service, crm_members_list_service, gym_id,
        )
    finally:
        for member_id in (valid.member_id, broken_id):
            await delete_member_data(db_pool, member_id)
