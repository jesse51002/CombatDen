"""Integration: the unified list-based start across a linked family.

These exercise ``MemberMembershipsStart.start`` through the public
``memberships_service.start`` facade with MULTI-member / MULTI-group carts —
the real reason the op is list-based:

  * a 3-member recurring family converged onto ONE subscription in ONE charge,
    each line keeping its discount (distinct lines exact, a shared price blended);
  * a mixed one-time + recurring cart producing exactly TWO charges (one
    consolidated one-time invoice + one recurring converge);
  * the Phase-A validation gate (every branch rejects with nothing written);
  * a mixed cart whose recurring card declines — the at-the-desk charge is now
    verified synchronously (``error_if_incomplete`` on the card path), so the
    recurring group ``failed`` (its pending rows cleaned, no subscription left)
    while the $0 one-time group still bills;
  * the single-member decline, the cash-path regression (a declining card still
    succeeds out of band), and adding to an EXISTING healthy sub when the card
    now declines (the add fails + reverts, the live sub untouched).

Every test cleans up exactly what it creates via the ``created`` fixture plus an
explicit ``delete_member_data`` in a ``finally`` (linked children need the
membership/applied-discount rows gone before the member rows, and the link
self-FK cleared — ``delete_member_data`` handles both per member).
"""

from uuid import uuid4

import pytest
from pydantic import ValidationError
from schema.task import ProrationBehavior
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.discounts.schema.discounts_schema import DiscountValue
from src.memberships import SQL_DIR
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from src.shared.sql_loader import load_sql
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import (
    get_applied_discounts,
    get_profile_stripe_ids,
)
from tests.helpers.stripe_assertions import fetch_subscription

# The single seeded gym is America/Chicago (tests/seed_constants.py).
_SEEDED_GYM_TZ = "America/Chicago"


async def _link_child(db_pool, child_id, parent_id) -> None:
    """Link a child to the payer via the production link SQL (NULLs the
    child's own card/sub so it rides the payer's invoice)."""
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


async def _read_membership_row(db_pool, item_id) -> dict:
    """Read one membership row from the unfiltered base by item_id."""
    sql = """
        SELECT item_id, member_id, plan_id,
               stripe_item_id, stripe_one_time_invoice_id,
               stripe_sync_status::text AS status, total_price
        FROM member_memberships_unfiltered
        WHERE item_id = :item_id
    """
    async with db_pool.session() as session:
        result = await session.execute(text(sql), {"item_id": str(item_id)})
        return dict(result.mappings().one())


async def _count_membership_rows(db_pool, member_id) -> int:
    """Count ALL membership rows (any status) for a member — the
    nothing-was-written assertion for the Phase-A rejection tests."""
    sql = (
        "SELECT count(*) AS n FROM member_memberships_unfiltered "
        "WHERE member_id = :member_id"
    )
    async with db_pool.session() as session:
        result = await session.execute(text(sql), {"member_id": str(member_id)})
        return int(result.mappings().one()["n"])


# ── Test 1 — 3-member recurring family, ONE converge, per-line discounts ──


