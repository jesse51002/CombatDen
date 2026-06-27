"""Unit tests: SubscriptionOrphanSweep cancels only aged, unlinked subs.

Piece 3 adds a reconciler sweep that cancels Stripe subscriptions whose items map
to no live membership row. These tests exercise the per-subscription decision
(``_consider_sub``) with plain dicts + mocked DB linkage + mocked cancel, so no DB
/ Stripe is touched. The Stripe list + per-account iteration is the proven
``_iter`` scaffold shared with InvoiceFetchSweep.
"""

from unittest.mock import AsyncMock, MagicMock

import src.shared.db_schema_path  # noqa: F401
from src.reconciler.service.reconciler.reconciler_result import SweepResult
from src.reconciler.service.reconciler.reconciler_subscription_orphan_sweep import (
    SubscriptionOrphanSweep,
)

MIN_CREATED = 1_000_000_000  # the age-guard cutoff used in these tests
ANCIENT = 1  # created well before the cutoff (eligible)


def _sweep() -> SubscriptionOrphanSweep:
    return SubscriptionOrphanSweep(
        db_pool=MagicMock(),
        stripe_client=MagicMock(),
        subscription_service=AsyncMock(),
    )


def _sub(created: int, item_ids: list[str], *, has_more: bool = False) -> dict:
    return {
        "id": "sub_x",
        "created": created,
        "items": {
            "data": [{"id": i} for i in item_ids],
            "has_more": has_more,
        },
    }


async def test_orphan_sub_is_cancelled() -> None:
    """An aged sub with no live link is cancelled."""
    sweep = _sweep()
    sweep._has_live_link = AsyncMock(return_value=False)
    result = SweepResult(name="x")

    await sweep._consider_sub(_sub(ANCIENT, ["si_1"]), "acct_1", MIN_CREATED, result)

    sweep._subscription_service.cancel_subscription.assert_awaited_once()
    assert result.changed == 1
    assert result.processed == 1


async def test_linked_sub_is_kept() -> None:
    """A sub with a live-linked item is never cancelled."""
    sweep = _sweep()
    sweep._has_live_link = AsyncMock(return_value=True)
    result = SweepResult(name="x")

    await sweep._consider_sub(_sub(ANCIENT, ["si_1"]), "acct_1", MIN_CREATED, result)

    sweep._subscription_service.cancel_subscription.assert_not_awaited()
    assert result.changed == 0


async def test_young_sub_is_skipped_without_db_check() -> None:
    """A sub newer than the age guard is skipped (no link check, no cancel)."""
    sweep = _sweep()
    sweep._has_live_link = AsyncMock(return_value=False)
    result = SweepResult(name="x")

    await sweep._consider_sub(
        _sub(MIN_CREATED + 100, ["si_1"]), "acct_1", MIN_CREATED, result,
    )

    sweep._has_live_link.assert_not_awaited()
    sweep._subscription_service.cancel_subscription.assert_not_awaited()
    assert result.skipped == 1


async def test_sub_with_more_items_is_skipped() -> None:
    """A sub whose items don't fit one page is skipped (can't judge orphan)."""
    sweep = _sweep()
    sweep._has_live_link = AsyncMock(return_value=False)
    result = SweepResult(name="x")

    await sweep._consider_sub(
        _sub(ANCIENT, ["si_1"], has_more=True), "acct_1", MIN_CREATED, result,
    )

    sweep._has_live_link.assert_not_awaited()
    sweep._subscription_service.cancel_subscription.assert_not_awaited()
    assert result.skipped == 1


async def test_cancel_failure_is_isolated() -> None:
    """A failed cancel is counted as an error, never raised."""
    sweep = _sweep()
    sweep._has_live_link = AsyncMock(return_value=False)
    sweep._subscription_service.cancel_subscription = AsyncMock(
        side_effect=RuntimeError("boom"),
    )
    result = SweepResult(name="x")

    await sweep._consider_sub(_sub(ANCIENT, ["si_1"]), "acct_1", MIN_CREATED, result)

    assert result.errors == 1
    assert result.changed == 0
