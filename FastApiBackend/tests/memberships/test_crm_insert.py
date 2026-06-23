"""Unit: ``_crm_insert`` maps each DB-generated id back to its row.

Regression for the same-plan collapse bug: multiple one-time rows on the same
(member, plan) — e.g. a 5-pack and a 10-pack of one plan at DIFFERENT prices —
were collapsed into a single ``item_id`` (a dict keyed on the non-unique
``(member_id, plan_id)``), so the preview's cleanup deleted only one of the
staged ``preview_add`` rows (leaking the rest) and the real start stamped only
one row's writeback.

``_crm_insert`` maps each returned id back to its row by ``(member_id,
price_id)`` — unique within one request via the dedup — so the mapping is
ORDER-INDEPENDENT (it never trusts ``RETURNING`` to stream in insert order, a
PostgreSQL implementation detail, not a contract) and it fails loud rather than
silently collapse if two rows ever share the key. Faked session — no real DB.
"""

from uuid import uuid4

import pytest

import src.shared.db_schema_path  # noqa: F401
from src.memberships.service.memberships_base import MemberMembershipsBase


class _FakeResult:
    def __init__(self, mappings: list[dict]) -> None:
        self._mappings = mappings

    def mappings(self) -> list[dict]:
        return self._mappings


class _FakeSession:
    def __init__(self, mappings: list[dict]) -> None:
        self._mappings = mappings
        self.params: dict | None = None

    async def __aenter__(self) -> _FakeSession:
        return self

    async def __aexit__(self, *exc: object) -> bool:
        return False

    async def execute(self, _sql: object, params: dict) -> _FakeResult:
        self.params = params
        return _FakeResult(self._mappings)

    async def commit(self) -> None:
        return None


class _FakePool:
    def __init__(self, mappings: list[dict]) -> None:
        self.session_obj = _FakeSession(mappings)

    def session(self) -> _FakeSession:
        return self.session_obj


def _row(member: object, plan: object, price: object, quantity: int) -> dict:
    return {
        "member_id": member,
        "paid_by_member_id": member,
        "gym_id": uuid4(),
        "plan_id": plan,
        "price_id": price,
        "start_date": None,
        "end_date": None,
        "last_paid_date": None,
        "next_due_date": None,
        "stripe_item_id": None,
        "total_price": 2500,
        "quantity": quantity,
    }


async def test_crm_insert_maps_ids_by_member_price_in_row_order():
    """Ids map back by (member, price), so the result is in ROWS order even
    when the DB streams RETURNING in a DIFFERENT order."""
    member, plan = uuid4(), uuid4()
    # Same (member, plan), three DIFFERENT prices (a 5-pack / 10-pack / 20-pack
    # of one one-time plan); ids[i] belongs to rows[i] (prices[i]).
    prices = [uuid4(), uuid4(), uuid4()]
    rows = [_row(member, plan, prices[i], i + 1) for i in range(3)]
    ids = [uuid4(), uuid4(), uuid4()]

    # The fake RETURNING streams SHUFFLED (2, 0, 1) — each row carries its own
    # (member_id, price_id), so the mapping does not depend on this order.
    pool = _FakePool([
        {
            "item_id": str(ids[i]),
            "member_id": str(member),
            "price_id": str(prices[i]),
        }
        for i in (2, 0, 1)
    ])

    base = MemberMembershipsBase(pool, None, None)
    result = await base._crm_insert(rows)

    assert result == ids  # ROWS order, despite the shuffled RETURNING
    assert len(set(result)) == 3  # NOT collapsed to one
    assert pool.session_obj.params["quantities"] == [1, 2, 3]


async def test_crm_insert_raises_when_key_collapses():
    """Two rows sharing (member, price) (the dedup should prevent it) fail loud
    instead of silently collapsing onto one id."""
    member, plan, price = uuid4(), uuid4(), uuid4()
    rows = [_row(member, plan, price, 1), _row(member, plan, price, 1)]
    # The DB inserted 2 rows; both come back with the SAME (member, price).
    pool = _FakePool([
        {
            "item_id": str(uuid4()),
            "member_id": str(member),
            "price_id": str(price),
        }
        for _ in range(2)
    ])

    base = MemberMembershipsBase(pool, None, None)
    with pytest.raises(RuntimeError, match="collapsed"):
        await base._crm_insert(rows)
