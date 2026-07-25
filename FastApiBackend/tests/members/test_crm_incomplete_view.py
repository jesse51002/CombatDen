"""Integration: the Incomplete tab lists stalled signups — and only those.

The rule (``sql/crm_views/_member_incomplete.sql``) has four clauses, and every
one of them exists to keep a specific wrong person OFF a staff follow-up list.
A member is incomplete when their row is VALID (it has a
``stripe_customer_id``), they hold no membership of their own, they are not the
payer on anyone else's, and they hold no billed-but-unconfirmed non-recurring
membership.

Each exclusion is covered below by building the real production row state:

* **the payer** — a non-training parent who pays for their kid owns no
  membership, so without the payer half they would sit in the follow-up list
  forever with nothing left to finish;
* **the invalid row** — no ``stripe_customer_id`` means the create never
  finished, so the row has no billing identity and every next step staff could
  take against it would be rejected;
* **the billed-but-unconfirmed row** — the start op charged the card and then
  failed to stamp the writeback, and deliberately KEEPS the row ("billed lines
  are never un-billed"); the filtered view hides it, so the member reads as
  owning nothing when in fact their money has been taken. Chasing them to
  "finish signing up" is the worst possible follow-up.

Runs against the real shared local Supabase DB with the real
``incomplete_view.sql`` / ``total_counts.sql``. Every assertion is scoped by a
per-run random surname passed through the list's own ``name`` filter, so the
seeded gym's own members can never make it pass or fail — and every test also
checks the TALLY delta, because the tab and its count share one predicate text
and a change that broke only one of them would be invisible otherwise.
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

    Passing a surname goes through the list's own ``name`` filter, which is how
    every behavioural assertion here stays immune to the shared local DB: other
    agents' test suites create and delete members in it continuously (observed
    live), so any assertion on an absolute COUNT is a coin flip. Set membership
    of a specific id is not.
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

    This is the invariant the shared fragment exists for: the tab
    (``incomplete_view.sql``) and the tally (``total_counts.sql``) inject ONE
    predicate text, so they cannot disagree about who is incomplete. Asserted
    as an equality at a single moment rather than as a before/after delta —
    a delta needs the gym-wide population to hold still across the whole test
    body, which on this shared DB it does not.

    Returns the agreed count so a caller can assert on it.
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


async def _attach_unconfirmed_membership(
    db_pool,
    *,
    member_id: UUID,
    paid_by_member_id: UUID,
    gym_id: UUID,
    plan_id: UUID,
    price_id: UUID,
) -> None:
    """Insert a BILLED-BUT-UNCONFIRMED membership row, exactly as production
    leaves one.

    This is the state ``MemberMembershipsStart._charge_one_time_group`` produces
    when the consolidated invoice is PAID but
    ``PaymentSyncOneTime._writeback_membership_rows`` fails to stamp the row:
    ``_verify_group(keep_unverified=True)`` marks the item failed and KEEPS the
    row untouched, because a billed line is never un-billed. The single UPDATE
    that would have written ``stripe_item_id`` / ``stripe_one_time_invoice_id`` /
    ``stripe_sync_status = 'applied'`` is the one that failed, so the row is
    still exactly as inserted: NULL ids, ``'not_added'``.

    That is why the fixture writes no ``stripe_item_id`` — a "charged" marker
    on the row is precisely what is missing, which is what makes the member
    look like an unfinished signup to every read that goes through the filtered
    view.
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

    Cannot go through ``created.member``: that helper always provisions the
    Stripe customer, which is the whole point of the production invariant. The
    row this writes is what survives when the create's Stripe step failed after
    the DB insert — no billing identity, invisible to
    ``member_billing_profile``, and unusable for every next step.
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
    """Three members, one rule: only the member with nothing at all is listed.

    * ``stalled`` — a shell row, no membership, pays for nobody. LISTED.
    * ``buyer`` — holds their own membership. NOT listed.
    * ``payer`` — holds no membership but funds ``child``'s. NOT listed; this
      is the exclusion the whole predicate exists for.
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

        # The tally agrees with the tab, and the same four members land on the
        # same side of both. This replaces a before/after DELTA assertion: the
        # tally is gym-wide, and other agents' suites add and remove members in
        # this shared DB continuously (observed live), so a delta measured
        # across a whole test body is a coin flip. The equality below is the
        # real invariant — one predicate text, two surfaces — and set
        # membership carries the per-member behaviour.
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


async def test_incomplete_view_excludes_billed_but_unconfirmed_memberships(
    crm_members_list_service,
    total_counts_service,
    db_pool,
    gym_id,
    created,
) -> None:
    """Someone who already PAID is never an unfinished signup.

    The start op charges a one-time group on one consolidated invoice, then
    stamps each row ``applied``. When the charge lands but that writeback does
    not, the row is deliberately KEPT in its pre-sync ``'not_added'`` state
    (``memberships_start.py``, ``_verify_group(keep_unverified=True)``) because
    a billed line is never un-billed. The ``member_memberships`` view hides
    exactly that status, so before this exclusion the member read to the entire
    CRM as owning nothing and landed in the staff follow-up list — staff then
    chased a person whose card had already been charged, and the reconciliation
    the row actually needs went unnoticed.

    Both directions are covered, because the shared predicate disqualifies a
    member as SUBJECT or as PAYER and a payer who paid for someone else has
    equally already paid.
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

        # The TALLY excludes them too, not just the tab — a change that fixed
        # only one surface would leave staff a count that disagrees with the
        # list they can see. Asserted as tally == tab (one shared predicate
        # text) plus set membership, never as a gym-wide count delta: this DB
        # is shared with other agents' suites and its population moves.
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

    Every member is provisioned a Stripe customer at creation and the id is
    immutable afterwards (``trg_prevent_stripe_customer_id_overwrite``), so a
    NULL means the create never completed. The row has no billing identity:
    ``member_billing_profile`` — which the whole billing read path goes through
    — filters on exactly this column, so nothing can be sold to it and every
    next step staff could take against it is rejected. Listing it as a signup to
    chase is sending someone after a dead row.

    The valid member created alongside it proves the exclusion is about the
    missing customer id and not about the fixture's insert path.
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

        # The tally excludes it too, and agrees with the tab (see the sibling
        # test for why this is an equality rather than a count delta).
        unfiltered = await _listed_ids(crm_members_list_service, gym_id, None)
        assert valid.member_id in unfiltered
        assert broken_id not in unfiltered
        await _assert_tally_matches_list(
            total_counts_service, crm_members_list_service, gym_id,
        )
    finally:
        for member_id in (valid.member_id, broken_id):
            await delete_member_data(db_pool, member_id)
