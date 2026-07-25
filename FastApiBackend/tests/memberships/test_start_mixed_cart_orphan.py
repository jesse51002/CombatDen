"""Integration: a NON-card failure on the ONE-TIME leg of a MIXED cart must not
strand the request's RECURRING rows as never-billed ``not_added`` ghosts.

``start`` commits EVERY row of the request in ONE insert (``_insert_all``), then
charges the one-time group, then converges the recurring group. When the
one-time charge fails for a NON-card reason its arm cleans up **its own** group
and re-raises — so the recurring rows used to survive as committed,
never-charged ``not_added`` rows still holding their deterministic idempotency
keys, and the member was locked out of that recurring plan until the
reconciler's orphan sweep happened to run.

EVERY retry died the same way, whatever idempotency key it carried:
``trg_recurring_no_active_memberships`` is a ``BEFORE INSERT`` trigger that
counts an uncancelled ``not_added`` row as active (it skips only
``preview_add``), so the ghost rejected the replacement row with a raw DB error
— the router's 500, over a charge that never happened. It fires before the
INSERT's ``ON CONFLICT (idempotency_key) DO NOTHING`` is resolved, so a same-key
retry never even reached the ``RETURNING``-shortfall check that would have
called it a 409 replay. And nothing could explain the 500 to staff, because the
blocking row is invisible: validation reads ``member_memberships_status``, a
view that HIDES ``not_added``, so the request cleared every check and then died
on a membership nobody could see.

Both tests read the UNFILTERED base (``member_memberships_unfiltered``). The
filtered ``member_memberships`` view hides ``not_added``, so a test reading the
view would pass against the bug.

The failure is injected on ``PaymentSyncOneTime.charge_one_time`` as a
``stripe.APIConnectionError`` — definitively NOT a ``CardError``, so it takes
the system-failure arm under test and not the decline path (which is data, and
is covered in ``test_start_card_decline.py``). It raises BEFORE any Stripe call,
so nothing is collected on either leg: the recurring rows are provably un-billed
and the 500's "nothing created and nothing charged" contract still holds.

The cart is ``paid_with_cash=True`` so the retry leg can complete without the
card being the variable under test.
"""

from uuid import UUID, uuid4

import pytest
import stripe
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from src.sync.service.sync_one_time import PaymentSyncOneTime
from tests.helpers.cleanup import delete_member_data