@pytest.mark.timeout(240)
async def test_recurring_family_one_converge_per_line_discounts(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Payer + 2 linked children, all recurring, in ONE request.

    Two children share one price; the payer is on a different, cheaper price —
    proving the converge both consolidates the shared price (quantity 2) AND
    keeps a separate line for the payer's price, with each membership carrying
    its discount. Ongoing discounts are used (not once) because a not-yet-synced
    membership's once is excluded from the immediate per-line figure — ongoing
    always counts, so each ``total_price`` writeback reflects its discount at
    start.

    Discount choice is deliberate: the payer gets a DISTINCT 10% on its own
    (qty-1) line, so it keeps its exact ``pct_1000_ongoing`` coupon. The two
    children share a price AND the SAME 20% discount — a Stripe sub item with
    quantity 2 can carry only one coupon set, so per-member discounts on a
    shared price are blended into ONE line coupon
    (``line_percent = Σ effᵢ / qty``). Giving both children the same 20% keeps
    that blend equal to 20% (``(0.20 + 0.20) / 2 = 0.20``) so the shared line's
    coupon is unambiguously ``pct_2000_ongoing`` and both per-member writebacks
    are 4000 — proving the consolidation cleanly rather than asserting a
    confusing averaged coupon.
    """
    pm_id = await created.payment_method()
    payer = await created.member(
        gym_id, first_name="Payer", last_name="Fam1", payment_method_id=pm_id
    )
    child_a = await created.member(gym_id, first_name="ChildA", last_name="Fam1")
    child_b = await created.member(gym_id, first_name="ChildB", last_name="Fam1")

    # Payer on a $40 plan; both children share a single $50 plan/price.
    payer_plan = await created.plan(
        gym_id, plan_name="Adult Recurring", price_cents=4000
    )
    shared_plan = await created.plan(
        gym_id, plan_name="Kids Recurring", price_cents=5000
    )

    disc_payer = await created.discount(
        gym_id, name="Fam payer 10% ongoing", percentage_off=10.0,
        discount_mode="ongoing",
    )
    # Both children share the same 20% so the consolidated qty-2 line's blended
    # coupon is unambiguously 20% (not an averaged-across-distinct-discounts id).
    disc_kid_a = await created.discount(
        gym_id, name="Fam kid A 20% ongoing", percentage_off=20.0,
        discount_mode="ongoing",
    )
    disc_kid_b = await created.discount(
        gym_id, name="Fam kid B 20% ongoing", percentage_off=20.0,
        discount_mode="ongoing",
    )

    try:
        await _link_child(db_pool, child_a.member_id, payer.member_id)
        await _link_child(db_pool, child_b.member_id, payer.member_id)

        response = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=payer.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=payer.member_id,
                        price_id=payer_plan.price_id,
                        discount_ids=[disc_payer.discount_id],
                    ),
                    MemberMembershipsStartItem(
                        member_id=child_a.member_id,
                        price_id=shared_plan.price_id,
                        discount_ids=[disc_kid_a.discount_id],
                    ),
                    MemberMembershipsStartItem(
                        member_id=child_b.member_id,
                        price_id=shared_plan.price_id,
                        discount_ids=[disc_kid_b.discount_id],
                    ),
                ],
            )
        )

        # One recurring converge, no one-time → exactly one charge.
        assert response.charge_count == 1
        assert response.multiple_charges is False
        assert [r.status.value for r in response.results] == [
            "created", "created", "created",
        ]

        by_member = {r.member_id: r for r in response.results}
        # Every membership row landed `applied` with a real sub-item line id,
        # at its post-discount price, and NO one-time invoice id (recurring).
        expected_price = {
            payer.member_id: 3600,    # 4000 - 10%
            child_a.member_id: 4000,  # 5000 - 20%
            child_b.member_id: 4000,  # 5000 - 20%
        }
        for member_id, result_item in by_member.items():
            row = await _read_membership_row(db_pool, result_item.item_id)
            assert row["status"] == "applied"
            assert row["stripe_item_id"] is not None
            assert row["stripe_item_id"].startswith("si_")
            assert row["stripe_one_time_invoice_id"] is None
            assert row["total_price"] == expected_price[member_id]

            # Each membership's applied-discount row got its coupon written back.
            snaps = await get_applied_discounts(db_pool, result_item.item_id)
            assert len(snaps) == 1
            assert snaps[0]["stripe_coupon_id"] is not None

        # Coupons are the deterministic per-value ids (pct_<bps>_<mode>). The
        # payer's distinct qty-1 line keeps its exact 10%; the two children's
        # consolidated qty-2 line carries the blended 20% (both contributed 20%
        # → (0.20 + 0.20) / 2 = 0.20), so both children's applied-discount rows
        # are written back to the SAME shared-line coupon.
        payer_snaps = await get_applied_discounts(
            db_pool, by_member[payer.member_id].item_id
        )
        a_snaps = await get_applied_discounts(
            db_pool, by_member[child_a.member_id].item_id
        )
        b_snaps = await get_applied_discounts(
            db_pool, by_member[child_b.member_id].item_id
        )
        assert payer_snaps[0]["stripe_coupon_id"] == "pct_1000_ongoing"
        assert a_snaps[0]["stripe_coupon_id"] == "pct_2000_ongoing"
        assert b_snaps[0]["stripe_coupon_id"] == "pct_2000_ongoing"
        created.track_coupon("pct_1000_ongoing")
        created.track_coupon("pct_2000_ongoing")

        # The payer's single family subscription carries the expected items:
        # one line on the payer's price (qty 1) + ONE consolidated line on the
        # shared kids' price (qty 2, two memberships).
        profile = await get_profile_stripe_ids(
            db_pool, payer.member_id, gym_id
        )
        assert profile.stripe_sub_id_month is not None
        sub = await fetch_subscription(
            stripe_client, profile.stripe_sub_id_month, connect_opts
        )
        qty_by_price = {
            item.price.id: item.quantity for item in sub.items.data
        }
        assert qty_by_price.get(payer_plan.stripe_price_id) == 1
        assert qty_by_price.get(shared_plan.stripe_price_id) == 2
    finally:
        await delete_member_data(db_pool, child_a.member_id)
        await delete_member_data(db_pool, child_b.member_id)
        await delete_member_data(db_pool, payer.member_id)


# ── Test 2 — mixed one-time + recurring in ONE request → TWO charges ──


@pytest.mark.timeout(240)
async def test_mixed_one_time_and_recurring_two_charges(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A single member buys a one-time pass + a recurring plan in one request.

    Two charge groups → ``charge_count == 2`` / ``multiple_charges is True``.
    The one-time row lands on a consolidated invoice (``in_…``) with its own
    line id; the recurring row lands on the family subscription. Both carry an
    ongoing discount so each post-discount price is asserted.
    """
    pm_id = await created.payment_method()
    member = await created.member(
        gym_id, first_name="Mixed", last_name="Cart", payment_method_id=pm_id
    )
    one_time_plan = await created.plan(
        gym_id, plan_type="one_time", plan_name="Day Pass",
        price_cents=3000, duration_amount=1, duration_unit="month",
    )
    recurring_plan = await created.plan(
        gym_id, plan_name="Monthly", price_cents=5000
    )
    ot_disc = await created.discount(
        gym_id, name="Mixed 10% once", percentage_off=10.0,
        discount_mode="once",
    )
    rec_disc = await created.discount(
        gym_id, name="Mixed 20% ongoing", percentage_off=20.0,
        discount_mode="ongoing",
    )

    try:
        response = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=one_time_plan.price_id,
                        discount_ids=[ot_disc.discount_id],
                    ),
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=recurring_plan.price_id,
                        discount_ids=[rec_disc.discount_id],
                    ),
                ],
            )
        )

        # One one-time + one recurring → two charges.
        assert response.charge_count == 2
        assert response.multiple_charges is True
        assert all(r.status.value == "created" for r in response.results)

        by_plan = {r.plan_id: r for r in response.results}
        ot_result = by_plan[one_time_plan.plan_id]
        rec_result = by_plan[recurring_plan.plan_id]

        # The one-time row: consolidated invoice id (in_…) + its own line id,
        # discounted 3000 - 10% = 2700.
        ot_row = await _read_membership_row(db_pool, ot_result.item_id)
        assert ot_row["status"] == "applied"
        assert ot_row["stripe_one_time_invoice_id"] is not None
        assert ot_row["stripe_one_time_invoice_id"].startswith("in_")
        assert ot_row["stripe_item_id"] is not None
        assert ot_row["stripe_item_id"] != ot_row["stripe_one_time_invoice_id"]
        assert ot_row["total_price"] == 2700

        # The recurring row: on the subscription (si_… line), NO one-time
        # invoice id, discounted 5000 - 20% = 4000.
        rec_row = await _read_membership_row(db_pool, rec_result.item_id)
        assert rec_row["status"] == "applied"
        assert rec_row["stripe_item_id"] is not None
        assert rec_row["stripe_item_id"].startswith("si_")
        assert rec_row["stripe_one_time_invoice_id"] is None
        assert rec_row["total_price"] == 4000

        # Both applied-discount rows got their coupons written back.
        for result_item in (ot_result, rec_result):
            snaps = await get_applied_discounts(db_pool, result_item.item_id)
            assert len(snaps) == 1
            assert snaps[0]["stripe_coupon_id"] is not None
            created.track_coupon(snaps[0]["stripe_coupon_id"])

        # The one-time invoice actually paid at the discounted amount.
        invoice = await stripe_client.client.v1.invoices.retrieve_async(
            ot_row["stripe_one_time_invoice_id"], options=connect_opts
        )
        assert invoice.status == "paid"
        assert invoice.amount_paid == 2700

        # The recurring sub carries the recurring plan's price.
        profile = await get_profile_stripe_ids(
            db_pool, member.member_id, gym_id
        )
        assert profile.stripe_sub_id_month is not None
        sub = await fetch_subscription(
            stripe_client, profile.stripe_sub_id_month, connect_opts
        )
        prices = {item.price.id for item in sub.items.data}
        assert recurring_plan.stripe_price_id in prices
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Test 3 — Phase-A validation gate (each rejects, nothing written) ──


