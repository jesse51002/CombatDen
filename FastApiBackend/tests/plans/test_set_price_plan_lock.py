"""Concurrency guard for ``plans_price.set_price`` (C-058 + orphan race).

Two concurrent ``set_price`` calls on the SAME plan could each read the active
price, deactivate it, insert a replacement, and call Stripe ``create_price``
before either committed; the loser's commit then hit the
``idx_max_one_active_price_per_plan`` <=1-active index and rolled back — but the
Stripe price it already created had no DB counterpart (a dangling orphan the
reconciler can't reap).

The fix takes a ``SELECT ... FOR UPDATE`` on the plan row as the FIRST statement
inside the txn, serializing same-plan ``set_price`` so the loser blocks until
the winner commits and never races to create a Stripe price.

This test proves the lock query is issued BEFORE Stripe ``create_price`` is
awaited. Pure unit test — the DB session and Stripe services are fakes/mocks, so
no live DB or Stripe connection is touched.
"""

from __future__ import annotations

from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.plans.plans_schema import MembershipPlanPriceRequest
from src.plans.service.plans_price import MembershipPlansPrice


class _FakeResult:
    """Minimal stand-in for a SQLAlchemy Result."""

    def __init__(self, row: dict | None) -> None:
        self._row = row

    def mappings(self) -> _FakeResult:
        return self

    def fetchone(self) -> dict | None:
        return self._row

    def one(self) -> dict:
        if self._row is None:
            raise AssertionError("expected a row")
        return self._row


class _RecordingSession:
    """Records the order of executes/commit; returns queued results in order.

    Each execute is tagged ``LOCK`` (its SQL contains ``FOR UPDATE``) or
    ``EXEC``; the raw SQL of every execute is kept in ``sqls`` so the test can
    assert the first statement really is the row lock.
    """

    def __init__(self, events: list[str], results: list[dict | None]) -> None:
        self._events = events
        self._results = [_FakeResult(r) for r in results]
        self.sqls: list[str] = []

    async def __aenter__(self) -> _RecordingSession:
        return self

    async def __aexit__(self, *exc: object) -> bool:
        return False

    async def execute(
        self, stmt: object, params: dict | None = None
    ) -> _FakeResult:
        sql = str(stmt)
        self.sqls.append(sql)
        self._events.append("LOCK" if "FOR UPDATE" in sql else "EXEC")
        return self._results.pop(0)

    async def commit(self) -> None:
        self._events.append("COMMIT")


def _price_row(stripe_price_id: str | None) -> dict:
    return {
        "price_id": uuid4(),
        "plan_id": uuid4(),
        "gym_id": uuid4(),
        "stripe_price_id": stripe_price_id,
        "price": 5000,
        "is_active": True,
        "created_at": datetime.now(UTC),
    }


@pytest.fixture
def price_service() -> MembershipPlansPrice:
    svc = MembershipPlansPrice(
        db_pool=MagicMock(),
        gym_stripe_service=MagicMock(),
        stripe_membership_service=MagicMock(),
        stripe_price_service=MagicMock(),
    )
    svc._get_plan = AsyncMock(
        return_value={"stripe_product_id": "prod_x", "plan_type": "recurring"},
    )
    svc._gym_stripe.get_stripe_account_id = AsyncMock(return_value="acct_x")
    svc._stripe_prices.set_product_default_price = AsyncMock()
    return svc


@pytest.mark.asyncio
async def test_set_price_locks_plan_row_before_stripe_create(
    price_service: MembershipPlansPrice,
) -> None:
    """The FOR UPDATE lock must be issued before Stripe create_price."""
    events: list[str] = []
    session = _RecordingSession(
        events,
        results=[
            None,  # lock row (result unused by set_price)
            _price_row("price_old"),  # deactivate_all -> old active row
            _price_row(None),  # insert new (NULL stripe id)
            _price_row("price_new"),  # set stripe_price_id
        ],
    )
    price_service._db_pool.session = MagicMock(return_value=session)

    async def _create(*_args: object, **_kwargs: object) -> SimpleNamespace:
        events.append("CREATE_PRICE")
        return SimpleNamespace(stripe_price_id="price_new")

    price_service._stripe_prices.create_price = AsyncMock(side_effect=_create)

    request = MembershipPlanPriceRequest(
        plan_id=uuid4(), gym_id=uuid4(), price=5000,
    )

    await price_service.set_price(request)

    # The very first statement on the session is the plan row lock...
    assert events[0] == "LOCK"
    assert "FOR UPDATE" in session.sqls[0]
    assert "membership_plans_unfiltered" in session.sqls[0]
    # ...and the lock is acquired before Stripe ever creates a price.
    price_service._stripe_prices.create_price.assert_awaited_once()
    assert events.index("LOCK") < events.index("CREATE_PRICE")
