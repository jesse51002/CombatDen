"""Integration tests for membership preview (dry-run) operations.

Every test asserts two invariants:

1. The CRM database is not mutated (no new rows, no status flips).
2. Stripe billing state is untouched (no new invoices, no subscription
   changes, no charges).

And the returned preview has a plausible shape when the operation
would produce a real invoice — every surface returns a
``DueNowVsRecurringPreview`` split whose ``due_now`` / ``recurring``
halves are flat ``PreviewInvoice`` objects.
"""

from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

from src.membership_plans.membership_plans_schemas import MembershipPlanPriceRequest
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
    PreviewInvoice,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import get_profile_stripe_ids
from tests.helpers.stripe_assertions import (
    assert_no_unexpected_charges,
    fetch_subscription,
    snapshot_billing_state,
)

# ── Helpers ─────────────────────────────────────────────────────────


async def _count_memberships(db_pool, member_id) -> int:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT COUNT(*) AS c FROM member_memberships_unfiltered WHERE member_id = :id"
            ),
            {"id": str(member_id)},
        )
        row = result.mappings().one()
    return int(row["c"])


async def _start_and_get_item_id(
    memberships_service,
    db_pool,
    member,
    gym_id,
    plan,
):
    await memberships_service.start(
        member_id=member.member_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
        idempotency_key=uuid4(),
    )
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT item_id FROM member_memberships "
                "WHERE member_id = :id AND plan_id = :plan_id"
            ),
            {"id": str(member.member_id), "plan_id": str(plan.plan_id)},
        )
        row = result.mappings().fetchone()
    return UUID(str(row["item_id"]))


def _assert_valid_preview(preview) -> None:
    assert isinstance(preview, PreviewInvoice)
    assert preview.currency
    # Non-negative — a preview of a prorated cancel could be $0, but it
    # should never be reported as a negative charge on the response model.
    assert preview.amount_due >= 0
    assert preview.total >= 0


def _assert_valid_split(preview) -> None:
    """Shape checks for a due-now / recurring split preview.

    Both halves are ordinary invoice previews (or ``None``): ``due_now``
    is the immediate charge, ``recurring`` the steady-state cycle.
    """
    assert isinstance(preview, DueNowVsRecurringPreview)
    if preview.due_now is not None:
        _assert_valid_preview(preview.due_now)
    if preview.recurring is not None:
        _assert_valid_preview(preview.recurring)


# ── Start preview ───────────────────────────────────────────────────


