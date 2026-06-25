"""Integration tests for cancelling memberships.

Every test fetches the Stripe subscription (or confirms it was
deleted) after the cancel and asserts that no surprise charges
landed on the member's customer balance.
"""

from datetime import date
from uuid import UUID, uuid4

import pytest
import stripe
from sqlalchemy import text

from src.memberships.memberships_exceptions import PartialCancelError
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from src.memberships.service.memberships_cancel import (
    MemberMembershipsCancel,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import get_profile_stripe_ids
from tests.helpers.db_writes import authorize_payer
from tests.helpers.stripe_assertions import (
    assert_no_unexpected_charges,
    fetch_subscription,
    snapshot_billing_state,
)


async def _start_and_get_item_id(
    memberships_service,
    db_pool,
    member,
    gym_id,
    plan,
):
    """Start a membership and return the item_id."""
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


async def _item_id_for(db_pool, member_id: UUID, plan_id) -> UUID:
    """The membership item_id for a (member, plan) pair (unfiltered base)."""
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT item_id FROM member_memberships_unfiltered "
                "WHERE member_id = :m AND plan_id = :p"
            ),
            {"m": str(member_id), "p": str(plan_id)},
        )
        return UUID(str(result.mappings().one()["item_id"]))


async def _assert_sub_canceled_or_item_removed(
    stripe_client,
    connect_opts,
    stripe_sub_id: str,
    removed_stripe_price_id: str,
) -> None:
    """Confirm the cancel reached Stripe.

    For the only-item-on-the-sub case, cancelling the item usually
    deletes the whole subscription; retrieving it either returns
    status ``canceled`` or raises 404. For the multi-item case,
    the sub survives but the cancelled item's price is gone.
    """
    try:
        sub = await fetch_subscription(
            stripe_client,
            stripe_sub_id,
            connect_opts,
        )
    except stripe.InvalidRequestError as exc:
        # 404 — Stripe deleted the subscription when its last item
        # was removed. That's a valid cancel outcome.
        assert "No such subscription" in str(exc), f"Unexpected Stripe error after cancel: {exc}"
        return

    if sub.status == "canceled":
        return

    # Subscription still exists (e.g. had other family items) —
    # verify the cancelled price is no longer on any remaining item.
    remaining_prices = {item.price.id for item in sub.items.data}
    assert removed_stripe_price_id not in remaining_prices, (
        f"Cancelled price {removed_stripe_price_id} still present on "
        f"subscription {stripe_sub_id}: items={sorted(remaining_prices)}"
    )


