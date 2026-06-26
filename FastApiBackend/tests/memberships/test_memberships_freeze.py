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
    get_profile_stripe_ids,
)
from tests.helpers.db_writes import authorize_payer
from tests.helpers.stripe_assertions import (
    assert_no_unexpected_charges,
    fetch_subscription,
    snapshot_billing_state,
)


async def _membership_total_price(db_pool, member_id, gym_id) -> int:
    """The member's active membership stamped post-discount ``total_price``.

    0 while frozen (the synthetic 100%-off), the full plan price when active.
    Reads the filtered ``member_memberships`` view — a frozen membership is
    still visible there because it keeps its ``stripe_item_id`` (freeze is a
    discount, not a drop).
    """
    item_id = await get_active_membership_item_id(db_pool, member_id, gym_id)
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT total_price FROM member_memberships WHERE item_id = :id"
            ),
            {"id": str(item_id)},
        )
        return result.scalar_one()


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
        # never cancelled), the frozen membership bills $0, and nothing charges.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert sub.pause_collection is None, (
            "Freeze must NOT pause collection — it is a synthetic 100%-off"
        )
        assert sub.status == "active"
        total = await _membership_total_price(db_pool, member.member_id, gym_id)
        assert total == 0, f"Frozen membership must bill $0, got {total}"
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

        # Re-freeze just extends the window; the membership stays $0 and the sub
        # stays active (no pause), with no charge from the extension.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert sub.pause_collection is None
        assert sub.status == "active"
        total = await _membership_total_price(db_pool, member.member_id, gym_id)
        assert total == 0, f"Re-frozen membership must still bill $0, got {total}"
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

        # The full (active) price, to confirm it's restored on unfreeze.
        full_total = await _membership_total_price(
            db_pool, member.member_id, gym_id,
        )
        assert full_total > 0

        await memberships_service.freeze(member.member_id, gym_id, 2, idempotency_key=uuid4())
        assert (
            await _membership_total_price(db_pool, member.member_id, gym_id)
        ) == 0

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
        # Billing resumes: the 100%-off is gone and total_price is back to full.
        assert (
            await _membership_total_price(db_pool, member.member_id, gym_id)
        ) == full_total
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

        payer_full = await _membership_total_price(
            db_pool, payer.member_id, gym_id,
        )
        child_full = await _membership_total_price(
            db_pool, child.member_id, gym_id,
        )
        assert payer_full > 0 and child_full > 0

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

        # The child is now $0; the payer keeps paying full; the sub stays active
        # (no pause) and nothing was charged by the freeze.
        assert (
            await _membership_total_price(db_pool, child.member_id, gym_id)
        ) == 0
        assert (
            await _membership_total_price(db_pool, payer.member_id, gym_id)
        ) == payer_full
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