async def _membership_rows(db_pool, member_id) -> list[dict]:
    """Every membership row for a member, read from the UNFILTERED base.

    The filtered view hides ``not_added``, so the ghost row this file is about
    is invisible there — reading the base is what makes the assertion real.
    """
    sql = """
        SELECT plan_id,
               stripe_item_id,
               stripe_sync_status::text AS status
        FROM member_memberships_unfiltered
        WHERE member_id = :member_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(sql), {"member_id": str(member_id)}
        )
        return [
            {
                "plan_id": UUID(str(row["plan_id"])),
                "stripe_item_id": row["stripe_item_id"],
                "status": row["status"],
            }
            for row in result.mappings().all()
        ]


def _fail_one_time_charge_once(monkeypatch) -> None:
    """Make the FIRST ``charge_one_time`` blow up non-card; later calls are real.

    One patch covers both phases of the retry test: attempt 1 hits the
    system-failure arm, attempt 2 charges for real.
    """
    original = PaymentSyncOneTime.charge_one_time
    calls = {"n": 0}

    async def _boom_first_then_real(self, *args, **kwargs):
        calls["n"] += 1
        if calls["n"] == 1:
            raise stripe.APIConnectionError(
                "network died before the one-time invoice was created",
            )
        return await original(self, *args, **kwargs)

    monkeypatch.setattr(
        PaymentSyncOneTime, "charge_one_time", _boom_first_then_real
    )


def _mixed_cart(
    member_id,
    gym_id,
    one_time_price_id,
    recurring_price_id,
    key,
) -> MemberMembershipsStartRequest:
    """A one-time + recurring cart for one self-paying member, settled in cash."""
    return MemberMembershipsStartRequest(
        payer_member_id=member_id,
        gym_id=gym_id,
        idempotency_key=key,
        paid_with_cash=True,
        memberships=[
            MemberMembershipsStartItem(
                member_id=member_id, price_id=one_time_price_id,
            ),
            MemberMembershipsStartItem(
                member_id=member_id, price_id=recurring_price_id,
            ),
        ],
    )


@pytest.mark.timeout(180)
async def test_one_time_system_failure_leaves_no_recurring_ghost(
    memberships_service,
    db_pool,
    gym_id,
    created,
    monkeypatch,
):
    """The recurring rows of a mixed cart are deleted when the one-time leg
    fails for a NON-card reason.

    Nothing was collected anywhere (the injected failure precedes every Stripe
    call) and the recurring converge never ran, so those rows carry no
    ``stripe_item_id`` and no subscription item — they are provably un-billed
    and must not be committed as ghosts. ``start`` still raises, so the router
    still answers a non-retryable 500.
    """
    pm_id = await created.payment_method()
    member = await created.member(
        gym_id,
        first_name="MixedCart",
        last_name="Orphan",
        payment_method_id=pm_id,
    )
    one_time_plan = await created.plan(
        gym_id,
        plan_type="one_time",
        plan_name="Orphan Guard Pack",
        price_cents=2500,
        duration_amount=1,
        duration_unit="month",
    )
    recurring_plan = await created.plan(
        gym_id, plan_name="Orphan Guard Monthly", price_cents=5000,
    )

    _fail_one_time_charge_once(monkeypatch)

    try:
        # A system failure is still a raise (-> the router's 500): the fix
        # changes what is left behind, never how the request answers.
        with pytest.raises(stripe.APIConnectionError):
            await memberships_service.start(
                _mixed_cart(
                    member.member_id,
                    gym_id,
                    one_time_plan.price_id,
                    recurring_plan.price_id,
                    uuid4(),
                )
            )

        rows = await _membership_rows(db_pool, member.member_id)

        # The regression: the RECURRING row survived as a committed, un-billed
        # `not_added` ghost holding its idempotency key.
        ghosts = [
            row
            for row in rows
            if row["status"] == "not_added"
            and row["plan_id"] == recurring_plan.plan_id
        ]
        assert ghosts == [], (
            "the recurring rows are un-billed here (their converge never ran), "
            "so a not_added survivor is a ghost that blocks the member from "
            f"ever buying this plan again: {ghosts}"
        )
        # And nothing else half-committed either — the one-time arm cleans its
        # own group, so the whole request leaves no row behind.
        assert rows == [], f"the failed start must leave no rows at all: {rows}"
    finally:
        await delete_member_data(db_pool, member.member_id)


@pytest.mark.timeout(300)
async def test_after_one_time_system_failure_a_same_key_retry_succeeds(
    memberships_service,
    db_pool,
    gym_id,
    created,
    monkeypatch,
):
    """The consequence the ghost caused: the member could never be re-sold.

    Re-firing the IDENTICAL request (same ``idempotency_key``) after the
    one-time leg's system failure must go through and bill once. With the ghost
    recurring row present, this exact retry died inside ``_insert_all`` on
    ``trg_recurring_no_active_memberships`` — an opaque 500 over a charge that
    never happened, and unfixable from the front desk, since nothing was ever
    collected to reconcile against and the blocking row is hidden from every
    read the CRM makes. A new key changed nothing: the trigger keys on
    (member, gym, plan), not on the idempotency key.
    """
    pm_id = await created.payment_method()
    member = await created.member(
        gym_id,
        first_name="MixedCart",
        last_name="Retry",
        payment_method_id=pm_id,
    )
    one_time_plan = await created.plan(
        gym_id,
        plan_type="one_time",
        plan_name="Retry Guard Pack",
        price_cents=2500,
        duration_amount=1,
        duration_unit="month",
    )
    recurring_plan = await created.plan(
        gym_id, plan_name="Retry Guard Monthly", price_cents=5000,
    )

    _fail_one_time_charge_once(monkeypatch)
    key = uuid4()

    try:
        # Attempt 1: the one-time leg dies non-card -> 500, nothing written.
        with pytest.raises(stripe.APIConnectionError):
            await memberships_service.start(
                _mixed_cart(
                    member.member_id,
                    gym_id,
                    one_time_plan.price_id,
                    recurring_plan.price_id,
                    key,
                )
            )
        assert await _membership_rows(db_pool, member.member_id) == []

        # Attempt 2: the SAME key, nothing patched any more. A surviving ghost
        # would instead blow the insert up on
        # `trg_recurring_no_active_memberships` (the router's 500).
        response = await memberships_service.start(
            _mixed_cart(
                member.member_id,
                gym_id,
                one_time_plan.price_id,
                recurring_plan.price_id,
                key,
            )
        )

        assert [item.status.value for item in response.results] == [
            "created",
            "created",
        ], f"the retry must go through: {response.results}"
        assert response.charge_count == 2
        assert response.multiple_charges is True

        # Billed exactly once: one row per plan, both confirmed on Stripe.
        rows = await _membership_rows(db_pool, member.member_id)
        assert len(rows) == 2, f"expected one row per plan, got {rows}"
        assert {row["plan_id"] for row in rows} == {
            one_time_plan.plan_id,
            recurring_plan.plan_id,
        }
        assert all(row["status"] == "applied" for row in rows), rows
        assert all(row["stripe_item_id"] is not None for row in rows), rows
    finally:
        await delete_member_data(db_pool, member.member_id)
