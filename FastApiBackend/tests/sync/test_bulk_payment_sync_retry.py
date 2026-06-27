"""Unit tests for ``bulk_payment_sync``'s failure-retry (pure, mocked).

The batch syncs each member under its family lock; members that fail a pass (most
often a transient ``LockBusyError``) are collected and retried in a loop, up to
``settings.bulk_sync_max_retries`` passes, each after a ``settings.bulk_sync_retry_delay_seconds``
wait. A member still failing once the retries are exhausted is logged, never
raised. These tests mock the resolver / lock / per-member sync so no DB or Stripe
is touched.
"""

from contextlib import asynccontextmanager
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import src.shared.db_schema_path  # noqa: F401
from src.core.config import settings
from src.shared.paying_member_lock import LockBusyError
from src.sync.service import (
    sync_service as mod,
)
from src.sync.service.sync_service import (
    PaymentSyncService,
)


def _build_service() -> PaymentSyncService:
    """A service whose deps are mocks; bulk only touches the paying-member lock
    and ``update_payments_recurring`` (patched per test)."""
    paying_lock = MagicMock()

    @asynccontextmanager
    async def _lock(member_ids: list[UUID]):
        yield

    paying_lock.lock = _lock

    return PaymentSyncService(
        db_pool=MagicMock(),
        subscription_service=MagicMock(),
        payer_resolver=MagicMock(),
        builder=MagicMock(),
        paying_lock=paying_lock,
    )


async def test_all_succeed_no_retry(monkeypatch) -> None:
    svc = _build_service()
    sleep = AsyncMock()
    monkeypatch.setattr(mod.asyncio, "sleep", sleep)
    synced: list[UUID] = []

    async def ok(member_id, idempotency_key) -> None:
        synced.append(member_id)

    svc.update_payments_recurring = ok
    ids = [uuid4(), uuid4(), uuid4()]

    await svc.bulk_payment_sync(ids)

    assert synced == ids
    sleep.assert_not_awaited()  # no failures -> no retry wait


async def test_failures_retried_after_delay(monkeypatch) -> None:
    svc = _build_service()
    sleep = AsyncMock()
    monkeypatch.setattr(mod.asyncio, "sleep", sleep)
    a, b, c = uuid4(), uuid4(), uuid4()
    attempts: dict[UUID, int] = {}

    async def flaky(member_id, idempotency_key) -> None:
        attempts[member_id] = attempts.get(member_id, 0) + 1
        if member_id == b and attempts[member_id] == 1:
            raise LockBusyError("busy")

    svc.update_payments_recurring = flaky

    await svc.bulk_payment_sync([a, b, c])

    # b failed once, was retried and succeeded; a and c synced once.
    assert attempts == {a: 1, b: 2, c: 1}
    sleep.assert_awaited_once_with(settings.bulk_sync_retry_delay_seconds)


async def test_persistent_failure_retries_max_then_logs(monkeypatch) -> None:
    svc = _build_service()
    sleep = AsyncMock()
    monkeypatch.setattr(mod.asyncio, "sleep", sleep)
    bad = uuid4()
    attempts: list[UUID] = []

    async def always_busy(member_id, idempotency_key) -> None:
        attempts.append(member_id)
        raise LockBusyError("busy")

    svc.update_payments_recurring = always_busy

    # First pass + bulk_sync_max_retries retry passes, all fail; never raises.
    await svc.bulk_payment_sync([bad])

    assert attempts == [bad] * (settings.bulk_sync_max_retries + 1)
    assert sleep.await_count == settings.bulk_sync_max_retries