async def test_phase_a_payer_frozen_rejects(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """3a: a frozen payer is rejected before anything is written.

    The freeze window is written directly to ``members`` (the simplest way to
    make ``PayerProfile.is_frozen`` true at validation time, with no live
    subscription needed). ``_resolve_payer`` raises and no membership row lands.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(gym_id)

    try:
        async with db_pool.session() as session:
            await session.execute(
                text(
                    "UPDATE members SET "
                    "freeze_start_date = CURRENT_DATE - 1, "
                    "freeze_end_date = CURRENT_DATE + 30 "
                    "WHERE member_id = :id"
                ),
                {"id": str(member.member_id)},
            )
            await session.commit()

        with pytest.raises(ValueError, match="frozen"):
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

        assert await _count_membership_rows(db_pool, member.member_id) == 0
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_phase_a_linked_child_self_pays_own_membership(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """3b: a linked child CAN be the payer of their own membership.

    Self-pay: the payer is the membership's own member, billed on their OWN
    Stripe customer + subscription. The parent's billing is untouched — the
    link is the authorization layer only, never the billing key.
    """
    parent_pm = await created.payment_method()
    parent = await created.member(
        gym_id, first_name="Top", last_name="Level", payment_method_id=parent_pm
    )
    child_pm = await created.payment_method()
    linked_child = await created.member(
        gym_id, first_name="Linked", last_name="Child", payment_method_id=child_pm
    )
    plan = await created.plan(gym_id)

    try:
        await _link_child(db_pool, linked_child.member_id, parent.member_id)

        result = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=linked_child.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=linked_child.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )
        assert all(
            r.status.value == "created" for r in result.results
        ), result

        # The CHILD's own subscription bills it; the parent has none.
        child_profile = await get_profile_stripe_ids(
            db_pool, linked_child.member_id, gym_id
        )
        parent_profile = await get_profile_stripe_ids(
            db_pool, parent.member_id, gym_id
        )
        assert child_profile.stripe_sub_id_month is not None
        assert parent_profile.stripe_sub_id_month is None
        assert await _count_membership_rows(db_pool, linked_child.member_id) == 1
        assert await _count_membership_rows(db_pool, parent.member_id) == 0
    finally:
        await delete_member_data(db_pool, linked_child.member_id)
        await delete_member_data(db_pool, parent.member_id)


async def test_phase_a_member_unlinked_rejects(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """3c: an item whose member is NOT linked to the payer is rejected.

    The start op never links — a bare (unlinked) non-payer member trips the
    "link them first" guard. Nothing is written.
    """
    pm_id = await created.payment_method()
    payer = await created.member(
        gym_id, first_name="Payer", last_name="Unlinked", payment_method_id=pm_id
    )
    stranger = await created.member(gym_id, first_name="Not", last_name="Linked")
    plan = await created.plan(gym_id)

    try:
        with pytest.raises(ValueError, match="link them first"):
            await memberships_service.start(
                MemberMembershipsStartRequest(
                    payer_member_id=payer.member_id,
                    gym_id=gym_id,
                    idempotency_key=uuid4(),
                    memberships=[
                        MemberMembershipsStartItem(
                            member_id=stranger.member_id,
                            price_id=plan.price_id,
                        ),
                    ],
                )
            )

        assert await _count_membership_rows(db_pool, stranger.member_id) == 0
        assert await _count_membership_rows(db_pool, payer.member_id) == 0
    finally:
        await delete_member_data(db_pool, stranger.member_id)
        await delete_member_data(db_pool, payer.member_id)


async def test_phase_a_member_linked_to_other_payer_rejects(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """3d: an item's member linked to a DIFFERENT payer is rejected.

    The child is linked to ``other_payer`` but the request's payer is
    ``payer`` → the "linked to a different paying account" guard fires.
    Nothing is written for any of the three members.
    """
    pm_a = await created.payment_method()
    pm_b = await created.payment_method()
    payer = await created.member(
        gym_id, first_name="Payer", last_name="A", payment_method_id=pm_a
    )
    other_payer = await created.member(
        gym_id, first_name="Other", last_name="Payer", payment_method_id=pm_b
    )
    child = await created.member(gym_id, first_name="Cross", last_name="Linked")
    plan = await created.plan(gym_id)

    try:
        await _link_child(db_pool, child.member_id, other_payer.member_id)

        with pytest.raises(ValueError, match="different paying"):
            await memberships_service.start(
                MemberMembershipsStartRequest(
                    payer_member_id=payer.member_id,
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

        assert await _count_membership_rows(db_pool, child.member_id) == 0
        assert await _count_membership_rows(db_pool, payer.member_id) == 0
        assert await _count_membership_rows(db_pool, other_payer.member_id) == 0
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, payer.member_id)
        await delete_member_data(db_pool, other_payer.member_id)


@pytest.mark.timeout(180)
async def test_phase_a_custom_discount_by_id_rejects(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """3e: passing a `custom` discount id in ``discount_ids`` is rejected.

    Customs are single-use inline values (``custom_discounts``); referencing an
    existing custom by id is always rejected by ``_check_discounts``. We mint a
    real custom by starting a one-time membership with an inline custom on a
    SEPARATE member, then reuse that custom's discount id in a second start —
    which must raise and write nothing for the second member.
    """
    pm_a = await created.payment_method()
    pm_b = await created.payment_method()
    minter = await created.member(
        gym_id, first_name="Custom", last_name="Minter", payment_method_id=pm_a
    )
    victim = await created.member(
        gym_id, first_name="Reuse", last_name="Victim", payment_method_id=pm_b
    )
    plan = await created.plan(
        gym_id, plan_type="one_time", price_cents=5000,
        duration_amount=1, duration_unit="month",
    )

    try:
        # Mint a custom by applying it inline on the minter's one-time start.
        mint_resp = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=minter.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=minter.member_id,
                        price_id=plan.price_id,
                        custom_discounts=[
                            DiscountValue(
                                percentage_off=15.0, discount_mode="once"
                            ),
                        ],
                    ),
                ],
            )
        )
        minter_item = mint_resp.results[0].item_id
        minted_snaps = await get_applied_discounts(db_pool, minter_item)
        assert len(minted_snaps) == 1
        custom_discount_id = minted_snaps[0]["discount_id"]
        created.track_discount(custom_discount_id)
        if minted_snaps[0]["stripe_coupon_id"]:
            created.track_coupon(minted_snaps[0]["stripe_coupon_id"])

        # Reuse that custom id by reference in a second start → rejected.
        with pytest.raises(ValueError, match="custom"):
            await memberships_service.start(
                MemberMembershipsStartRequest(
                    payer_member_id=victim.member_id,
                    gym_id=gym_id,
                    idempotency_key=uuid4(),
                    memberships=[
                        MemberMembershipsStartItem(
                            member_id=victim.member_id,
                            price_id=plan.price_id,
                            discount_ids=[custom_discount_id],
                        ),
                    ],
                )
            )

        assert await _count_membership_rows(db_pool, victim.member_id) == 0
    finally:
        await delete_member_data(db_pool, minter.member_id)
        await delete_member_data(db_pool, victim.member_id)


def test_request_rejects_duplicate_member_price_pairs(gym_id):
    """3f: duplicate (member_id, price_id) items are REJECTED at construction.

    Buying N of the same pack is ONE item with quantity = N, never N duplicate
    items. (Two DIFFERENT prices of the same plan stay distinct items; the
    recurring "one per plan in one request" guard lives in
    MemberMembershipsStartValidation, where plan types are known — see
    tests/memberships/test_start_request_schema.py.)
    """
    member_id = uuid4()
    price_id = uuid4()
    with pytest.raises(ValidationError):
        MemberMembershipsStartRequest(
            payer_member_id=member_id,
            gym_id=gym_id,
            idempotency_key=uuid4(),
            memberships=[
                MemberMembershipsStartItem(
                    member_id=member_id, price_id=price_id,
                ),
                MemberMembershipsStartItem(
                    member_id=member_id, price_id=price_id,
                ),
            ],
        )


# ── Helper: stand a member up on a good card, then swap to a failing one ──


async def _swap_to_failing_card(stripe_client, connect_opts, customer_id):
    """Attach ``tok_chargeCustomerFail`` and make it the default PM.

    ``tok_chargeDeclined`` declines even on attach (so creating a customer with
    it as the default PM blows up). The pattern is: stand the member up with a
    good card, then swap the customer's default to this one — it attaches
    cleanly but fails every charge. (Test PMs are never cleaned up, so nothing
    extra to track.)
    """
    failing_pm = await stripe_client.client.v1.payment_methods.create_async(
        params={"type": "card", "card": {"token": "tok_chargeCustomerFail"}},
        options=connect_opts,
    )
    await stripe_client.client.v1.payment_methods.attach_async(
        failing_pm.id,
        params={"customer": customer_id},
        options=connect_opts,
    )
    await stripe_client.client.v1.customers.update_async(
        customer_id,
        params={"invoice_settings": {"default_payment_method": failing_pm.id}},
        options=connect_opts,
    )


# ── Test 4 — mixed cart, declining card FAILS the recurring group ──


@pytest.mark.timeout(240)
async def test_mixed_cart_recurring_card_fails_at_billing(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A declining card FAILS the recurring group — never reports success.

    Setup: payer with a $0 one-time membership + a paid recurring membership in
    ONE request (``proration_behavior=prorate_to_anchor``, NOT cash). The payer's card-on-file is
    ``tok_chargeCustomerFail`` (attaches cleanly, fails every charge).

    With ``payment_behavior='error_if_incomplete'`` on the card create path,
    Stripe 402s the subscription create when the first invoice can't be paid and
    leaves NO subscription behind. So:
      * ``charge_count == 2`` / ``multiple_charges is True`` — both groups run.
      * The $0 one-time group settles: result ``created``, invoice ``in_…``
        finalized + paid ($0), row ``applied`` — a successful charge is never
        un-billed even though its sibling group fails.
      * The recurring group ``failed`` with the decline error text; its pending
        membership row is cleaned up (gone from the unfiltered base); and there
        is NO subscription left on the customer and no ``stripe_sub_id_month``.

    The empirically-verified Stripe behavior the assertions below pin: a
    declined ``error_if_incomplete`` create produces zero subscriptions and zero
    invoices on the customer (the create is rolled back whole).
    """
    good_pm = await created.payment_method()
    payer = await created.member(
        gym_id,
        first_name="Decline",
        last_name="Payer",
        payment_method_id=good_pm,
    )
    await _swap_to_failing_card(
        stripe_client, connect_opts, payer.stripe_customer_id
    )
    free_plan = await created.plan(
        gym_id, plan_type="one_time", plan_name="Free Pass",
        price_cents=0, duration_amount=1, duration_unit="month",
    )
    paid_recurring = await created.plan(
        gym_id, plan_name="Paid Monthly", price_cents=5000
    )

    try:
        response = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=payer.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                paid_with_cash=False,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=payer.member_id,
                        price_id=free_plan.price_id,
                    ),
                    MemberMembershipsStartItem(
                        member_id=payer.member_id,
                        price_id=paid_recurring.price_id,
                    ),
                ],
            )
        )

        # Two charge groups were attempted (one-time + recurring).
        assert response.charge_count == 2
        assert response.multiple_charges is True

        by_plan = {r.plan_id: r for r in response.results}
        ot_result = by_plan[free_plan.plan_id]
        rec_result = by_plan[paid_recurring.plan_id]

        # ── One-time group: $0 invoice settles, row kept + billed. ──
        # The failed recurring sibling never un-bills this group.
        assert ot_result.status.value == "created"
        assert ot_result.item_id is not None
        ot_row = await _read_membership_row(db_pool, ot_result.item_id)
        assert ot_row["status"] == "applied"
        assert ot_row["stripe_one_time_invoice_id"] is not None
        assert ot_row["stripe_one_time_invoice_id"].startswith("in_")
        assert ot_row["total_price"] == 0
        invoice = await stripe_client.client.v1.invoices.retrieve_async(
            ot_row["stripe_one_time_invoice_id"], options=connect_opts
        )
        assert invoice.status == "paid"
        assert invoice.amount_paid == 0

        # ── Recurring group: FAILED with the decline error. ──
        assert rec_result.status.value == "failed"
        assert rec_result.error is not None
        assert "declined" in rec_result.error.lower()

        # The pending recurring membership row was cleaned up entirely.
        assert (
            await _count_membership_rows(db_pool, payer.member_id) == 1
        ), "only the one-time row should remain; the recurring row was cleaned"

        # ── No subscription was left behind on the customer. ──
        profile = await get_profile_stripe_ids(
            db_pool, payer.member_id, gym_id
        )
        assert profile.stripe_sub_id_month is None
        subs = await stripe_client.client.v1.subscriptions.list_async(
            params={
                "customer": payer.stripe_customer_id,
                "status": "all",
                "limit": 10,
            },
            options=connect_opts,
        )
        assert subs.data == [], (
            f"error_if_incomplete must leave no subscription; got "
            f"{[(s.id, s.status) for s in subs.data]}"
        )
    finally:
        await delete_member_data(db_pool, payer.member_id)


