"""Unit tests: ``PaymentSyncWriteback.write`` is best-effort per step.

Regression guard for the bug where a single failed writeback aborted every
later step. The worst case it produced: for a **cancel**, the caller's verify
reads the ``deleted`` stamp written near the end of the writeback, so a transient
failure in an earlier step (e.g. a coupon-link write) skipped the ``deleted``
stamp and ``sync_or_revert`` reverted a cancel Stripe had already executed.

Each step now runs under its own guard — a failure is logged and swallowed and
must NOT prevent the remaining steps from running. ``write`` never raises; the
caller's verify/revert + the reconciler re-correct any step that did not land.

These are pure unit tests: ``PaymentSyncQueries`` and the subscription service
are mocked, so no DB / Stripe is touched.
"""

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
from src.shared.payer_profile import PayerProfile
from src.sync.service.sync_writeback import PaymentSyncWriteback
from src.sync.sync_schema import (
    ActiveMembershipRow,
    IntervalBucket,
    SyncParams,
)


def _params(memberships: list[ActiveMembershipRow] | None = None) -> SyncParams:
    """A minimal SyncParams with one coupon link to write back."""
    payer = PayerProfile(
        member_id=uuid4(),
        gym_id=uuid4(),
        stripe_customer_id="cus_test",
    )
    return SyncParams(
        bucket=IntervalBucket(interval=DurationUnit.month, items=[]),
        payer=payer,
        stripe_account_id="acct_test",
        coupon_links={uuid4(): "pct_1000"},
        membership_post_discount_amounts={},
        memberships=memberships or [],
    )


def _writeback() -> tuple[PaymentSyncWriteback, AsyncMock]:
    """A writeback whose queries + subscription service are mocked."""
    wb = PaymentSyncWriteback(
        db_pool=MagicMock(),
        subscription_service=AsyncMock(),
    )
    queries = AsyncMock()
    # _mark_removed_deleted reads this; no cancelled rows → early return.
    queries.get_cancelled_recurring.return_value = {}
    wb._queries = queries
    # _sync_payer_monthly_total only fetches when there is a sub id; keep the
    # upcoming-invoice read harmless if it is reached.
    wb._subscription_service.fetch_upcoming_invoice = AsyncMock(
        return_value=SimpleNamespace(lines=[]),
    )
    return wb, queries


async def test_mirror_step_failure_does_not_block_later_steps() -> None:
    """A failed post-discount-price write must not abort the rest."""
    wb, queries = _writeback()
    queries.set_membership_post_discount_prices.side_effect = RuntimeError(
        "boom",
    )

    # Must not raise.
    await wb.write(_params(), sub_result=None)

    # Every step AFTER the failing one still ran.
    queries.set_applied_discount_coupon_id.assert_awaited()
    queries.update_profile_sub_id.assert_awaited()
    queries.set_payer_monthly_total.assert_awaited()


async def test_coupon_link_failure_does_not_block_later_steps() -> None:
    """A failed coupon-link write must not abort the status/sub-id writes."""
    wb, queries = _writeback()
    queries.set_applied_discount_coupon_id.side_effect = RuntimeError("boom")

    await wb.write(_params(), sub_result=None)

    queries.update_profile_sub_id.assert_awaited()
    queries.set_payer_monthly_total.assert_awaited()


async def test_membership_row_stamp_failure_is_isolated() -> None:
    """A failed per-membership stamp must not abort the later steps."""
    wb, queries = _writeback()
    queries.apply_membership_sync.side_effect = RuntimeError("boom")

    membership = ActiveMembershipRow(
        item_id=uuid4(),
        member_id=uuid4(),
        plan_id=uuid4(),
        price_id=uuid4(),
        stripe_price_id="price_x",
        price=5000,
    )
    item = SimpleNamespace(
        stripe_price_id="price_x",
        stripe_subscription_item_id="si_x",
        current_period_end=1893456000,
    )
    sub_result = SimpleNamespace(
        stripe_subscription_id="sub_x",
        items=[item],
    )

    await wb.write(_params([membership]), sub_result)

    # The stamp was attempted and failed, but the rest still ran.
    queries.apply_membership_sync.assert_awaited()
    queries.update_profile_sub_id.assert_awaited()
    queries.set_payer_monthly_total.assert_awaited()


async def test_write_never_raises_even_if_every_step_fails() -> None:
    """If every writeback step blows up, write still returns cleanly."""
    wb, queries = _writeback()
    for method in (
        "apply_membership_sync",
        "set_membership_post_discount_prices",
        "set_applied_discount_coupon_id",
        "get_cancelled_recurring",
        "update_profile_sub_id",
        "set_payer_monthly_total",
    ):
        getattr(queries, method).side_effect = RuntimeError("boom")

    # No exception escapes.
    await wb.write(_params(), sub_result=None)
