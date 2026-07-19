"""Regression tests for G4 plan-billing fixes.

C-058 (``plans_price.set_price``): the old price must never be *durably*
deactivated until the replacement Stripe Price is confirmed — so on a Stripe
failure the transaction rolls back (commit is never called) and the plan keeps
its existing active price. Pre-fix, the deactivate+insert committed BEFORE the
Stripe create, so a Stripe failure left the plan with zero active prices.

C-059 (``plans_update.update_plan``): when the Stripe product is recreated
(the old one was gone), the new ``stripe_product_id`` must be persisted in the
same UPDATE transaction. Pre-fix the recreated id was returned but discarded.

These are pure unit tests: the DB session and Stripe services are fakes/mocks,
so no live DB or Stripe connection is touched.
"""

from __future__ import annotations

from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.plans.plans_schema import (
    MembershipPlanPriceRequest,
    MembershipPlanUpdateData,
    MembershipPlanUpdateRequest,
)
from src.plans.service.plans_price import MembershipPlansPrice
from src.plans.service.plans_update import MembershipPlansUpdate


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


class _FakeSession:
    """Records executes/commits; returns queued results in order."""

    def __init__(self, results: list[dict | None]) -> None:
        self._results = [_FakeResult(r) for r in results]
        self.executed: list[tuple[str, dict]] = []
        self.commit_called = 0

    async def __aenter__(self) -> _FakeSession:
        return self

    async def __aexit__(self, *exc: object) -> bool:
        return False

    async def execute(self, stmt: object, params: dict | None = None) -> _FakeResult:
        self.executed.append((str(stmt), params or {}))
        return self._results.pop(0)

    async def commit(self) -> None:
        self.commit_called += 1


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


# ── C-058 ──────────────────────────────────────────────────────


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


async def test_set_price_stripe_failure_does_not_commit_deactivation(
    price_service: MembershipPlansPrice,
) -> None:
    """C-058: Stripe failure must roll back — old price never deactivated."""
    session = _FakeSession(
        [
            None,  # FOR UPDATE plan lock (result unused)
            _price_row("price_old"),  # deactivate_all -> old row (still active)
            _price_row(None),  # insert new (NULL stripe id)
        ],
    )
    price_service._db_pool.session = MagicMock(return_value=session)
    price_service._stripe_prices.create_price = AsyncMock(
        side_effect=RuntimeError("stripe boom"),
    )

    request = MembershipPlanPriceRequest(
        plan_id=uuid4(), gym_id=uuid4(), price=5000,
    )

    with pytest.raises(RuntimeError, match="stripe boom"):
        await price_service.set_price(request)

    # Stripe was attempted...
    price_service._stripe_prices.create_price.assert_awaited_once()
    # ...but the deactivate+insert transaction was NEVER committed, so the old
    # price stays active on rollback (no zero-active-price window).
    assert session.commit_called == 0
    # And we never repointed the product default price to a non-existent price.
    price_service._stripe_prices.set_product_default_price.assert_not_awaited()


async def test_set_price_success_commits_after_stripe(
    price_service: MembershipPlansPrice,
) -> None:
    """Happy path: Stripe create precedes the single commit."""
    final_row = _price_row("price_new")
    session = _FakeSession(
        [
            None,  # FOR UPDATE plan lock (result unused)
            _price_row("price_old"),  # deactivate_all
            _price_row(None),  # insert
            final_row,  # set stripe_price_id
        ],
    )
    price_service._db_pool.session = MagicMock(return_value=session)
    price_service._stripe_prices.create_price = AsyncMock(
        return_value=SimpleNamespace(stripe_price_id="price_new"),
    )

    request = MembershipPlanPriceRequest(
        plan_id=uuid4(), gym_id=uuid4(), price=5000,
    )

    resp = await price_service.set_price(request)

    price_service._stripe_prices.create_price.assert_awaited_once()
    assert session.commit_called == 1
    assert resp.stripe_price_id == "price_new"


# ── C-059 ──────────────────────────────────────────────────────


def _existing_plan() -> dict:
    return {
        "plan_id": uuid4(),
        "gym_id": uuid4(),
        "plan_name": "Old Name",
        "image_url": "https://cdn.combatden.net/membership/presets/activity-01.jpg",
        "plan_type": "recurring",
        "class_count": None,
        "duration_amount": 1,
        "duration_unit": "month",
        "is_public": True,
        "stripe_product_id": "prod_old",
        "created_at": datetime.now(UTC),
    }


def _make_update_service(
    session: _FakeSession,
    recreated_product_id: str,
) -> MembershipPlansUpdate:
    svc = MembershipPlansUpdate(
        db_pool=MagicMock(),
        gym_stripe_service=MagicMock(),
        stripe_membership_service=MagicMock(),
        stripe_price_service=MagicMock(),
    )
    svc._db_pool.session = MagicMock(return_value=session)
    svc._get_plan = AsyncMock(return_value=_existing_plan())
    svc._gym_stripe.get_stripe_account_id = AsyncMock(return_value="acct_x")
    svc._update_or_recreate_product = AsyncMock(
        return_value=recreated_product_id,
    )
    return svc


async def test_update_persists_recreated_product_id() -> None:
    """C-059: a recreated product id is written back in the same txn."""
    # update_sql row (truthy), then the set_stripe_product_id execute row.
    session = _FakeSession([{"plan_id": "x"}, {"plan_id": "x"}])
    svc = _make_update_service(session, recreated_product_id="prod_new")

    request = MembershipPlanUpdateRequest(
        plan_id=uuid4(),
        gym_id=uuid4(),
        data=MembershipPlanUpdateData(plan_name="New Name"),
    )

    await svc.update_plan(request)

    # Two executes: the field UPDATE + the stripe_product_id writeback.
    assert len(session.executed) == 2
    assert session.commit_called == 1
    writeback_params = session.executed[1][1]
    assert writeback_params["stripe_product_id"] == "prod_new"


async def test_update_no_recreate_skips_product_writeback() -> None:
    """When the product was only updated (same id), no extra writeback runs."""
    session = _FakeSession([{"plan_id": "x"}])
    svc = _make_update_service(session, recreated_product_id="prod_old")

    request = MembershipPlanUpdateRequest(
        plan_id=uuid4(),
        gym_id=uuid4(),
        data=MembershipPlanUpdateData(plan_name="New Name"),
    )

    await svc.update_plan(request)

    # Only the field UPDATE ran — no stripe_product_id writeback.
    assert len(session.executed) == 1
    assert session.commit_called == 1
