"""Integration tests for the scheduled reconciler.

Run against the real local Supabase DB. These cover the genuinely-new reconciler
logic that needs no live Stripe subscription:

- ``ResourceLock`` (generic non-blocking TTL lease)
- ``OrphanCleanupSweep`` (lock-guarded delete of ``not_added`` rows)

The Stripe-read path (``InvoiceFetchSweep``) needs a real subscription/test-clock
fixture and is not covered here.
"""

from uuid import UUID, uuid4

from schema.task import TaskType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.core.config import PAYING_MEMBER_LOCK_PREFIX
from src.reconciler.service.reconciler.reconciler_orphan_cleanup_sweep import (
    OrphanCleanupSweep,
)
from src.shared.billing_parent_resolver import BillingParentResolver
from src.shared.gym_stripe_service import GymStripeService
from src.shared.resource_lock import ResourceLock
from src.tasks.service.tasks_queries import TasksQueries
from src.tasks.service.tasks_service import TasksService
from src.tasks.tasks_schema import TaskItemCreate

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


async def test_orphan_cleanup_skips_task_referenced_rows(
    db_pool, gym_id, created
):
    """A pending row a TASK produced is not an orphan.

    The reprice's successor waits as 'not_added' between retry attempts
    (and after a FAILED task, it is the member's only live membership) —
    the sweep must leave it for the push sweep to converge. Once the task
    item is 'completed', the row is sweepable again.
    """
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

    tasks_service = TasksService(db_pool)
    queries = TasksQueries(db_pool)
    task_id = await tasks_service.create_task(
        gym_id,
        TaskType.membership_reprice,
        [
            TaskItemCreate(
                member_id=member.member_id,
                target_price_id=plan.price_id,
                prorate=False,
            ),
        ],
    )
    items = await queries.get_items_for_task(task_id)
    task_item_id = items[0].task_item_id
    # Reference the pending row as the task's successor (pending item).
    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE task_items SET new_item_id = :item "
                "WHERE task_item_id = :ti"
            ),
            {"item": str(item_id), "ti": str(task_item_id)},
        )
        await session.commit()

    sweep = OrphanCleanupSweep(
        db_pool, _parent_resolver(db_pool), ResourceLock(db_pool)
    )

    # Pending item -> excluded.
    await sweep.run()
    assert await _membership_row(db_pool, item_id) is not None

    # FAILED item -> still excluded (the successor is the member's only
    # live membership).
    claimed = await queries.claim_item(task_item_id)
    await queries.fail_item(claimed.task_item_id, "test: forced failure")
    await sweep.run()
    assert await _membership_row(db_pool, item_id) is not None

    # Task records removed -> the row is an ordinary orphan again. (A
    # COMPLETED item can never expose its successor to the sweep for real:
    # completed means the verify saw the row 'applied' with its line id
    # stamped, so it never matches the orphan criteria.)
    async with db_pool.session() as session:
        await session.execute(
            text("DELETE FROM task_items WHERE task_item_id = :ti"),
            {"ti": str(task_item_id)},
        )
        await session.execute(
            text("DELETE FROM tasks WHERE task_id = :t"),
            {"t": str(task_id)},
        )
        await session.commit()
    await sweep.run()
    assert await _membership_row(db_pool, item_id) is None
