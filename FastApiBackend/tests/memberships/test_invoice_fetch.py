"""Unit tests for the on-demand invoice fetch (``MemberMembershipsInvoiceFetch``).

These mock the payments service + the payer resolver — they exercise the retry /
early-stop loop, the customer-scoped vs full-sweep listing, the line-merge, the
no-billing-profile guard, and cancel-safety, all WITHOUT touching Stripe or the
DB. The Stripe list pagination + dict conversion now live in the payments layer
(see ``tests/payments/test_payments_invoice_list_primitives.py``); the
record-correctness is covered by the webhook ``record`` tests + the
``test_invoice_fetch_e2e`` end-to-end test.
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.core.config import settings
from src.memberships.service.memberships_invoice_fetch import (
    MemberMembershipsInvoiceFetch,
)


def _build_fetch(
    *,
    payer_resolver: AsyncMock,
    payment_service: AsyncMock | None = None,
) -> MemberMembershipsInvoiceFetch:
    return MemberMembershipsInvoiceFetch(
        db_pool=MagicMock(),
        payment_service=payment_service or AsyncMock(),
        invoice_paid_handler=MagicMock(),
        invoice_payment_paid_handler=MagicMock(),
        invoice_payment_failed_handler=MagicMock(),
        refund_handler=MagicMock(),
        payer_resolver=payer_resolver,
    )


def _payer_resolver(customer: str = "cus_test") -> AsyncMock:
    resolver = AsyncMock()
    payer = MagicMock(stripe_customer_id=customer, gym_id=uuid4())
    resolver.resolve_payer_with_account.return_value = (payer, "acct_test")
    return resolver


@pytest.fixture(autouse=True)
def _fast_retries(monkeypatch):
    """No real sleeping between attempts."""
    monkeypatch.setattr(
        settings, "invoice_fetch_retry_delays_seconds", [0, 0, 0, 0, 0]
    )
    monkeypatch.setattr(settings, "invoice_fetch_buffer_seconds", 60)


async def test_early_stop_once_a_fresh_invoice_is_applied():
    """Stops on the attempt that records a paid invoice created >= op_start."""
    fetch = _build_fetch(payer_resolver=_payer_resolver())
    attempts = []

    async def fake_sweep(gym_id, account_id, cutoff, result, *,
                         customer=None, fresh=None, fresh_since=None):
        attempts.append(customer)
        if len(attempts) == 3 and fresh is not None:
            fresh.append("in_fresh")  # the bill this op cut just landed

    fetch.sweep_account = fake_sweep
    await fetch.fetch_for_payer(uuid4(), op_start=1000)

    # Attempt 3 found it → no 4th/5th attempt.
    assert len(attempts) == 3
    assert attempts == ["cus_test", "cus_test", "cus_test"]


async def test_runs_every_attempt_when_nothing_fresh_lands():
    """Exhausts the schedule when the invoice never shows (backstops cover it)."""
    fetch = _build_fetch(payer_resolver=_payer_resolver())
    attempts = []

    async def fake_sweep(gym_id, account_id, cutoff, result, *,
                         customer=None, fresh=None, fresh_since=None):
        attempts.append(customer)  # never appends to fresh

    fetch.sweep_account = fake_sweep
    await fetch.fetch_for_payer(uuid4(), op_start=1000)

    assert len(attempts) == len(settings.invoice_fetch_retry_delays_seconds)


async def test_no_billing_profile_is_a_clean_noop():
    """A payer with no Stripe customer (cash-only) makes no fetch call."""
    resolver = AsyncMock()
    resolver.resolve_payer_with_account.side_effect = ValueError("no profile")
    fetch = _build_fetch(payer_resolver=resolver)
    swept = []
    fetch.sweep_account = lambda *a, **k: swept.append(1)  # noqa: E731

    await fetch.fetch_for_payer(uuid4(), op_start=1000)

    assert swept == []  # never reached the fetch loop


async def test_customer_scopes_invoices_and_skips_refunds():
    """A customer-scoped sweep filters invoices by customer and lists NO refunds
    (refunds.list has no customer filter; on-demand isn't about refunds)."""
    payments = AsyncMock()
    payments.list_invoices.return_value = []
    payments.list_refunds.return_value = []
    fetch = _build_fetch(
        payer_resolver=_payer_resolver(), payment_service=payments
    )
    from src.shared.sweep_result import SweepResult

    await fetch.sweep_account(
        uuid4(), "acct_test", 1000, SweepResult(name="t"), customer="cus_x"
    )

    payments.list_invoices.assert_awaited_once()
    assert payments.list_invoices.await_args.kwargs["customer"] == "cus_x"
    payments.list_refunds.assert_not_awaited()  # skipped on a customer sweep


async def test_full_sweep_lists_refunds_and_has_no_customer():
    """customer=None (the reconciler path) lists refunds and no customer."""
    payments = AsyncMock()
    payments.list_invoices.return_value = []
    payments.list_refunds.return_value = []
    fetch = _build_fetch(
        payer_resolver=_payer_resolver(), payment_service=payments
    )
    from src.shared.sweep_result import SweepResult

    await fetch.sweep_account(uuid4(), "acct_test", 1000, SweepResult(name="t"))

    assert payments.list_invoices.await_args.kwargs["customer"] is None
    payments.list_refunds.assert_awaited_once()


async def test_complete_invoice_lines_merges_when_has_more():
    """A paid invoice reporting lines.has_more gets ALL its lines merged in
    (the payments primitive returns the full paginated list)."""
    payments = AsyncMock()
    payments.list_invoice_line_items.return_value = [
        {"id": "il_1"}, {"id": "il_2"}, {"id": "il_3"},
    ]
    fetch = _build_fetch(
        payer_resolver=_payer_resolver(), payment_service=payments
    )

    invoice = {"id": "in_1", "lines": {"data": [{"id": "il_1"}], "has_more": True}}
    await fetch._complete_invoice_lines(invoice, "acct_test")

    payments.list_invoice_line_items.assert_awaited_once()
    assert invoice["lines"]["has_more"] is False
    assert [li["id"] for li in invoice["lines"]["data"]] == [
        "il_1", "il_2", "il_3",
    ]


async def test_complete_invoice_lines_noop_when_all_present():
    """No extra fetch when the first page already holds every line."""
    payments = AsyncMock()
    fetch = _build_fetch(
        payer_resolver=_payer_resolver(), payment_service=payments
    )
    invoice = {"id": "in_1", "lines": {"data": [{"id": "il_1"}], "has_more": False}}
    await fetch._complete_invoice_lines(invoice, "acct_test")

    payments.list_invoice_line_items.assert_not_awaited()
    assert invoice["lines"]["data"] == [{"id": "il_1"}]


async def test_cancel_propagates_during_backoff(monkeypatch):
    """Cancelling the task mid-sleep raises CancelledError (clean shutdown)."""
    monkeypatch.setattr(
        settings, "invoice_fetch_retry_delays_seconds", [60]
    )
    fetch = _build_fetch(payer_resolver=_payer_resolver())

    async def fake_sweep(*a, **k):
        return  # nothing fresh → it will hit the sleep

    fetch.sweep_account = fake_sweep
    task = asyncio.create_task(fetch.fetch_for_payer(uuid4(), op_start=1000))
    await asyncio.sleep(0)  # let it reach the sleep
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
