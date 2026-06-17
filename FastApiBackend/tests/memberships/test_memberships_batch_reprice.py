"""Per-plan BATCH reprice — the only reprice that is a tracked task.

``POST /member_memberships/reprice-plan`` (mirrored by the
``batch_reprice_plan`` helper) auto-discovers every live membership on a plan
not already on its active price, creates ONE task with an item per membership,
runs them in the background, and returns the task id. These cover:

* the happy path — N members on a stale price all land on the active price;
* nothing to do — every member already on the active price → no task;
* the in-task exclusion — a membership already mid-task is skipped;
* the retry: a busy family exhausts the 3 attempts → that item fails with the
  membership untouched (DB-first verify-or-revert), and re-running the batch
  picks it up again and succeeds.
"""

from uuid import UUID

from schema.task import TaskType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.plans.plans_schema import MembershipPlanPriceRequest
from src.tasks.service.tasks_service import TasksService
from src.tasks.tasks_schema import TaskItemCreate
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import await_task_terminal
from tests.helpers.service_factory import (
    batch_reprice_plan,
    build_paying_member_lock,
)
from tests.memberships.test_memberships_update_price import (
    _get_membership_row,
    _start_and_get_item_id,
)


async def _live_membership(db_pool, member_id, plan_id) -> dict:
    """The member's current live (applied, not cancelled) row on the plan."""
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT item_id, price_id, stripe_sync_status::text AS status "
                "FROM member_memberships_unfiltered "
                "WHERE member_id = :m AND plan_id = :p "
                "  AND cancel_date IS NULL AND stripe_sync_status = 'applied'"
            ),
            {"m": str(member_id), "p": str(plan_id)},
        )
        return dict(result.mappings().one())


async def _task_items(db_pool, task_id) -> list[dict]:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT status::text AS status, attempt_count, "
                "error_message, old_item_id, new_item_id "
                "FROM task_items WHERE task_id = :t ORDER BY created_at"
            ),
            {"t": str(task_id)},
        )
        return [dict(r) for r in result.mappings().fetchall()]


async def test_batch_upgrades_all_plan_members(
    memberships_service,
    plans_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Every member on a stale price lands on the plan's active price."""
    pm_a = await created.payment_method()
    pm_b = await created.payment_method()
    member_a = await created.member(gym_id, payment_method_id=pm_a)
    member_b = await created.member(gym_id, payment_method_id=pm_b)
    plan = await created.plan(gym_id)

    try:
        await _start_and_get_item_id(
            memberships_service, db_pool, member_a, gym_id, plan,
        )
        await _start_and_get_item_id(
            memberships_service, db_pool, member_b, gym_id, plan,
        )
        # New active price — both members are now on the stale (old) one.
        new_price = await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id, gym_id=gym_id, price=8000,
            ),
        )

        task_id, count = await batch_reprice_plan(
            db_pool, stripe_client, gym_id, plan.plan_id, prorate=False,
        )
        assert count == 2
        assert task_id is not None
        assert await await_task_terminal(db_pool, task_id) == "completed"

        for member in (member_a, member_b):
            row = await _live_membership(db_pool, member.member_id, plan.plan_id)
            assert UUID(str(row["price_id"])) == new_price.price_id
            assert row["status"] == "applied"
    finally:
        await delete_member_data(db_pool, member_a.member_id)
        await delete_member_data(db_pool, member_b.member_id)


async def test_batch_nothing_to_upgrade_no_task(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Every member already on the active price → no task is created."""
    pm = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm)
    plan = await created.plan(gym_id)

    try:
        await _start_and_get_item_id(
            memberships_service, db_pool, member, gym_id, plan,
        )
        # No new price — the member is already on the plan's active price.
        task_id, count = await batch_reprice_plan(
            db_pool, stripe_client, gym_id, plan.plan_id,
        )
        assert task_id is None
        assert count == 0
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_batch_skips_membership_already_in_task(
    memberships_service,
    plans_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A membership referenced by an unfinished task is excluded from
    discovery (a re-run won't double-task it)."""
    pm = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm)
    plan = await created.plan(gym_id)
    tasks_service = TasksService(db_pool)

    try:
        item_id = await _start_and_get_item_id(
            memberships_service, db_pool, member, gym_id, plan,
        )
        await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id, gym_id=gym_id, price=8000,
            ),
        )
        # Park the membership in a pending task (don't run it).
        await tasks_service.create_task(
            gym_id,
            TaskType.membership_reprice,
            [
                TaskItemCreate(
                    member_id=member.member_id,
                    old_item_id=item_id,
                    target_price_id=plan.price_id,
                    prorate=False,
                ),
            ],
        )

        # On a stale price, but mid-task → discovery skips it.
        task_id, count = await batch_reprice_plan(
            db_pool, stripe_client, gym_id, plan.plan_id,
        )
        assert task_id is None
        assert count == 0

        # Finish the parked task → the next batch picks the membership up.
        async with db_pool.session() as session:
            await session.execute(
                text(
                    "UPDATE task_items SET status = 'completed' "
                    "WHERE old_item_id = :i"
                ),
                {"i": str(item_id)},
            )
            await session.commit()
        _, count2 = await batch_reprice_plan(
            db_pool, stripe_client, gym_id, plan.plan_id,
        )
        assert count2 == 1
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_batch_item_lock_busy_retries_then_resubmit(
    memberships_service,
    plans_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A busy family exhausts the 3 attempts → that item fails with the
    membership untouched; re-running the batch picks it up and succeeds."""
    pm = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm)
    plan = await created.plan(gym_id)
    paying_lock = build_paying_member_lock(db_pool)

    try:
        item_id = await _start_and_get_item_id(
            memberships_service, db_pool, member, gym_id, plan,
        )
        new_price = await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id, gym_id=gym_id, price=8000,
            ),
        )

        async with paying_lock.lock([member.member_id]):
            task_id, count = await batch_reprice_plan(
                db_pool, stripe_client, gym_id, plan.plan_id, prorate=False,
            )
            assert count == 1
            assert await await_task_terminal(db_pool, task_id) == "failed"

        items = await _task_items(db_pool, task_id)
        assert len(items) == 1
        assert items[0]["status"] == "failed"
        assert items[0]["attempt_count"] == 3
        assert items[0]["new_item_id"] is None  # never reached the DB phase

        # The membership is untouched — still live on the old price.
        row = await _get_membership_row(db_pool, item_id)
        assert row["cancel_date"] is None
        assert row["status"] == "applied"

        # Re-run the batch (the failed item no longer guards the row).
        task_2, count2 = await batch_reprice_plan(
            db_pool, stripe_client, gym_id, plan.plan_id, prorate=False,
        )
        assert count2 == 1
        assert await await_task_terminal(db_pool, task_2) == "completed"
        row2 = await _live_membership(db_pool, member.member_id, plan.plan_id)
        assert UUID(str(row2["price_id"])) == new_price.price_id
    finally:
        await delete_member_data(db_pool, member.member_id)