async def test_cancel_active_membership(
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

        await memberships_service.cancel(item_id, member.member_id, idempotency_key=uuid4())

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
        assert row["cancel_date"] is not None

        await _assert_sub_canceled_or_item_removed(
            stripe_client,
            connect_opts,
            profile.stripe_sub_id_month,
            plan.stripe_price_id,
        )
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_cancel_already_cancelled_noop(
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

        await memberships_service.cancel(item_id, member.member_id, idempotency_key=uuid4())

        # Snapshot after the first cancel completes — the second
        # cancel is a pure CRM no-op and must not reach Stripe at all.
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.cancel(item_id, member.member_id, idempotency_key=uuid4())

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_cancel_one_of_shared_consolidated_line(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Regression: cancel ONE family member off a shared consolidated line.

    Two linked members on the same price share ONE Stripe item (quantity 2).
    Cancelling one must succeed (not revert), stamp the cancelled row
    ``deleted`` even though the shared line id stays live for the sibling,
    and leave the sibling billing on that line at quantity 1.
    """
    pm_id = await created.payment_method()
    payer = await created.member(gym_id, payment_method_id=pm_id)
    child = await created.member(gym_id)
    plan = await created.plan(gym_id)

    await authorize_payer(db_pool, child.member_id, payer.member_id)

    try:
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

        rows = {}
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id, member_id, stripe_item_id "
                    "FROM member_memberships_unfiltered "
                    "WHERE member_id IN (:payer_id, :child_id)"
                ),
                {
                    "payer_id": str(payer.member_id),
                    "child_id": str(child.member_id),
                },
            )
            for row in result.mappings().fetchall():
                rows[UUID(str(row["member_id"]))] = row

        # Consolidated: both rows carry the SAME Stripe line id.
        assert (
            rows[payer.member_id]["stripe_item_id"]
            == rows[child.member_id]["stripe_item_id"]
        )
        child_item_id = UUID(str(rows[child.member_id]["item_id"]))
        payer_item_id = UUID(str(rows[payer.member_id]["item_id"]))

        profile = await get_profile_stripe_ids(
            db_pool,
            payer.member_id,
            gym_id,
        )
        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        # Must succeed — the old live-line diff never stamped a row
        # removed from a shared line, so the verify reverted the cancel.
        await memberships_service.cancel(
            child_item_id,
            child.member_id,
            idempotency_key=uuid4(),
        )

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id, cancel_date, "
                    "stripe_sync_status::text AS status "
                    "FROM member_memberships_unfiltered "
                    "WHERE item_id IN (:child_item, :payer_item)"
                ),
                {
                    "child_item": str(child_item_id),
                    "payer_item": str(payer_item_id),
                },
            )
            by_item = {
                UUID(str(r["item_id"])): r
                for r in result.mappings().fetchall()
            }

        assert by_item[child_item_id]["cancel_date"] is not None
        assert by_item[child_item_id]["status"] == "deleted"
        assert by_item[payer_item_id]["cancel_date"] is None
        assert by_item[payer_item_id]["status"] == "applied"

        # Sibling keeps billing on the shared line at quantity 1.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        qty_by_price = {
            item.price.id: item.quantity for item in sub.items.data
        }
        assert qty_by_price.get(plan.stripe_price_id) == 1

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, payer.member_id)


async def test_payer_cancels_membership_they_fund_for_child(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """The PAYER (not the subject) cancels a membership they fund for a child.

    Payer A is authorized to pay for child B and funds B's recurring
    membership (B is the subject, A is ``paid_by_member_id``, the sub lives on
    A's customer). The actor on both the preview and the cancel is A — the
    PAYER, not the subject. Regression for the subject-vs-actor keying bug:
    keying per-item ops by the actor A would read nothing for B's row and the
    preview would error ("could not load cancellation preview").

    - ``preview_cancel([B_item], member_id=A)`` returns ONE
      ``PayerInvoiceChange`` for payer A, ``affected=True`` (it does NOT error).
    - ``cancel([B_item], member_id=A)`` cancels B's membership: cancel_date set
      on B's row, the line removed from A's sub, the row stamped ``deleted``.
    """
    pm_id = await created.payment_method()
    payer = await created.member(gym_id, payment_method_id=pm_id)
    child = await created.member(gym_id)
    plan = await created.plan(gym_id)

    await authorize_payer(db_pool, child.member_id, payer.member_id)

    try:
        # Payer A funds child B's recurring membership (B is the subject).
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=payer.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=child.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )

        child_item_id = await _item_id_for(
            db_pool, child.member_id, plan.plan_id
        )

        # The subscription lives on the PAYER's customer (A is billed).
        profile = await get_profile_stripe_ids(
            db_pool,
            payer.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        # Preview as the PAYER (actor = A, not subject B) — must NOT error.
        changes = await memberships_service.preview_cancel(
            child_item_id,
            payer.member_id,
        )
        assert len(changes) == 1
        change = changes[0]
        assert str(change.payer_member_id) == str(payer.member_id)
        assert change.affected is True

        # The preview must not have mutated the CRM row.
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT cancel_date FROM member_memberships_unfiltered "
                    "WHERE item_id = :item_id"
                ),
                {"item_id": str(child_item_id)},
            )
            assert result.mappings().one()["cancel_date"] is None

        # Cancel as the PAYER (actor = A, not subject B).
        await memberships_service.cancel(
            child_item_id,
            payer.member_id,
            idempotency_key=uuid4(),
        )

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT cancel_date, stripe_sync_status::text AS status "
                    "FROM member_memberships_unfiltered "
                    "WHERE item_id = :item_id"
                ),
                {"item_id": str(child_item_id)},
            )
            row = result.mappings().one()

        assert row["cancel_date"] is not None
        assert row["status"] == "deleted"

        await _assert_sub_canceled_or_item_removed(
            stripe_client,
            connect_opts,
            profile.stripe_sub_id_month,
            plan.stripe_price_id,
        )
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, payer.member_id)


async def test_cancel_one_time_raises(
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
        plan_name="One-Time Cancel Test",
        price_cents=2000,
    )

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

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id FROM member_memberships "
                    "WHERE member_id = :id AND plan_id = :plan_id"
                ),
                {"id": str(member.member_id), "plan_id": str(plan.plan_id)},
            )
            row = result.mappings().fetchone()
        item_id = UUID(str(row["item_id"]))

        # Snapshot after start completes — the failed cancel must
        # not create any Stripe side effects.
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

        with pytest.raises((ValueError, Exception)):
            await memberships_service.cancel(item_id, member.member_id, idempotency_key=uuid4())

        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_multi_payer_cancel_partial_failure_is_payer_atomic(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A multi-payer cancel where the SECOND payer's converge fails.

    One member M holds two recurring memberships funded by two different payers
    (M self-pays plan A; payer P pays plan B for M). Cancelling both at once
    processes one payer at a time: when P's converge fails AFTER M's converge
    already succeeded, the batch is partial and payer-atomic —

    - M's membership (the payer that DID converge) stays cancelled.
    - P's membership (the FAILED payer) is reverted: its ``cancel_date`` is
      cleared, so no stale cancel_date is left behind a missing Stripe cancel.
    - a ``PartialCancelError`` is raised carrying the succeeded/failed map.
    """
    pm_m = await created.payment_method()
    pm_p = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_m)
    payer = await created.member(gym_id, payment_method_id=pm_p)
    plan_self = await created.plan(gym_id)
    plan_by_p = await created.plan(gym_id)

    await authorize_payer(db_pool, member.member_id, payer.member_id)

    try:
        # M self-pays plan_self.
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=plan_self.price_id,
                    ),
                ],
            )
        )
        # P pays plan_by_p for M.
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=payer.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=plan_by_p.price_id,
                    ),
                ],
            )
        )

        item_self = await _item_id_for(db_pool, member.member_id, plan_self.plan_id)
        item_by_p = await _item_id_for(db_pool, member.member_id, plan_by_p.plan_id)

        # Force payer P's converge to fail (after M's succeeds). Patch the
        # underlying sync so P's converge raises — that drives the real
        # sync_or_revert path, which reverts P's cancel_date. M's converge runs
        # for real. The cancel processes payers in batch (item-id) order, so
        # list M's item first → M succeeds, then P fails.
        cancel_svc = memberships_service._cancel
        original_sync = cancel_svc._payment_sync.update_payments_recurring

        async def _flaky_sync(payer_member_id, **kwargs):
            if payer_member_id == payer.member_id:
                raise RuntimeError("forced P converge failure")
            return await original_sync(payer_member_id, **kwargs)

        cancel_svc._payment_sync.update_payments_recurring = _flaky_sync
        try:
            with pytest.raises(PartialCancelError) as exc_info:
                await memberships_service.cancel_many(
                    [item_self, item_by_p],
                    member.member_id,
                    uuid4(),
                )
        finally:
            cancel_svc._payment_sync.update_payments_recurring = original_sync

        err = exc_info.value
        assert item_self in err.succeeded
        assert err.failed_payer_id == payer.member_id
        assert err.failed_item_ids == [item_by_p]

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT item_id, cancel_date, "
                    "stripe_sync_status::text AS status "
                    "FROM member_memberships_unfiltered "
                    "WHERE item_id IN (:a, :b)"
                ),
                {"a": str(item_self), "b": str(item_by_p)},
            )
            by_item = {
                UUID(str(r["item_id"])): r
                for r in result.mappings().fetchall()
            }

        # M's membership (succeeded payer) is cancelled and deleted.
        assert by_item[item_self]["cancel_date"] is not None
        assert by_item[item_self]["status"] == "deleted"
        # P's membership (failed payer) was reverted: no stale cancel_date,
        # still applied (the converge that would have removed it never landed).
        assert by_item[item_by_p]["cancel_date"] is None
        assert by_item[item_by_p]["status"] == "applied"
    finally:
        await delete_member_data(db_pool, member.member_id)
        await delete_member_data(db_pool, payer.member_id)


