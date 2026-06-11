"""Tests for the sync's dead-subscription cancel path.

When Stripe reports the family's monthly subscription gone, the payment sync
records the cancellation in the CRM — cancel the family's live recurring
memberships + null the parent's sub id — instead of recreating the sub (which
would re-bill a member Stripe already let go). Two levels:

- ``PaymentSyncCancel.cancel_dead_subscription`` — the CRM-only write, no Stripe.
- ``update_payments_recurring`` AND ``preview_update_payments_recurring`` — both
  catch the subscription not-found surfaced by the converge (gated on
  ``resource_type == subscription``), record the cancellation, then **re-raise**
  (the requested converge/preview could not happen against a gone sub).

Run against the real local Supabase DB + real Stripe test Connect. The membership
is inserted directly (no real sub); the family is pointed at a sub id Stripe does
not have, so the converge's ``update_subscription`` raises a real not-found.
"""

from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.shared.billing_parent_resolver import BillingParentResolver
from src.shared.gym_stripe_service import GymStripeService
from src.sync.service.sync_cancel import (
    PaymentSyncCancel,
)
from tests.helpers.service_factory import build_payment_sync_service

_TOTAL_PRICE = 5000


def _parent_resolver(db_pool) -> BillingParentResolver:
    return BillingParentResolver(db_pool, GymStripeService(db_pool))


async def _insert_membership(
    db_pool,
    member_id: UUID,
    gym_id: UUID,
    plan,
    *,
    stripe_item_id: str | None,
    sync_status: str,
) -> UUID:
    """Insert a membership row directly and return its item_id.

    start_date a week back keeps the daterange(start, cancel) trigger valid when
    the cancel sets cancel_date from the gym-tz "today" (which near UTC midnight
    can be the day before CURRENT_DATE in UTC).
    """
    sql = """
        INSERT INTO member_memberships_unfiltered (
            member_id, gym_id, plan_id, price_id,
            start_date, stripe_item_id, total_price, stripe_sync_status
        ) VALUES (
            :member_id, :gym_id, :plan_id, :price_id,
            CURRENT_DATE - 7, :stripe_item_id, :total_price,
            CAST(:sync_status AS stripe_sync_status)
        )
        RETURNING item_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(sql),
            {
                "member_id": str(member_id),
                "gym_id": str(gym_id),
                "plan_id": str(plan.plan_id),
                "price_id": str(plan.price_id),
                "stripe_item_id": stripe_item_id,
                "total_price": _TOTAL_PRICE,
                "sync_status": sync_status,
            },
        )
        row = result.mappings().fetchone()
        await session.commit()
    return UUID(str(row["item_id"]))


async def _membership_row(db_pool, item_id: UUID) -> dict | None:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT cancel_date, stripe_sync_status "
                "FROM member_memberships_unfiltered WHERE item_id = :id"
            ),
            {"id": str(item_id)},
        )
        row = result.mappings().fetchone()
    return dict(row) if row else None


async def _sub_id(db_pool, member_id: UUID) -> str | None:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT stripe_sub_id_month FROM members WHERE member_id = :id"
            ),
            {"id": str(member_id)},
        )
        row = result.mappings().fetchone()
    return row["stripe_sub_id_month"] if row else None


async def _set_sub_id(db_pool, member_id: UUID, sub_id: str) -> None:
    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE members SET stripe_sub_id_month = :sub "
                "WHERE member_id = :id"
            ),
            {"sub": sub_id, "id": str(member_id)},
        )
        await session.commit()


# ── PaymentSyncCancel (CRM-only) ───────────────────────────────


async def test_cancel_dead_subscription_cancels_family_and_nulls_sub_id(
    db_pool, gym_id, created
):
    member = await created.member(gym_id)
    plan = await created.plan(gym_id)
    item_id = await _insert_membership(
        db_pool,
        member.member_id,
        gym_id,
        plan,
        stripe_item_id=f"si_fake_{uuid4().hex[:12]}",
        sync_status="applied",
    )
    await _set_sub_id(db_pool, member.member_id, f"sub_fake_{uuid4().hex[:12]}")

    parent = await _parent_resolver(db_pool).resolve_parent(member.member_id)
    cancelled = await PaymentSyncCancel(db_pool).cancel_dead_subscription(parent)

    assert cancelled == 1
    row = await _membership_row(db_pool, item_id)
    assert row is not None
    assert row["cancel_date"] is not None
    assert row["stripe_sync_status"] == "deleted"
    assert await _sub_id(db_pool, member.member_id) is None


async def test_cancel_dead_subscription_is_idempotent(db_pool, gym_id, created):
    member = await created.member(gym_id)
    plan = await created.plan(gym_id)
    await _insert_membership(
        db_pool,
        member.member_id,
        gym_id,
        plan,
        stripe_item_id=f"si_fake_{uuid4().hex[:12]}",
        sync_status="applied",
    )
    await _set_sub_id(db_pool, member.member_id, f"sub_fake_{uuid4().hex[:12]}")

    resolver = _parent_resolver(db_pool)
    svc = PaymentSyncCancel(db_pool)
    parent = await resolver.resolve_parent(member.member_id)
    assert await svc.cancel_dead_subscription(parent) == 1
    # Second run: the family is already cancelled -> nothing to cancel.
    parent_again = await resolver.resolve_parent(member.member_id)
    assert await svc.cancel_dead_subscription(parent_again) == 0


# ── update_payments_recurring: dead-sub catch (real Stripe not-found) ──


async def test_sync_cancels_family_when_subscription_gone(
    db_pool, stripe_client, gym_id, created
):
    member = await created.member(gym_id)
    plan = await created.plan(gym_id)
    item_id = await _insert_membership(
        db_pool,
        member.member_id,
        gym_id,
        plan,
        stripe_item_id=f"si_fake_{uuid4().hex[:12]}",
        sync_status="applied",
    )
    # Point the family at a sub Stripe does not have: the converge's
    # update_subscription retrieve raises not-found (resource_type=subscription).
    # The sync records the cancellation, then re-raises (the converge failed).
    await _set_sub_id(db_pool, member.member_id, f"sub_{uuid4().hex[:20]}")

    svc = build_payment_sync_service(db_pool, stripe_client)
    with pytest.raises(PaymentsResourceNotFoundError):
        await svc.update_payments_recurring(
            member.member_id, idempotency_key=uuid4()
        )

    # The cancellation was still recorded before the raise.
    row = await _membership_row(db_pool, item_id)
    assert row is not None
    assert row["cancel_date"] is not None
    assert row["stripe_sync_status"] == "deleted"
    assert await _sub_id(db_pool, member.member_id) is None


async def test_preview_cancels_family_when_subscription_gone(
    db_pool, stripe_client, gym_id, created
):
    member = await created.member(gym_id)
    plan = await created.plan(gym_id)
    item_id = await _insert_membership(
        db_pool,
        member.member_id,
        gym_id,
        plan,
        stripe_item_id=f"si_fake_{uuid4().hex[:12]}",
        sync_status="applied",
    )
    # Preview records a gone sub too (settled fact, like the once-settle that
    # already writes during preview), then re-raises — no invoice to preview.
    await _set_sub_id(db_pool, member.member_id, f"sub_{uuid4().hex[:20]}")

    svc = build_payment_sync_service(db_pool, stripe_client)
    with pytest.raises(PaymentsResourceNotFoundError):
        await svc.preview_update_payments_recurring(member.member_id)

    row = await _membership_row(db_pool, item_id)
    assert row is not None
    assert row["cancel_date"] is not None
    assert row["stripe_sync_status"] == "deleted"
    assert await _sub_id(db_pool, member.member_id) is None
