"""Unit: ``_crm_insert`` returns one DISTINCT id per inserted row.

Regression for the same-plan collapse bug: multiple one-time rows on the same
(member, plan) — e.g. a 5-pack and a 10-pack of one plan at DIFFERENT prices —
were collapsed into a single ``item_id`` (a dict keyed on the non-unique
``(member_id, plan_id)``), so the preview's cleanup deleted only one of the
staged ``preview_add`` rows (leaking the rest, which then re-surfaced on every
preview) and the real start stamped only one row's writeback. The DB generates
a distinct ``item_id`` per row; ``_crm_insert`` must return ALL of them, in row
order, never deduped. (Buying N of ONE pack is a single row with quantity = N,
not N rows — so identical (member, plan, price) rows no longer occur; the
remaining same-(member, plan) case is distinct prices.) Faked session — no
real DB.
"""

from uuid import uuid4

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


async def test_crm_insert_keeps_one_id_per_same_plan_row():
    """3 same-(member, plan) rows at distinct prices -> 3 DISTINCT ids."""
    member, plan = uuid4(), uuid4()
    # Same (member, plan), three different prices (e.g. 5-pack / 10-pack /
    # 20-pack of one one-time plan), each its own quantity.
    rows = [_row(member, plan, uuid4(), q) for q in (1, 2, 3)]
    db_ids = [uuid4(), uuid4(), uuid4()]
    # The DB RETURNING: each row shares the SAME (member, plan) but carries its
    # OWN item_id. The extra (member, plan) keys make a re-collapse regression
    # fail loudly (it would dedupe to one id).
    pool = _FakePool([
        {"item_id": str(i), "member_id": str(member), "plan_id": str(plan)}
        for i in db_ids
    ])

    base = MemberMembershipsBase(pool, None, None)
    result = await base._crm_insert(rows)

    assert result == db_ids  # all three, in row order
    assert len(set(result)) == 3  # NOT collapsed to one
    # All 3 input rows were sent (same-plan rows are not deduped away), each
    # carrying its own quantity in order.
    assert len(pool.session_obj.params["member_ids"]) == 3
    assert pool.session_obj.params["quantities"] == [1, 2, 3]
