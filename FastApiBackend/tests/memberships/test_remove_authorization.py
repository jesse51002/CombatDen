"""Integration tests for remove_authorization — the pair-scoped cascading cancel.

Removing a payment authorization cancels the recurring memberships funded across
THAT ONE relationship and de-authorizes only that pair. The billing-critical
invariant these tests guard: it must NOT touch the payer's memberships for OTHER
members, nor the member's memberships paid by OTHER payers. Each test confirms
the cancel reached the right rows and no surprise charges landed.
"""

from uuid import UUID, uuid4

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
    snapshot_billing_state,
)


async def _item_id_for(db_pool, member_id: UUID, plan_id: UUID) -> UUID:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT item_id FROM member_memberships_unfiltered "
                "WHERE member_id = :m AND plan_id = :p"
            ),
            {"m": str(member_id), "p": str(plan_id)},
        )
        return UUID(str(result.mappings().one()["item_id"]))


async def _cancel_date(db_pool, item_id: UUID):
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT cancel_date FROM member_memberships_unfiltered "
                "WHERE item_id = :i"
            ),
            {"i": str(item_id)},
        )
        return result.mappings().one()["cancel_date"]


async def _is_authorized(db_pool, member_id: UUID, payer_member_id: UUID) -> bool:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT 1 FROM member_authorized_payers "
                "WHERE member_id = :m AND payer_member_id = :p"
            ),
            {"m": str(member_id), "p": str(payer_member_id)},
        )
        return result.mappings().fetchone() is not None


async def test_remove_authorization_cancels_only_the_pair(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Remove (A, P): cancel A's membership paid by P only.

    Leaves B's membership paid by P (other member) and A's self-paid membership
    (other payer) untouched, and removes only the (A, P) authorization.
    """
    pm_p = await created.payment_method()
    pm_a = await created.payment_method()
    payer = await created.member(gym_id, payment_method_id=pm_p)
    member_a = await created.member(gym_id, payment_method_id=pm_a)
    member_b = await created.member(gym_id)
    plan = await created.plan(gym_id)
    plan_self = await created.plan(gym_id)

    await authorize_payer(db_pool, member_a.member_id, payer.member_id)
    await authorize_payer(db_pool, member_b.member_id, payer.member_id)

    try:
        # P pays for A and B (one consolidated start), A self-pays a 2nd plan.
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=payer.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member_a.member_id,
                        price_id=plan.price_id,
                    ),
                    MemberMembershipsStartItem(
                        member_id=member_b.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member_a.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member_a.member_id,
                        price_id=plan_self.price_id,
                    ),
                ],
            )
        )

        a_paid_by_p = await _item_id_for(db_pool, member_a.member_id, plan.plan_id)
        b_paid_by_p = await _item_id_for(db_pool, member_b.member_id, plan.plan_id)
        a_self = await _item_id_for(db_pool, member_a.member_id, plan_self.plan_id)

        # Preview is a per-payer cost preview: pair-scoped → exactly one
        # entry, for the payer P whose subscription loses A's line.
        preview = await memberships_service.preview_remove_authorization(
            member_a.member_id,
            payer.member_id,
        )
        assert len(preview) == 1
        assert preview[0].payer_member_id == payer.member_id
        assert preview[0].preview is not None

        payer_profile = await get_profile_stripe_ids(
            db_pool, payer.member_id, gym_id
        )
        before = await snapshot_billing_state(
            stripe_client, payer_profile.stripe_customer_id, connect_opts
        )

        await memberships_service.remove_authorization(
            member_a.member_id,
            payer.member_id,
        )

        # Only A's membership paid by P is cancelled.
        assert await _cancel_date(db_pool, a_paid_by_p) is not None
        assert await _cancel_date(db_pool, b_paid_by_p) is None  # other member
        assert await _cancel_date(db_pool, a_self) is None  # other payer

        # Only the (A, P) authorization is removed; (B, P) survives.
        assert not await _is_authorized(
            db_pool, member_a.member_id, payer.member_id
        )
        assert await _is_authorized(
            db_pool, member_b.member_id, payer.member_id
        )

        await assert_no_unexpected_charges(stripe_client, before, connect_opts)
    finally:
        await delete_member_data(db_pool, member_a.member_id)
        await delete_member_data(db_pool, member_b.member_id)
        await delete_member_data(db_pool, payer.member_id)


async def test_remove_authorization_no_memberships_just_deauthorizes(
    memberships_service,
    db_pool,
    gym_id,
    created,
):
    """Removing an authorization with no funded memberships is a clean
    de-authorize: empty preview, no cancel, the row is gone."""
    payer = await created.member(gym_id)
    member = await created.member(gym_id)
    await authorize_payer(db_pool, member.member_id, payer.member_id)

    try:
        preview = await memberships_service.preview_remove_authorization(
            member.member_id, payer.member_id
        )
        assert preview == []

        await memberships_service.remove_authorization(
            member.member_id, payer.member_id
        )
        assert not await _is_authorized(
            db_pool, member.member_id, payer.member_id
        )
    finally:
        await delete_member_data(db_pool, member.member_id)
        await delete_member_data(db_pool, payer.member_id)