# ── Test 5 — single-member recurring start, declining card → failed ──


@pytest.mark.timeout(240)
async def test_single_recurring_start_declining_card_fails(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A lone recurring start on a declining card fails with no charge.

    The simplest decline case: ONE recurring membership, no one-time sibling,
    declining card, ``proration_behavior=prorate_to_anchor``, NOT cash. The create 402s,
    so the result
    row is ``failed``, the pending membership row is cleaned (no rows remain),
    no subscription is left on the customer, and no charge succeeded.
    """
    good_pm = await created.payment_method()
    member = await created.member(
        gym_id, first_name="Lone", last_name="Decline",
        payment_method_id=good_pm,
    )
    await _swap_to_failing_card(
        stripe_client, connect_opts, member.stripe_customer_id
    )
    plan = await created.plan(
        gym_id, plan_name="Solo Monthly", price_cents=5000
    )

    try:
        response = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                paid_with_cash=False,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id, price_id=plan.price_id,
                    ),
                ],
            )
        )

        # Single recurring charge group, which failed.
        assert response.charge_count == 1
        assert response.multiple_charges is False
        assert len(response.results) == 1
        result = response.results[0]
        assert result.status.value == "failed"
        assert result.error is not None
        assert "declined" in result.error.lower()

        # Pending row cleaned — nothing left for this member.
        assert await _count_membership_rows(db_pool, member.member_id) == 0

        # No subscription, no successful charge.
        profile = await get_profile_stripe_ids(
            db_pool, member.member_id, gym_id
        )
        assert profile.stripe_sub_id_month is None
        subs = await stripe_client.client.v1.subscriptions.list_async(
            params={
                "customer": member.stripe_customer_id,
                "status": "all",
                "limit": 10,
            },
            options=connect_opts,
        )
        assert subs.data == []
        invoices = await stripe_client.client.v1.invoices.list_async(
            params={"customer": member.stripe_customer_id, "limit": 10},
            options=connect_opts,
        )
        assert all(
            inv.amount_paid == 0 for inv in invoices.data
        ), "no charge should have succeeded against a declining card"
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Test 6 — cash recurring start STILL succeeds on a declining card ──


@pytest.mark.timeout(240)
async def test_cash_recurring_start_with_declining_card_succeeds(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Regression: the cash path is NOT broken by error_if_incomplete.

    A ``paid_with_cash=True`` recurring start for a member whose card declines
    must STILL succeed: the cash path keeps ``default_incomplete`` + pays the
    first invoice out of band (never touching the card), so the decline is
    irrelevant. The result is ``created``, the row lands ``applied`` on a real
    sub-item line, and the subscription's first invoice is paid out of band.
    """
    good_pm = await created.payment_method()
    member = await created.member(
        gym_id, first_name="Cash", last_name="Decline",
        payment_method_id=good_pm,
    )
    await _swap_to_failing_card(
        stripe_client, connect_opts, member.stripe_customer_id
    )
    plan = await created.plan(
        gym_id, plan_name="Cash Monthly", price_cents=5000
    )

    try:
        response = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                paid_with_cash=True,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id, price_id=plan.price_id,
                    ),
                ],
            )
        )

        assert response.charge_count == 1
        result = response.results[0]
        assert result.status.value == "created", (
            f"cash start must succeed despite the declining card; "
            f"error={result.error}"
        )

        row = await _read_membership_row(db_pool, result.item_id)
        assert row["status"] == "applied"
        assert row["stripe_item_id"] is not None
        assert row["stripe_item_id"].startswith("si_")

        # The subscription exists and its first invoice was paid out of band.
        profile = await get_profile_stripe_ids(
            db_pool, member.member_id, gym_id
        )
        assert profile.stripe_sub_id_month is not None
        sub = await stripe_client.client.v1.subscriptions.retrieve_async(
            profile.stripe_sub_id_month, options=connect_opts
        )
        # An out-of-band-paid first invoice activates the sub (not incomplete).
        assert sub.status == "active"
        invoices = await stripe_client.client.v1.invoices.list_async(
            params={
                "customer": member.stripe_customer_id,
                "subscription": profile.stripe_sub_id_month,
                "limit": 10,
            },
            options=connect_opts,
        )
        assert len(invoices.data) == 1
        first_invoice = invoices.data[0]
        assert first_invoice.status == "paid"
        # Paid out of band (the cash path stamps the invoice) — the sub going
        # `active` despite the declining default card is the proof the card was
        # never charged.
        invoice_metadata = (
            first_invoice.metadata.to_dict() if first_invoice.metadata else {}
        )
        assert invoice_metadata.get("crm_paid_with_cash") == "true"
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Test 7 — adding to an EXISTING healthy sub when the card now declines ──


