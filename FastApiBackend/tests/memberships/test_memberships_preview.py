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
from schema.task import ProrationBehavior
from sqlalchemy import text

from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartPreviewResponse,
    MemberMembershipsStartRequest,
)
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


def _assert_valid_due_now_split(preview) -> None:
    """Shape checks for a cancel / update_price preview (the 2-way split).

    Those ops keep the ``DueNowVsRecurringPreview`` shape — only the START
    preview moved to the 3-way ``MemberMembershipsStartPreviewResponse``.
    """
    assert isinstance(preview, DueNowVsRecurringPreview)
    if preview.due_now is not None:
        _assert_valid_preview(preview.due_now)
    if preview.recurring is not None:
        _assert_valid_preview(preview.recurring)


def _assert_valid_split(preview) -> None:
    """Shape checks for a start preview response.

    Three halves: ``one_time`` (consolidated one-time invoice), ``due_now``
    (immediate recurring proration), ``recurring`` (steady-state cycle).
    """
    assert isinstance(preview, MemberMembershipsStartPreviewResponse)
    if preview.one_time is not None:
        _assert_valid_preview(preview.one_time)
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

        _assert_valid_split(preview)
        # A one-time purchase is entirely due now; nothing recurs.
        assert preview.one_time.amount_due == plan.price_cents, (
            f"one-time one_time.amount_due={preview.one_time.amount_due} != "
            f"plan price_cents={plan.price_cents}"
        )
        assert preview.recurring is None
        assert preview.due_now is None

        assert await _count_memberships(db_pool, member.member_id) == 0

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_preview_start_no_prorate_due_now_is_none(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """proration_behavior=no_charge start preview: due_now is None, recurring present.

    When not prorating, nothing extra is charged now. The engine's split
    reuses the steady-state recurring figure as ``due_now`` ("same thing
    twice"), but that amount is NOT actually due now — so the START preview
    suppresses it and reports ``due_now=None`` while ``recurring`` carries the
    full cycle. (The shared engine split / cancel / update_price previews keep
    the reuse; only the start preview overrides it.)
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
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.no_charge,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )

        _assert_valid_split(preview)
        assert preview.due_now is None, (
            "proration_behavior=no_charge start preview must report due_now=None"
        )
        assert preview.recurring is not None
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
                MemberMembershipsStartRequest(
                    payer_member_id=member.member_id,
                    gym_id=gym_id,
                    idempotency_key=uuid4(),
                    memberships=[
                        MemberMembershipsStartItem(
                            member_id=member.member_id,
                            price_id=uuid4(),
                        ),
                    ],
                )
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

        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        with pytest.raises((ValueError, Exception)):
            await memberships_service.preview_start(
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
