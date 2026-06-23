"""Unit: ``_crm_insert`` returns one DISTINCT id per inserted row.

Regression for the stacked-pack bug: N identical one-time items on the same
(member, plan) were collapsed into a single ``item_id`` (a dict keyed on the
non-unique ``(member_id, plan_id)``), so the preview's cleanup deleted only one
of the N staged ``preview_add`` rows (leaking the rest, which then re-surfaced
on every preview) and the real start stamped only one row's writeback. The DB
generates a distinct ``item_id`` per row; ``_crm_insert`` must return ALL of
them, in row order, never deduped. Faked session — no real DB.
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


def _row(member: object, plan: object, price: object) -> dict:
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
    }


async def test_crm_insert_keeps_one_id_per_stacked_row():
    """3 identical (member, plan, price) rows -> 3 DISTINCT ids, in order."""
    member, plan, price = uuid4(), uuid4(), uuid4()
    rows = [_row(member, plan, price) for _ in range(3)]
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
    # All 3 input rows were sent (the duplicates are not deduped away).
    assert len(pool.session_obj.params["member_ids"]) == 3
