"""Integration tests for the scheduled reconciler.

Run against the real local Supabase DB. These cover the genuinely-new reconciler
logic that needs no live Stripe subscription:

- ``ResourceLock`` (generic non-blocking TTL lease)
- ``OrphanCleanupSweep`` (lock-guarded delete of ``not_added`` rows)

The Stripe-read path (``InvoiceFetchSweep``) needs a real subscription/test-clock
fixture and is not covered here.
"""

from uuid import UUID, uuid4

from sqlalchemy import text

from src.core.config import PAYING_MEMBER_LOCK_PREFIX
from src.reconciler.service.reconciler.reconciler_orphan_cleanup_sweep import (
    OrphanCleanupSweep,
)
from src.shared.gym_stripe_service import GymStripeService
from src.shared.payer_resolver import PayerResolver
from src.shared.resource_lock import ResourceLock

_TOTAL_PRICE = 5000


def _parent_resolver(db_pool) -> PayerResolver:
    return PayerResolver(db_pool, GymStripeService(db_pool))


async def _insert_membership(
    db_pool,
    member_id: UUID,
    gym_id: UUID,
    plan,
    *,
    stripe_item_id: str | None,
    sync_status: str,
) -> UUID:
    """Insert a membership row directly and return its item_id."""
    # start_date a week back keeps the daterange(start_date, cancel_date) trigger
    # valid for any later cancel; harmless for the not_added orphan rows here.
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


# ── ResourceLock ───────────────────────────────────────────────


async def test_resource_lock_acquire_once_blocks_while_held(db_pool):
    lock = ResourceLock(db_pool)
    key = f"test_lock_{uuid4().hex}"
    token_a = uuid4()
    token_b = uuid4()
    try:
        assert await lock.acquire_once(key, token_a) is True
        # Held by token_a -> a second acquire fails.
        assert await lock.acquire_once(key, token_b) is False
    finally:
        await lock.release(key, token_a)
    # Released -> acquirable again.
    assert await lock.acquire_once(key, token_b) is True
    await lock.release(key, token_b)


async def test_resource_lock_release_is_token_fenced(db_pool):
    lock = ResourceLock(db_pool)
    key = f"test_lock_{uuid4().hex}"
    token_a = uuid4()
    try:
        assert await lock.acquire_once(key, token_a) is True
        # A release with the wrong token must NOT free the lease.
        await lock.release(key, uuid4())
        assert await lock.acquire_once(key, uuid4()) is False
    finally:
        await lock.release(key, token_a)


async def test_resource_lock_try_lock_yields_true_then_false(db_pool):
    lock = ResourceLock(db_pool)
    key = f"test_lock_{uuid4().hex}"
    async with lock.try_lock(key) as got_first:
        assert got_first is True
        # Nested attempt while the outer context holds it -> False.
        async with lock.try_lock(key) as got_second:
            assert got_second is False
    # Released on exit -> acquirable again.
    async with lock.try_lock(key) as got_again:
        assert got_again is True


# ── OrphanCleanupSweep ─────────────────────────────────────────


async def test_orphan_cleanup_deletes_not_added_row(
    db_pool, gym_id, created
):
    member = await created.member(gym_id)
    plan = await created.plan(gym_id)
    item_id = await _insert_membership(
        db_pool,
        member.member_id,
        gym_id,
        plan,
        stripe_item_id=None,
        sync_status="not_added",
    )

    sweep = OrphanCleanupSweep(
        db_pool, _parent_resolver(db_pool), ResourceLock(db_pool)
    )
    result = await sweep.run()

    assert result.processed >= 1
    # Our orphan is gone.
    assert await _membership_row(db_pool, item_id) is None


async def test_orphan_cleanup_skips_when_family_lock_held(
    db_pool, gym_id, created
):
    member = await created.member(gym_id)
    plan = await created.plan(gym_id)
    item_id = await _insert_membership(
        db_pool,
        member.member_id,
        gym_id,
        plan,
        stripe_item_id=None,
        sync_status="not_added",
    )

    # Hold this family's lock so the sweep must skip the orphan.
    lock = ResourceLock(db_pool)
    family_key = f"{PAYING_MEMBER_LOCK_PREFIX}:{member.member_id}"
    token = uuid4()
    assert await lock.acquire_once(family_key, token) is True
    try:
        sweep = OrphanCleanupSweep(
            db_pool, _parent_resolver(db_pool), ResourceLock(db_pool)
        )
        result = await sweep.run()
        assert result.skipped >= 1
        # Row survived because its family was busy.
        assert await _membership_row(db_pool, item_id) is not None
    finally:
        await lock.release(family_key, token)

    # With the lock free, the next sweep deletes it.
    sweep = OrphanCleanupSweep(
        db_pool, _parent_resolver(db_pool), ResourceLock(db_pool)
    )
    await sweep.run()
    assert await _membership_row(db_pool, item_id) is None
