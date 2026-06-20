"""The in-task guard + the (direct) reprice op's failure end-state.

The in-task guard (``TasksService.assert_memberships_not_in_task``, wired into
every item-targeted membership endpoint at the router) rejects a mutation on a
membership referenced by a PENDING/RUNNING task item — a queued/retrying batch
task holds no family lock, so the guard stops a staff op racing it. A terminal
task lifts the guard. The reprice op is standalone DB-first verify-or-revert:
an unconfirmed converge reverts its DB phase, leaving the membership untouched.
"""

from uuid import UUID, uuid4

import pytest
import stripe
from schema.task import ProrationBehavior, TaskType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from src.payments.payments_exceptions import PaymentsStripeError
from src.plans.plans_schema import MembershipPlanPriceRequest
from src.shared.db_first_helpers import SyncNotConfirmedError
from src.tasks.service.tasks_queries import TasksQueries
from src.tasks.service.tasks_service import TasksService
from src.tasks.tasks_exceptions import MembershipInTaskError
from src.tasks.tasks_schema import TaskItemCreate
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import get_applied_discounts
from tests.helpers.service_factory import build_memberships_reprice
from tests.memberships.test_memberships_update_price import (
    _get_membership_row,
)


async def _seed_applied_membership(db_pool, member, gym_id, plan) -> UUID:
    """Insert one already-synced membership row directly (no Stripe)."""
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "INSERT INTO member_memberships_unfiltered "
                "(member_id, paid_by_member_id, gym_id, plan_id, price_id, "
                " start_date, last_paid_date, stripe_item_id, total_price, "
                " stripe_sync_status) "
                "VALUES (:member_id, :paid_by_member_id, :gym_id, :plan_id, "
                " :price_id, CURRENT_DATE, CURRENT_DATE, :line_id, 5000, "
                " 'applied') "
                "RETURNING item_id"
            ),
            {
                "member_id": str(member.member_id),
                "paid_by_member_id": str(member.member_id),
                "gym_id": str(gym_id),
                "plan_id": str(plan.plan_id),
                "price_id": str(plan.price_id),
                "line_id": f"si_guard_{uuid4().hex[:12]}",
            },
        )
        item_id = UUID(str(result.scalar_one()))
        await session.commit()
    return item_id


async def test_in_task_guard_blocks_then_lifts(
    db_pool,
    gym_id,
    created,
):
    """The guard rejects a membership inside an unfinished task — every
    item-targeted endpoint calls it — and a terminal task lifts it."""
    member = await created.member(gym_id)
    plan = await created.plan(gym_id)
    tasks_service = TasksService(db_pool)
    queries = TasksQueries(db_pool)

    try:
        item_id = await _seed_applied_membership(
            db_pool, member, gym_id, plan,
        )
        task_id = await tasks_service.create_task(
            gym_id,
            TaskType.membership_reprice,
            [
                TaskItemCreate(
                    member_id=member.member_id,
                    old_item_id=item_id,
                    target_price_id=plan.price_id,
                    proration_behavior=ProrationBehavior.no_charge,
                ),
            ],
        )

        # The guard every item-targeted endpoint runs rejects the membership.
        with pytest.raises(MembershipInTaskError):
            await tasks_service.assert_memberships_not_in_task([item_id])

        # Terminal task → guard lifted.
        items = await queries.get_items_for_task(task_id)
        claimed = await queries.claim_item(items[0].task_item_id)
        await queries.fail_item(claimed.task_item_id, "test: forced terminal")
        await queries.finalize_task_status(task_id)
        await tasks_service.assert_memberships_not_in_task([item_id])
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_reprice_reverts_on_failed_converge(
    memberships_service,
    plans_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A converge failure REVERTS the reprice's DB phase entirely.

    The reprice is a standalone DB-first op — it handles its own failure
    like cancel/start do: an unconfirmed converge deletes the discount
    copies + the pending successor and clears the old row's cancel_date,
    leaving the membership exactly as it was. Failure is injected by
    pointing the target price at a nonexistent Stripe price.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(gym_id)
    preset = await created.discount(gym_id, percentage_off=20)
    reprice_service = build_memberships_reprice(db_pool, stripe_client)

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
                        discount_ids=[preset.discount_id],
                    ),
                ],
            )
        )
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id FROM member_memberships "
                    "WHERE member_id = :id AND plan_id = :plan_id"
                ),
                {
                    "id": str(member.member_id),
                    "plan_id": str(plan.plan_id),
                },
            )
            item_id = UUID(str(result.scalar_one()))
        discounts_before = await get_applied_discounts(db_pool, item_id)
        assert len(discounts_before) == 1

        new_price = await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id,
                gym_id=gym_id,
                price=8000,
            ),
        )
        # Failure injection: the converge must die when it tries to put the
        # successor's line on Stripe.
        async with db_pool.session() as session:
            await session.execute(
                text(
                    "UPDATE membership_plan_prices_unfiltered "
                    "SET stripe_price_id = 'price_nonexistent_for_test' "
                    "WHERE price_id = :p"
                ),
                {"p": str(new_price.price_id)},
            )
            await session.commit()

        with pytest.raises(
            (PaymentsStripeError, SyncNotConfirmedError, stripe.StripeError)
        ):
            await reprice_service.reprice(
                member_id=member.member_id,
                old_item_id=item_id,
                target_price_id=new_price.price_id,
                proration_behavior=ProrationBehavior.no_charge,
            )

        # Fully reverted: old row live and untouched, no successor row,
        # the applied discount exactly as it was (no copies left behind).
        row = await _get_membership_row(db_pool, item_id)
        assert row["cancel_date"] is None
        assert row["status"] == "applied"
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT count(*) FROM member_memberships_unfiltered "
                    "WHERE member_id = :id AND price_id = :p"
                ),
                {
                    "id": str(member.member_id),
                    "p": str(new_price.price_id),
                },
            )
            assert int(result.scalar_one()) == 0
        discounts_after = await get_applied_discounts(db_pool, item_id)
        assert {str(d["applied_discount_id"]) for d in discounts_after} == {
            str(d["applied_discount_id"]) for d in discounts_before
        }
    finally:
        await delete_member_data(db_pool, member.member_id)
