"""Regression test for C-086: the one-time membership start must be idempotent
on the DB insert, not only on the Stripe charge.

The bug: the start idempotency key keyed only the Stripe CHARGES. ``_insert_all``
/ ``_crm_insert`` inserted pending one-time rows with NO existing-row guard, and
one-time / trial rows are intentionally allowed to stack (only recurring is
blocked by a trigger). On a client RETRY with the SAME ``request.idempotency_key``
(the canonical "server finished but the 200 was lost" case) N duplicate pending
one-time rows were re-inserted; the charge dedup'd at Stripe (original invoice
returned) but the writeback then stamped the retry's N rows ``applied`` too ->
2N membership rows for one payment (double passes/credits).

The fix derives a DETERMINISTIC per-row ``idempotency_key`` for one-time / trial
rows — ``uuid5(request.idempotency_key, "<member_id>:<price_id>")`` — and a
partial unique index + ``ON CONFLICT (idempotency_key) DO NOTHING`` make a
retry's duplicate rows collide (and the caller reject the replay) instead of
stacking. Recurring rows keep a NULL key (the trigger guards them); preview rows
keep a NULL key (so a leaked preview row never collides with the real insert);
distinct purchases carry a different request key, so they still stack.

These tests are PURE UNIT tests over the key derivation in
``MemberMembershipsBase._build_pending_rows`` — no DB, Stripe, or network. The
DB-level ``ON CONFLICT`` dedup is an integration concern (real Supabase), written
below as a skipped test.
"""

from __future__ import annotations

from datetime import date
from uuid import UUID, uuid4, uuid5

import pytest
from schema.member_membership import StripeSyncStatus
from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401 — enables ``from schema.*`` imports
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from src.memberships.service.memberships_base import MemberMembershipsBase

START_DATE = date(2026, 1, 1)


def _base() -> MemberMembershipsBase:
    """Build the base service with no live deps.

    ``_build_pending_rows`` is pure (it touches neither the db_pool, the sync
    service, nor the gym-stripe service), so passing ``None`` for the three
    constructor deps is safe for this unit test.
    """
    return MemberMembershipsBase(None, None, None)  # type: ignore[arg-type]


def _plan_price(
    plan_id: UUID,
    plan_type: PlanType,
) -> dict:
    """A minimal plan/price row as ``_build_pending_rows`` consumes it."""
    is_recurring = plan_type == PlanType.recurring
    return {
        "plan_id": plan_id,
        "plan_type": plan_type.value,
        # recurring carries a 1-month span; one_time/trial carry none here.
        "duration_amount": 1 if is_recurring else None,
        "duration_unit": "month" if is_recurring else None,
        "price": 5000,
    }


def _request(
    idempotency_key: UUID,
    items: list[MemberMembershipsStartItem],
) -> MemberMembershipsStartRequest:
    return MemberMembershipsStartRequest(
        payer_member_id=uuid4(),
        gym_id=uuid4(),
        idempotency_key=idempotency_key,
        memberships=items,
    )


def test_one_time_key_is_deterministic_across_retries() -> None:
    """Same request (same key) built twice -> identical per-row key.

    This is what makes a retry collide on the partial unique index instead of
    inserting a fresh duplicate row.
    """
    member, price, plan = uuid4(), uuid4(), uuid4()
    req_key = uuid4()
    item = MemberMembershipsStartItem(member_id=member, price_id=price)
    plan_prices = {price: _plan_price(plan, PlanType.one_time)}
    base = _base()

    rows_a = base._build_pending_rows(
        _request(req_key, [item]), plan_prices, START_DATE,
    )
    rows_b = base._build_pending_rows(
        _request(req_key, [item]), plan_prices, START_DATE,
    )

    assert rows_a[0]["idempotency_key"] is not None
    assert rows_a[0]["idempotency_key"] == rows_b[0]["idempotency_key"]
    # And it is exactly the documented derivation.
    assert rows_a[0]["idempotency_key"] == uuid5(req_key, f"{member}:{price}")


def test_trial_rows_also_get_a_key() -> None:
    """Trial rows stack like one_time, so they need the same dedup guard."""
    member, price, plan = uuid4(), uuid4(), uuid4()
    req_key = uuid4()
    item = MemberMembershipsStartItem(member_id=member, price_id=price)
    plan_prices = {price: _plan_price(plan, PlanType.trial)}

    rows = _base()._build_pending_rows(
        _request(req_key, [item]), plan_prices, START_DATE,
    )

    assert rows[0]["idempotency_key"] == uuid5(req_key, f"{member}:{price}")


