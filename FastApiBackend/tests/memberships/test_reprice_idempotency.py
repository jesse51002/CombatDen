"""Regression test for C-064: reprice must use a STABLE Stripe idempotency key.

The bug: ``reprice`` generated ``idempotency_key=uuid4()`` *inside* the
``sync_fn`` lambda, so every retry of the same logical converge re-keyed,
defeating Stripe idempotency (a retry could re-bill). The fix derives the key
once, outside the lambda, as a deterministic ``uuid5`` over the successor item
id — identical across retries of the same reprice, distinct between different
reprices.

Pure unit test: the reprice op is driven with every DB/lock/sync helper
stubbed, and a fake ``sync_or_revert`` invokes the captured ``sync_fn`` TWICE
(simulating two attempts of one logical op). The fix is proven by both
invocations carrying the SAME key; the old code would have produced two
different uuid4s.
"""

from contextlib import asynccontextmanager
from unittest.mock import AsyncMock
from uuid import UUID, uuid4, uuid5

import pytest
from schema.membership_plan import PlanType
from schema.task import ProrationBehavior

import src.memberships.service.memberships_reprice as reprice_mod
from src.memberships.service.memberships_reprice import (
    REPRICE_IDEMPOTENCY_NAMESPACE,
    MemberMembershipsReprice,
)


def _build_op(new_item_id: UUID, update_mock: AsyncMock):
    """An un-__init__'d reprice op with every collaborator stubbed."""
    op = object.__new__(MemberMembershipsReprice)

    @asynccontextmanager
    async def _lock(_keys):
        yield

    op._paying_lock = type("L", (), {"lock": staticmethod(_lock)})()
    op._resolve_payer = AsyncMock(return_value=uuid4())
    op._get_membership = AsyncMock(
        return_value={
            "gym_id": uuid4(),
            "plan_id": uuid4(),
            "price_id": uuid4(),  # != target, so not a no-op
            "plan_type": PlanType.recurring,
            "cancel_date": None,
            "end_date": None,
            "timezone": "America/Chicago",
        }
    )
    op._get_price_for_plan = AsyncMock(return_value={"price_id": uuid4()})
    op._pre_sync_payments = AsyncMock()
    op._write_db_phase = AsyncMock(return_value=new_item_id)
    op._revert_db_phase = AsyncMock()
    op._verify = AsyncMock(return_value=True)
    op._payment_sync = type(
        "PS", (), {"update_payments_recurring": update_mock}
    )()
    return op


@pytest.mark.asyncio
async def test_reprice_idempotency_key_stable_across_retries(monkeypatch):
    new_item_id = uuid4()
    update_mock = AsyncMock()
    op = _build_op(new_item_id, update_mock)

    captured_keys: list[UUID] = []

    async def _fake_sync_or_revert(*, sync_fn, **_kwargs):
        # Two attempts of the SAME logical converge.
        await sync_fn()
        await sync_fn()

    def _capture(payer_id, *, idempotency_key, proration_behavior):
        captured_keys.append(idempotency_key)
        return None

    update_mock.side_effect = _capture
    monkeypatch.setattr(reprice_mod, "sync_or_revert", _fake_sync_or_revert)

    target_price_id = uuid4()
    op._get_price_for_plan.return_value = {"price_id": target_price_id}

    returned = await op.reprice(
        member_id=uuid4(),
        old_item_id=uuid4(),
        proration_behavior=ProrationBehavior.prorate_to_anchor,
        target_price_id=target_price_id,
    )

    assert returned == new_item_id
    # Two attempts, ONE stable key (the bug would yield two distinct uuid4s).
    assert len(captured_keys) == 2
    assert captured_keys[0] == captured_keys[1]
    # And it is the deterministic uuid5 over the successor item id.
    expected = uuid5(REPRICE_IDEMPOTENCY_NAMESPACE, str(new_item_id))
    assert captured_keys[0] == expected


def test_different_reprices_do_not_collide():
    a, b = uuid4(), uuid4()
    key_a = uuid5(REPRICE_IDEMPOTENCY_NAMESPACE, str(a))
    key_b = uuid5(REPRICE_IDEMPOTENCY_NAMESPACE, str(b))
    assert key_a != key_b
