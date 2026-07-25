"""The membership start must be idempotent on the DB INSERT, not only on the
Stripe charge — for EVERY plan type.

The original bug: the start idempotency key keyed only the Stripe CHARGES.
``_insert_all`` / ``_crm_insert`` inserted pending one-time rows with NO
existing-row guard, and one-time / trial rows are intentionally allowed to stack.
On a client RETRY with the SAME ``request.idempotency_key`` (the canonical
"server finished but the 200 was lost" case) N duplicate pending one-time rows
were re-inserted; the charge dedup'd at Stripe (original invoice returned) but
the writeback then stamped the retry's N rows ``applied`` too -> 2N membership
rows for one payment (double passes/credits).

The fix derives a DETERMINISTIC per-row ``idempotency_key`` —
``uuid5(request.idempotency_key, "<member_id>:<price_id>")`` — and a partial
unique index + ``ON CONFLICT (idempotency_key) DO NOTHING`` make a retry's
duplicate rows collide (and the caller reject the replay) instead of stacking.

RECURRING rows carry the key too. They were originally left NULL on the grounds
that ``trg_recurring_no_active_memberships`` already blocks a duplicate — but
that trigger is a ``SELECT COUNT`` inside a ``BEFORE INSERT`` trigger, i.e.
correct but NOT race-safe: two concurrent re-fires (a kiosk double-tap) each read
before the other commits, both pass, and both insert. Two rows means two
subscription line items and a double bill. The partial unique index is the only
guard that serializes that race, so it has to cover recurring rows as well.
Preview (``preview_add``) rows still keep a NULL key, so a leaked preview row can
never collide with a real insert; distinct purchases carry a different request
key, so they still insert normally.

These tests are PURE UNIT tests over the key derivation in
``MemberMembershipsBase._build_pending_rows`` — no DB, Stripe, or network. The
DB-level ``ON CONFLICT`` dedup (including the concurrent double-fire) is covered
against the real database in ``test_recurring_insert_idempotency.py``.
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


def test_recurring_rows_also_get_a_key() -> None:
    """Recurring rows carry the same deterministic key.

    ``trg_recurring_no_active_memberships`` is a ``SELECT COUNT`` in a
    ``BEFORE INSERT`` trigger — two concurrent re-fires both read before either
    commits, so both pass it and both insert. The partial unique index is the
    only race-safe guard, so recurring rows have to be keyed for it to apply.
    """
    member, price, plan = uuid4(), uuid4(), uuid4()
    req_key = uuid4()
    item = MemberMembershipsStartItem(member_id=member, price_id=price)
    plan_prices = {price: _plan_price(plan, PlanType.recurring)}

    rows = _base()._build_pending_rows(
        _request(req_key, [item]), plan_prices, START_DATE,
    )

    assert rows[0]["idempotency_key"] == uuid5(req_key, f"{member}:{price}")


def test_recurring_key_is_deterministic_across_retries() -> None:
    """A re-fired recurring-only cart reproduces the SAME per-row key.

    This is what makes the re-fire collide on the partial unique index — the
    whole point of keying recurring rows.
    """
    member, price, plan = uuid4(), uuid4(), uuid4()
    req_key = uuid4()
    item = MemberMembershipsStartItem(member_id=member, price_id=price)
    plan_prices = {price: _plan_price(plan, PlanType.recurring)}
    base = _base()

    rows_a = base._build_pending_rows(
        _request(req_key, [item]), plan_prices, START_DATE,
    )
    rows_b = base._build_pending_rows(
        _request(req_key, [item]), plan_prices, START_DATE,
    )

    assert rows_a[0]["idempotency_key"] == rows_b[0]["idempotency_key"]


def test_recurring_key_differs_per_request() -> None:
    """A genuinely separate recurring purchase (new request key) does not
    collide — re-subscribing after a cancel must still insert."""
    member, price, plan = uuid4(), uuid4(), uuid4()
    item = MemberMembershipsStartItem(member_id=member, price_id=price)
    plan_prices = {price: _plan_price(plan, PlanType.recurring)}
    base = _base()

    rows1 = base._build_pending_rows(
        _request(uuid4(), [item]), plan_prices, START_DATE,
    )
    rows2 = base._build_pending_rows(
        _request(uuid4(), [item]), plan_prices, START_DATE,
    )

    assert rows1[0]["idempotency_key"] != rows2[0]["idempotency_key"]


@pytest.mark.parametrize(
    "plan_type",
    [PlanType.one_time, PlanType.trial, PlanType.recurring],
)
def test_preview_rows_have_null_key(plan_type: PlanType) -> None:
    """Preview-staged (``preview_add``) rows keep a NULL key for EVERY plan
    type, so a leaked preview row can never collide with the real start's
    insert."""
    member, price, plan = uuid4(), uuid4(), uuid4()
    item = MemberMembershipsStartItem(member_id=member, price_id=price)
    plan_prices = {price: _plan_price(plan, plan_type)}

    rows = _base()._build_pending_rows(
        _request(uuid4(), [item]),
        plan_prices,
        START_DATE,
        sync_status=StripeSyncStatus.preview_add,
    )

    assert rows[0]["idempotency_key"] is None


def test_mixed_cart_keys_every_row() -> None:
    """In a mixed cart BOTH rows carry their own key — one-time and recurring.

    Both land in ONE multi-row insert, so the key array must line up per row,
    and a re-fire must drop BOTH halves (any shortfall rejects the whole
    request, which is what keeps a mixed cart from half-applying).
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
    assert rows[1]["idempotency_key"] == uuid5(
        req_key, f"{member}:{recurring_price}",
    )
    assert rows[0]["idempotency_key"] != rows[1]["idempotency_key"]


# The DB-level ``ON CONFLICT`` dedup — including the concurrent double-fire the
# recurring key exists for — is covered for real in
# ``tests/memberships/test_recurring_insert_idempotency.py``.