@pytest.mark.timeout(300)
async def test_add_to_existing_sub_card_declines_fails_and_reverts(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Adding a recurring membership to a live family fails + reverts on decline.

    Start a healthy recurring family (payer on a good card), then swap the
    payer's card to a declining one and add a SECOND recurring membership (a
    linked child) with ``proration_behavior=prorate_to_anchor``. The add generates a
    proration invoice;
    with ``error_if_incomplete`` on the update card path Stripe 402s and rolls
    the item change back. So:
      * the add result is ``failed`` with the decline error;
      * the child's pending membership row is reverted (gone);
      * the EXISTING subscription is untouched — still ONE item (the payer's),
        still ``active`` — and the payer's membership row is untouched.

    Empirically verified: ``error_if_incomplete`` on the update rolls the item
    change back on the 402 (the live sub keeps exactly its prior items), so no
    explicit-pay-then-revert fallback is needed.
    """
    good_pm = await created.payment_method()
    payer = await created.member(
        gym_id, first_name="Existing", last_name="Payer",
        payment_method_id=good_pm,
    )
    child = await created.member(
        gym_id, first_name="Existing", last_name="Child",
    )
    payer_plan = await created.plan(
        gym_id, plan_name="Existing Payer Plan", price_cents=5000
    )
    child_plan = await created.plan(
        gym_id, plan_name="Existing Child Plan", price_cents=6000
    )

    try:
        await _link_child(db_pool, child.member_id, payer.member_id)

        # First start: the payer's recurring membership on a GOOD card.
        first = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=payer.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                paid_with_cash=False,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=payer.member_id,
                        price_id=payer_plan.price_id,
                    ),
                ],
            )
        )
        assert first.results[0].status.value == "created"
        payer_item_id = first.results[0].item_id

        profile = await get_profile_stripe_ids(
            db_pool, payer.member_id, gym_id
        )
        sub_id = profile.stripe_sub_id_month
        assert sub_id is not None
        sub_before = await stripe_client.client.v1.subscriptions.retrieve_async(
            sub_id, options=connect_opts
        )
        assert len(sub_before.items.data) == 1
        assert sub_before.status == "active"

        # Swap to a declining card, then add the child's membership (an UPDATE
        # of the existing sub).
        await _swap_to_failing_card(
            stripe_client, connect_opts, payer.stripe_customer_id
        )
        add = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=payer.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                paid_with_cash=False,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=child.member_id,
                        price_id=child_plan.price_id,
                    ),
                ],
            )
        )

        # ── The add failed with the decline. ──
        assert add.results[0].status.value == "failed"
        assert add.results[0].error is not None
        assert "declined" in add.results[0].error.lower()

        # ── The child's pending row was reverted (cleaned). ──
        assert await _count_membership_rows(db_pool, child.member_id) == 0

        # ── The existing sub + payer membership are untouched. ──
        sub_after = await stripe_client.client.v1.subscriptions.retrieve_async(
            sub_id, options=connect_opts
        )
        assert len(sub_after.items.data) == 1, (
            "error_if_incomplete must roll the add back; the live sub keeps "
            "exactly its prior single item"
        )
        assert sub_after.status == "active"
        payer_row = await _read_membership_row(db_pool, payer_item_id)
        assert payer_row["status"] == "applied"
        assert payer_row["stripe_item_id"] is not None
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, payer.member_id)