async def test_remove_authorization_threads_caller_idempotency_key(
    memberships_service,
    db_pool,
    gym_id,
    created,
):
    """remove_authorization passes the CALLER's key into the cancel path.

    Guards finding #2: the cascading cancel must use the stable,
    caller-supplied idempotency key (so a retry dedups at Stripe), NOT a fresh
    ``uuid4()`` minted per call. We spy on the cancel sub-service to capture the
    key it receives and assert it is exactly the one the caller passed.
    """
    pm_p = await created.payment_method()
    payer = await created.member(gym_id, payment_method_id=pm_p)
    member = await created.member(gym_id)
    plan = await created.plan(gym_id)
    await authorize_payer(db_pool, member.member_id, payer.member_id)

    try:
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=payer.member_id,
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

        caller_key = uuid4()
        seen: dict[str, UUID] = {}
        cancel_svc = memberships_service._cancel
        original_cancel = cancel_svc.cancel

        async def _spy_cancel(item_ids, member_id, idempotency_key):
            seen["key"] = idempotency_key
            return await original_cancel(item_ids, member_id, idempotency_key)

        cancel_svc.cancel = _spy_cancel
        try:
            await memberships_service.remove_authorization(
                member.member_id,
                payer.member_id,
                caller_key,
            )
        finally:
            cancel_svc.cancel = original_cancel

        assert seen["key"] == caller_key
    finally:
        await delete_member_data(db_pool, member.member_id)
        await delete_member_data(db_pool, payer.member_id)


