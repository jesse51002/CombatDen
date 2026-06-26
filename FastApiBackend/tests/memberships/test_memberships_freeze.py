"""Integration tests for freezing/unfreezing memberships.

Freeze is a synthetic 100%-off, NOT a Stripe pause: a frozen membership STAYS on
the subscription (keeps its line id, stays ``applied``) and bills $0. So every
test asserts the membership's stamped ``total_price`` goes to 0 on freeze and
back to its full plan price on unfreeze, the subscription stays **active** (never
paused, never cancelled), and no surprise charge lands.
"""

from uuid import uuid4

import pytest
from sqlalchemy import text

from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import (
    get_active_membership_item_id,
    get_applied_discounts,
    get_membership_total_price,
    get_payer_monthly_bill,
    get_profile_stripe_ids,
)
from tests.helpers.db_writes import authorize_payer
from tests.helpers.stripe_assertions import (
    assert_no_unexpected_charges,
    fetch_subscription,
    snapshot_billing_state,
)


async def test_freeze_account(
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
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        price_before = await get_membership_total_price(
            db_pool, member.member_id, gym_id,
        )
        bill_before = await get_payer_monthly_bill(db_pool, member.member_id)
        assert price_before > 0 and bill_before > 0

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.freeze(member.member_id, gym_id, 2, idempotency_key=uuid4())

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT freeze_start_date, freeze_end_date "
                    "FROM members "
                    "WHERE member_id = :id"
                ),
                {"id": str(member.member_id)},
            )
            row = result.mappings().fetchone()

        assert row["freeze_start_date"] is not None
        assert row["freeze_end_date"] is not None

        # Freeze is a 100%-off, NOT a pause: the sub stays ACTIVE (never paused,
        # never cancelled) and nothing charges.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert sub.pause_collection is None, (
            "Freeze must NOT pause collection — it is a synthetic 100%-off"
        )
        assert sub.status == "active"
        # The membership's own total_price stays its real standalone price;
        # the BILL (the payer's monthly recurring) drops to $0.
        assert (
            await get_membership_total_price(db_pool, member.member_id, gym_id)
        ) == price_before
        assert (
            await get_payer_monthly_bill(db_pool, member.member_id)
        ) == 0, "Frozen member's actual bill must be $0"
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_freeze_updates_end_date(
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
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        await memberships_service.freeze(member.member_id, gym_id, 1, idempotency_key=uuid4())

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT freeze_end_date FROM members "
                    "WHERE member_id = :id"
                ),
                {"id": str(member.member_id)},
            )
            first_end = result.mappings().fetchone()["freeze_end_date"]

        # Snapshot between the two freeze calls. Extending a freeze
        # must not generate any charge or upcoming invoice.
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        # Re-freeze with different duration
        await memberships_service.freeze(member.member_id, gym_id, 3, idempotency_key=uuid4())

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT freeze_end_date FROM members "
                    "WHERE member_id = :id"
                ),
                {"id": str(member.member_id)},
            )
            second_end = result.mappings().fetchone()["freeze_end_date"]

        assert second_end > first_end

        # Re-freeze just extends the window; the bill stays $0 and the sub
        # stays active (no pause), with no charge from the extension.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert sub.pause_collection is None
        assert sub.status == "active"
        assert (
            await get_payer_monthly_bill(db_pool, member.member_id)
        ) == 0, "Re-frozen member's actual bill must still be $0"
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_unfreeze_account(
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
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        # The full (active) bill, to confirm it's restored on unfreeze.
        full_bill = await get_payer_monthly_bill(db_pool, member.member_id)
        assert full_bill > 0

        await memberships_service.freeze(member.member_id, gym_id, 2, idempotency_key=uuid4())
        # While frozen the BILL is $0 (the membership's own total_price stays real).
        assert (await get_payer_monthly_bill(db_pool, member.member_id)) == 0

        # Snapshot while frozen — the unfreeze itself must not invoice the
        # member; it just drops the 100%-off so the NEXT cycle bills full.
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.unfreeze(member.member_id, gym_id, idempotency_key=uuid4())

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT freeze_start_date, freeze_end_date "
                    "FROM members "
                    "WHERE member_id = :id"
                ),
                {"id": str(member.member_id)},
            )
            row = result.mappings().fetchone()

        assert row["freeze_start_date"] is None
        assert row["freeze_end_date"] is None

        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert sub.pause_collection is None
        assert sub.status == "active"
        # Billing resumes: the 100%-off is gone and the bill is back to full.
        assert (
            await get_payer_monthly_bill(db_pool, member.member_id)
        ) == full_bill
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_freeze_zero_months_raises(
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
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )

        # Validation error must not touch Stripe at all.
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        with pytest.raises(ValueError):
            await memberships_service.freeze(
                member.member_id, gym_id, 0, idempotency_key=uuid4()
            )

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
        if profile.stripe_sub_id_month is not None:
            sub = await fetch_subscription(
                stripe_client,
                profile.stripe_sub_id_month,
                connect_opts,
            )
            assert sub.pause_collection is None, "Failed validation must not pause the Stripe sub"
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_freeze_one_member_off_shared_line(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Freeze ONE member on a SHARED consolidated line — the sibling keeps paying.

    A payer + an authorized member, both on the SAME plan/price, consolidate into
    one Stripe line (quantity 2). Freezing only the authorized member applies a
    synthetic 100%-off to just their share — the line averages to 50% off, so it
    bills exactly one unit — so the payer keeps paying full while the frozen
    member is $0, both on the SAME line id (no split, no new row, no pause). This
    is the per-member freeze the old account-level pause could not do.
    """
    pm_id = await created.payment_method()
    payer = await created.member(
        gym_id, payment_method_id=pm_id, first_name="Payer", last_name="Shared"
    )
    child = await created.member(
        gym_id, first_name="Child", last_name="Shared"
    )
    plan = await created.plan(gym_id)

    try:
        # Authorize the payer to pay for the child, then start BOTH on the SAME
        # plan/price in one request → one consolidated line, quantity 2.
        await authorize_payer(db_pool, child.member_id, payer.member_id)
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

        payer_full = await get_membership_total_price(
            db_pool, payer.member_id, gym_id,
        )
        child_full = await get_membership_total_price(
            db_pool, child.member_id, gym_id,
        )
        assert payer_full > 0 and child_full > 0
        # Both units bill before the freeze.
        assert (
            await get_payer_monthly_bill(db_pool, payer.member_id)
        ) == payer_full + child_full

        profile = await get_profile_stripe_ids(
            db_pool, payer.member_id, gym_id,
        )
        before = await snapshot_billing_state(
            stripe_client, profile.stripe_customer_id, connect_opts,
        )

        # Freeze ONLY the child.
        await memberships_service.freeze(
            child.member_id, gym_id, 2, idempotency_key=uuid4(),
        )

        # Both per-membership total_prices stay the real standalone price; the
        # BILL drops to just the active (payer's) unit — the child's share is $0.
        # The sub stays active (no pause) and nothing was charged by the freeze.
        assert (
            await get_membership_total_price(db_pool, child.member_id, gym_id)
        ) == child_full
        assert (
            await get_membership_total_price(db_pool, payer.member_id, gym_id)
        ) == payer_full
        assert (
            await get_payer_monthly_bill(db_pool, payer.member_id)
        ) == payer_full, "Shared line must bill only the active unit"
        sub = await fetch_subscription(
            stripe_client, profile.stripe_sub_id_month, connect_opts,
        )
        assert sub.status == "active"
        assert sub.pause_collection is None
        await assert_no_unexpected_charges(
            stripe_client, before, connect_opts,
        )
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, payer.member_id)


async def test_frozen_membership_discount_still_reaches_writeback(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A frozen membership's OWN discount still lands in the writeback.

    The membership bills $0 (the synthetic 100%-off), but its applied-discount
    row must NOT be stranded: the sync still collects it, so the row gets a
    coupon link and flips to ``applied``. We exercise the strongest case — a
    discount on a membership STARTED for an already-frozen member, so the
    applied-discount row begins ``not_added`` and must be carried to ``applied``
    by the frozen converge. (Without collecting frozen discounts the row would
    stay ``not_added`` — invisible to clients and reaped by the orphan cleanup.)
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(gym_id)
    discount = await created.discount(
        gym_id, name="Frozen 20%", percentage_off=20.0,
    )

    try:
        # Freeze the member up front (no prior subscription).
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

        # Start WITH the discount: the membership is frozen ($0) but its discount
        # must still be resolved by the writeback.
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=plan.price_id,
                        discount_ids=[discount.discount_id],
                    ),
                ],
            )
        )

        item_id = await get_active_membership_item_id(
            db_pool, member.member_id, gym_id,
        )
        applied = await get_applied_discounts(db_pool, item_id)
        assert len(applied) == 1, f"expected 1 applied discount, got {len(applied)}"
        # A non-null coupon means the writeback linked it AND flipped the row to
        # `applied` (`set_applied_discount_coupon_id` writes both). A null coupon
        # would mean the frozen membership's discount was skipped and stranded.
        assert applied[0]["stripe_coupon_id"] is not None, (
            "a frozen membership's discount must still get a coupon link + "
            "reach `applied`"
        )
        # ...and the membership genuinely bills $0 while frozen.
        assert (
            await get_payer_monthly_bill(db_pool, member.member_id)
        ) == 0
    finally:
        await delete_member_data(db_pool, member.member_id)
