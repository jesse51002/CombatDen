"""Regression tests for G1 — one-time billing safety.

C-025: a post-charge writeback failure in ``PaymentSyncOneTime`` must NEVER
propagate. A successful one-time charge is terminal money; if the writeback
raised, the start op's blanket ``except`` (``_charge_one_time_group``) would
route the group to ``_fail_group(cleanup=True) -> _delete_pending``, DELETING
the just-charged rows and un-billing a real charge. The writeback is therefore
best-effort (every step guarded, logged, never re-raised), mirroring the
recurring ``PaymentSyncWriteback``. These are pure unit tests — the DB /
payment-service collaborators are mocked, nothing touches a live DB or Stripe.

C-086 (one-time insert idempotency) is NOT covered here: a correct fix requires
persisting the request idempotency key (an ``idempotency_key`` column on
``member_memberships`` + ``ON CONFLICT`` in ``member_memberships_insert.sql``,
or deterministic item_ids fed to that insert). Those live in the DB schema /
SQL / query layer, outside the two files owned by this group, so the regression
test for C-086 belongs with that cross-file change. See the group report.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.payments.schema.payments_payment_schema import (
    PaymentsInvoicePaymentResponse,
)
from src.shared.payer_profile import PayerProfile
from src.sync.service.sync_one_time import PaymentSyncOneTime
from src.sync.sync_schema import OneTimeInvoiceItem, OneTimeInvoicePlan


def _make_service() -> PaymentSyncOneTime:
    """A PaymentSyncOneTime whose collaborators are all mocked.

    The constructor builds ``self._queries = PaymentSyncQueries(db_pool)``; we
    swap it for an ``AsyncMock`` so no SQL runs.
    """
    service = PaymentSyncOneTime(
        db_pool=MagicMock(),
        discounts=MagicMock(),
        payment_service=AsyncMock(),
        payer_resolver=AsyncMock(),
    )
    service._queries = AsyncMock()
    return service


def _make_plan(n_items: int, n_links: int = 0) -> OneTimeInvoicePlan:
    """A plan with ``n_items`` membership lines and ``n_links`` coupon links."""
    payer = PayerProfile(
        member_id=uuid4(),
        gym_id=uuid4(),
        stripe_customer_id="cus_test",
    )
    items = [
        OneTimeInvoiceItem(
            item_id=uuid4(),
            member_id=uuid4(),
            plan_id=uuid4(),
            stripe_price_id=f"price_{i}",
            quantity=1,
        )
        for i in range(n_items)
    ]
    coupon_links = {uuid4(): f"coupon_{i}" for i in range(n_links)}
    return OneTimeInvoicePlan(
        items=items,
        payer=payer,
        stripe_account_id="acct_test",
        coupon_links=coupon_links,
    )


def _make_result(n_lines: int) -> PaymentsInvoicePaymentResponse:
    """A charge result with ``n_lines`` returned invoice lines."""
    return PaymentsInvoicePaymentResponse(
        stripe_invoice_id="in_test",
        stripe_customer_id="cus_test",
        amount_paid=1000,
        currency="usd",
        status="paid",
        line_item_ids=[f"il_{i}" for i in range(n_lines)],
        line_amounts=[1000 for _ in range(n_lines)],
    )


@pytest.mark.asyncio
async def test_writeback_swallows_membership_stamp_failure() -> None:
    """A failing per-row stamp is logged, not raised (charge stays billed)."""
    service = _make_service()
    service._queries.apply_one_time_membership_sync.side_effect = RuntimeError(
        "db down",
    )
    plan = _make_plan(n_items=2, n_links=1)
    result = _make_result(n_lines=2)

    # Must NOT raise — a raise would un-bill the charge in the caller.
    await service._writeback(plan, result)

    # Best-effort: it tried every row, and still ran the coupon-link step
    # afterward despite the row failures.
    assert service._queries.apply_one_time_membership_sync.await_count == 2
    assert service._queries.set_applied_discount_coupon_id.await_count == 1


@pytest.mark.asyncio
async def test_writeback_swallows_coupon_link_failure() -> None:
    """A failing coupon link is logged, not raised."""
    service = _make_service()
    service._queries.set_applied_discount_coupon_id.side_effect = RuntimeError(
        "coupon write failed",
    )
    plan = _make_plan(n_items=1, n_links=2)
    result = _make_result(n_lines=1)

    await service._writeback(plan, result)

    # Every row stamped; every coupon link attempted despite failures.
    assert service._queries.apply_one_time_membership_sync.await_count == 1
    assert service._queries.set_applied_discount_coupon_id.await_count == 2


@pytest.mark.asyncio
async def test_writeback_line_count_mismatch_does_not_raise() -> None:
    """A Stripe line-count mismatch is logged loud, never raised.

    The old code used ``zip(..., strict=True)``, which raised on a mismatch;
    after a successful charge that raise un-billed the rows. Now it stamps the
    overlap best-effort.
    """
    service = _make_service()
    plan = _make_plan(n_items=3)
    result = _make_result(n_lines=2)  # Stripe billed fewer lines than we sent.

    await service._writeback(plan, result)

    # Overlap (2) stamped, no exception.
    assert service._queries.apply_one_time_membership_sync.await_count == 2


@pytest.mark.asyncio
async def test_charge_one_time_does_not_propagate_writeback_failure() -> None:
    """End-to-end: a writeback failure after a successful charge is swallowed.

    This is the C-025 guarantee at the ``charge_one_time`` boundary — the
    method the start op wraps in a blanket ``except`` that would otherwise
    delete the billed rows.
    """
    service = _make_service()
    plan = _make_plan(n_items=1)
    # Skip the read/build; jump straight to a charged plan + a poisoned write.
    service._build_plan = AsyncMock(return_value=plan)
    service._execute = AsyncMock(return_value=_make_result(n_lines=1))
    service._payer.resolve_payer_with_account = AsyncMock(
        return_value=(plan.payer, "acct_test"),
    )
    service._queries.apply_one_time_membership_sync.side_effect = RuntimeError(
        "writeback boom",
    )

    # The charge happened; the writeback failed — charge_one_time must still
    # return cleanly so the caller never reaches its delete branch.
    await service.charge_one_time(
        payer_member_id=plan.payer.member_id,
        idempotency_key=uuid4(),
    )

    service._execute.assert_awaited_once()
    service._queries.apply_one_time_membership_sync.assert_awaited()