async def test_end_one_time_membership(
    memberships_service,
    db_pool,
    gym_id,
    created,
):
    """Ending a one-time membership sets end_date=today → status 'ended'.

    A one-time pack is a terminal invoice with no subscription line, so this is
    a pure DB date write — no Stripe action.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        plan_name="One-Time End Test",
        price_cents=2000,
    )
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
        async with db_pool.session() as session:
            row = (
                await session.execute(
                    text(
                        "SELECT item_id FROM member_memberships "
                        "WHERE member_id = :id AND plan_id = :plan_id"
                    ),
                    {"id": str(member.member_id), "plan_id": str(plan.plan_id)},
                )
            ).mappings().fetchone()
        item_id = UUID(str(row["item_id"]))

        end_date = await memberships_service.end_one_time(
            item_id, member.member_id,
        )
        assert end_date is not None

        async with db_pool.session() as session:
            persisted = (
                await session.execute(
                    text(
                        "SELECT end_date FROM member_memberships_unfiltered "
                        "WHERE item_id = :id"
                    ),
                    {"id": str(item_id)},
                )
            ).mappings().one()
            status_row = (
                await session.execute(
                    text(
                        "SELECT status FROM member_memberships_status "
                        "WHERE item_id = :id"
                    ),
                    {"id": str(item_id)},
                )
            ).mappings().one()
        assert persisted["end_date"] == end_date
        assert status_row["status"] == "ended"
    finally:
        await delete_member_data(db_pool, member.member_id)


def test_end_one_time_rejects_recurring_unit():
    """The end-one-time guard refuses a RECURRING membership (use cancel)."""
    row = {
        "plan_type": "recurring",
        "cancel_date": None,
        "end_date": None,
        "timezone": "America/Chicago",
    }
    with pytest.raises(ValueError, match="recurring"):
        MemberMembershipsCancel._validate_end_one_time(row, uuid4(), uuid4())


def test_end_one_time_rejects_already_ended_unit():
    """The end-one-time guard refuses an already-ended membership."""
    row = {
        "plan_type": "one_time",
        "cancel_date": None,
        "end_date": date(2020, 1, 1),
        "timezone": "America/Chicago",
    }
    with pytest.raises(ValueError, match="already ended"):
        MemberMembershipsCancel._validate_end_one_time(row, uuid4(), uuid4())