def test_key_differs_per_request_so_distinct_purchases_still_stack() -> None:
    """Different request keys -> different per-row keys -> no collision.

    Buying another pack of the same plan later is a SEPARATE request with its
    own ``idempotency_key``; its rows must NOT collide with the first purchase.
    """
    member, price, plan = uuid4(), uuid4(), uuid4()
    item = MemberMembershipsStartItem(member_id=member, price_id=price)
    plan_prices = {price: _plan_price(plan, PlanType.one_time)}
    base = _base()

    rows1 = base._build_pending_rows(
        _request(uuid4(), [item]), plan_prices, START_DATE,
    )
    rows2 = base._build_pending_rows(
        _request(uuid4(), [item]), plan_prices, START_DATE,
    )

    assert rows1[0]["idempotency_key"] != rows2[0]["idempotency_key"]


def test_key_differs_per_member_and_price_within_a_request() -> None:
    """Distinct (member, price) items in one request get distinct keys."""
    m1, m2 = uuid4(), uuid4()
    p1, p2 = uuid4(), uuid4()
    plan = uuid4()
    req_key = uuid4()
    items = [
        MemberMembershipsStartItem(member_id=m1, price_id=p1),
        MemberMembershipsStartItem(member_id=m1, price_id=p2),
        MemberMembershipsStartItem(member_id=m2, price_id=p1),
    ]
    plan_prices = {
        p1: _plan_price(plan, PlanType.one_time),
        p2: _plan_price(plan, PlanType.one_time),
    }

    rows = _base()._build_pending_rows(
        _request(req_key, items), plan_prices, START_DATE,
    )

    keys = [r["idempotency_key"] for r in rows]
    assert all(k is not None for k in keys)
    assert len(set(keys)) == len(keys)


def test_recurring_rows_have_null_key() -> None:
    """Recurring rows keep a NULL key — the no-active trigger guards them, and a
    NULL key is excluded from the partial unique index."""
    member, price, plan = uuid4(), uuid4(), uuid4()
    item = MemberMembershipsStartItem(member_id=member, price_id=price)
    plan_prices = {price: _plan_price(plan, PlanType.recurring)}

    rows = _base()._build_pending_rows(
        _request(uuid4(), [item]), plan_prices, START_DATE,
    )

    assert rows[0]["idempotency_key"] is None


def test_preview_rows_have_null_key() -> None:
    """Preview-staged (``preview_add``) rows keep a NULL key, so a leaked
    preview row can never collide with the real start's insert."""
    member, price, plan = uuid4(), uuid4(), uuid4()
    item = MemberMembershipsStartItem(member_id=member, price_id=price)
    plan_prices = {price: _plan_price(plan, PlanType.one_time)}

    rows = _base()._build_pending_rows(
        _request(uuid4(), [item]),
        plan_prices,
        START_DATE,
        sync_status=StripeSyncStatus.preview_add,
    )

    assert rows[0]["idempotency_key"] is None


def test_mixed_request_keys_only_one_time_rows() -> None:
    """In a mixed cart, only the one-time row carries a key; recurring is NULL.

    Both land in ONE multi-row insert, so the key array must line up per row.
    """
    member = uuid4()
    one_time_price, recurring_price = uuid4(), uuid4()
    one_time_plan, recurring_plan = uuid4(), uuid4()
    req_key = uuid4()
    items = [
        MemberMembershipsStartItem(member_id=member, price_id=one_time_price),
        MemberMembershipsStartItem(member_id=member, price_id=recurring_price),
    ]
    plan_prices = {
        one_time_price: _plan_price(one_time_plan, PlanType.one_time),
        recurring_price: _plan_price(recurring_plan, PlanType.recurring),
    }

    rows = _base()._build_pending_rows(
        _request(req_key, items), plan_prices, START_DATE,
    )

    assert rows[0]["idempotency_key"] == uuid5(
        req_key, f"{member}:{one_time_price}",
    )
    assert rows[1]["idempotency_key"] is None


@pytest.mark.skip(
    reason="integration: needs a real Supabase DB (FK rows + ON CONFLICT). "
    "C-086 DB-level dedup — not run in the unit suite.",
)
async def test_retry_insert_is_deduped_at_the_db(created, db_pool) -> None:  # type: ignore[no-untyped-def]
    """A second ``_crm_insert`` with the same per-row idempotency_key is dropped.

    Integration shape (requires the real shared local Supabase DB + the migrated
    ``idempotency_key`` column + partial unique index):

    1. Create a member + a ONE-TIME plan with an active price (data factory).
    2. Build a pending one-time row for that (member, price) and insert it via
       ``_crm_insert`` — succeeds, returns one item_id.
    3. Build the SAME row again (same member/price -> same deterministic
       idempotency_key) and insert it AGAIN — simulating the lost-200 retry.
       ``ON CONFLICT (idempotency_key) DO NOTHING`` drops it, so the RETURNING
       set is empty and ``_crm_insert`` raises the duplicate-replay RuntimeError.
    4. Assert exactly ONE ``member_memberships_unfiltered`` row exists for the
       (member, price) — never 2 — proving the 2N-rows bug is closed.

    Left as documentation of the DB-level contract; the partial unique index is
    also the backstop for two concurrent retries racing into the INSERT.
    """
    pytest.skip("integration placeholder — see docstring")