async def test_preview_start_recurring(
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
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        preview = await memberships_service.preview_start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )

        _assert_valid_split(preview)
        # Recurring is the full monthly price (no discount here); due-now
        # is the prorated first payment, never more than a full period.
        assert preview.recurring.amount_due == plan.price_cents, (
            f"recurring.amount_due={preview.recurring.amount_due} != "
            f"plan price_cents={plan.price_cents}"
        )
        assert preview.due_now.amount_due <= plan.price_cents, (
            f"due_now.amount_due={preview.due_now.amount_due} exceeds "
            f"plan price_cents={plan.price_cents}"
        )

        # No DB row should have been inserted.
        assert await _count_memberships(db_pool, member.member_id) == 0

        # No subscription was created on the parent profile.
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is None

        # No new invoices, no charges.
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_preview_start_one_time(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        plan_name="Preview One-Time Plan",
        price_cents=3000,
    )

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        preview = await memberships_service.preview_start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )

        _assert_valid_split(preview)
        # A one-time purchase is entirely due now; nothing recurs.
        assert preview.due_now.amount_due == plan.price_cents, (
            f"one-time due_now.amount_due={preview.due_now.amount_due} != "
            f"plan price_cents={plan.price_cents}"
        )
        assert preview.recurring is None

        assert await _count_memberships(db_pool, member.member_id) == 0

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_preview_start_no_prorate_due_now_equals_recurring(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """prorate=False: due-now and recurring are the same preview.

    When not prorating, nothing extra is charged now, so the immediate
    and steady-state previews are identical — the split returns the same
    thing twice. Deterministic regardless of the billing anchor date.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(gym_id)

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        preview = await memberships_service.preview_start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            prorate=False,
        )

        _assert_valid_split(preview)
        assert preview.due_now is not None
        assert preview.recurring is not None
        assert preview.due_now.amount_due == preview.recurring.amount_due
        assert preview.recurring.amount_due == plan.price_cents, (
            f"recurring.amount_due={preview.recurring.amount_due} != "
            f"plan price_cents={plan.price_cents}"
        )
        assert preview.recurring.lines, "recurring should carry the plan line"

        assert await _count_memberships(db_pool, member.member_id) == 0
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_preview_start_validates_plan_price(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        with pytest.raises((ValueError, Exception)):
            await memberships_service.preview_start(
                member_id=member.member_id,
                gym_id=gym_id,
                plan_id=uuid4(),
                price_id=uuid4(),
            )

        assert await _count_memberships(db_pool, member.member_id) == 0
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_preview_start_duplicate_raises(
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
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        with pytest.raises((ValueError, Exception)):
            await memberships_service.preview_start(
                member_id=member.member_id,
                gym_id=gym_id,
                plan_id=plan.plan_id,
                price_id=plan.price_id,
            )

        # Only the original membership row exists — preview didn't
        # insert anything.
        assert await _count_memberships(db_pool, member.member_id) == 1

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Cancel preview ──────────────────────────────────────────────────


async def test_preview_cancel_active(
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
        item_id = await _start_and_get_item_id(
            memberships_service,
            db_pool,
            member,
            gym_id,
            plan,
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

        preview = await memberships_service.preview_cancel(
            item_id,
            member.member_id,
        )

        # Cancelling the only item on the subscription drops the bucket
        # to zero — preview returns None for pure cancellations.
        assert preview is None

        # CRM row still active: cancel_date must be NULL.
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT cancel_date FROM member_memberships_unfiltered "
                    "WHERE item_id = :item_id"
                ),
                {"item_id": str(item_id)},
            )
            row = result.mappings().fetchone()

        assert row is not None
        assert row["cancel_date"] is None

        # Stripe sub must still be active and carry the plan's price.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        assert sub.status == "active"
        remaining_prices = {item.price.id for item in sub.items.data}
        assert plan.stripe_price_id in remaining_prices

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_preview_cancel_already_cancelled_returns_none(
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
        item_id = await _start_and_get_item_id(
            memberships_service,
            db_pool,
            member,
            gym_id,
            plan,
        )
        await memberships_service.cancel(item_id, member.member_id, idempotency_key=uuid4())

        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        preview = await memberships_service.preview_cancel(
            item_id,
            member.member_id,
        )
        assert preview is None

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Update price preview ────────────────────────────────────────────


async def test_preview_update_price(
    memberships_service,
    plans_service,
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
        item_id = await _start_and_get_item_id(
            memberships_service,
            db_pool,
            member,
            gym_id,
            plan,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        new_price = await plans_service.set_price(
            MembershipPlanPriceRequest(
                plan_id=plan.plan_id,
                gym_id=gym_id,
                price=8000,
            ),
        )

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        preview = await memberships_service.preview_update_price(
            item_id=item_id,
            member_id=member.member_id,
            prorate=False,
        )

        _assert_valid_split(preview)

        # CRM price_id must still be the ORIGINAL — preview does no writes.
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT price_id, total_price "
                    "FROM member_memberships_unfiltered "
                    "WHERE item_id = :item_id"
                ),
                {"item_id": str(item_id)},
            )
            row = result.mappings().fetchone()

        assert UUID(str(row["price_id"])) == plan.price_id, (
            "preview_update_price must not change the CRM price_id"
        )

        # Stripe subscription item must still be on the original price.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        remaining_prices = {item.price.id for item in sub.items.data}
        assert plan.stripe_price_id in remaining_prices, (
            "preview_update_price must not swap the Stripe price"
        )
        assert new_price.stripe_price_id not in remaining_prices, (
            "preview_update_price must not attach the new Stripe price"
        )

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)
