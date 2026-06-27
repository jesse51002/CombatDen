"""Pure-unit tests for the ``invoice.paid`` handler fixes (no DB/Stripe).

Covers:
  #12 — ``_insert_line_items`` skips proration lines (incl. the zero-dollar edge).
  #7  — ``_all_lines`` paginates the invoice lines so a >10-line family invoice
        is not truncated to Stripe's embedded first page; a non-paged invoice (or
        one with no Stripe account to page against) makes no extra Stripe call.
  Review #1 — ``_capture_discounts`` gates on per-line ``discount_amounts``, NOT
        the invoice-level ``total_discount_amounts`` rollup (which dahlia can omit
        while lines still carry discounts).
"""

from __future__ import annotations

import json
from typing import Any
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from src.stripe_webhooks.service.invoice_paid_handler import InvoicePaidHandler


class _FakeStripeClient:
    """Minimal stand-in exposing the ``.client`` the handler stores."""

    def __init__(self) -> None:
        self.client = MagicMock()


def _handler() -> InvoicePaidHandler:
    return InvoicePaidHandler(_FakeStripeClient())


class _AsyncNullCtx:
    async def __aenter__(self) -> _AsyncNullCtx:
        return self

    async def __aexit__(self, *exc: object) -> bool:
        return False


class _FakeResult:
    """A membership-lookup result that resolves to zero rows."""

    def mappings(self) -> _FakeResult:
        return self

    def all(self) -> list[Any]:
        return []


class _FakeSession:
    """Records every execute() params dict; begin_nested() is a no-op ctx."""

    def __init__(self) -> None:
        self.executed: list[dict[str, Any]] = []

    async def execute(
        self, statement: Any, params: dict[str, Any] | None = None
    ) -> _FakeResult:
        if params is not None:
            self.executed.append(params)
        return _FakeResult()

    def begin_nested(self) -> _AsyncNullCtx:
        return _AsyncNullCtx()


# ── #12: _insert_line_items skips proration lines ──────────────────────────


async def test_insert_line_items_skips_proration_line() -> None:
    """A zero-dollar proration line records no row; the normal line does."""
    handler = _handler()
    lines = [
        {
            "id": "il_pro",
            "amount": 0,
            "parent": {"subscription_item_details": {"proration": True}},
        },
        {"id": "il_normal", "amount": 5000, "description": "Membership"},
    ]
    session = _FakeSession()

    await handler._insert_line_items(
        session, lines, gym_id=uuid4(), invoice_id=uuid4()
    )

    inserts = [p for p in session.executed if "item_type" in p]
    assert {p["line_item_id"] for p in inserts} == {"il_normal"}
    # The proration line drove no DB call at all (not even a membership lookup).
    assert not any(
        p.get("line_item_id") == "il_pro" or p.get("stripe_item_id") == "il_pro"
        for p in session.executed
    )


# ── #7: _all_lines paginates every line beyond the embedded page ───────────


class _FakeLineObj:
    """Stripe-line stand-in whose ``str()`` is its canonical JSON (round-trip)."""

    def __init__(self, payload: dict[str, Any]) -> None:
        self._payload = payload

    def __str__(self) -> str:
        return json.dumps(self._payload)


class _FakePage:
    def __init__(self, data: list[_FakeLineObj], has_more: bool) -> None:
        self.data = data
        self.has_more = has_more


def _paged_invoice() -> dict[str, Any]:
    return {
        "id": "in_paged",
        "lines": {
            "has_more": True,
            "data": [{"id": "il_a"}],
        },
    }


async def test_all_lines_follows_has_more_across_pages() -> None:
    """``has_more`` is followed through the line-items endpoint; every page's
    lines are returned alongside the embedded first page."""
    handler = _handler()
    page_one = _FakePage([_FakeLineObj({"id": "il_b"})], has_more=True)
    page_two = _FakePage([_FakeLineObj({"id": "il_c"})], has_more=False)
    list_async = AsyncMock(side_effect=[page_one, page_two])
    handler._stripe.v1.invoices.line_items.list_async = list_async

    lines = await handler._all_lines(_paged_invoice(), "acct_1")

    assert [line["id"] for line in lines] == ["il_a", "il_b", "il_c"]
    assert list_async.await_count == 2


async def test_all_lines_no_pagination_when_not_has_more() -> None:
    """A single embedded page makes NO line-items list call."""
    handler = _handler()
    list_async = AsyncMock()
    handler._stripe.v1.invoices.line_items.list_async = list_async
    invoice = {"id": "in_single", "lines": {"has_more": False, "data": [{"id": "il_a"}]}}

    lines = await handler._all_lines(invoice, "acct_1")

    list_async.assert_not_awaited()
    assert [line["id"] for line in lines] == ["il_a"]


async def test_all_lines_no_pagination_without_account() -> None:
    """``has_more`` but no Stripe account -> degrade to the embedded page."""
    handler = _handler()
    list_async = AsyncMock()
    handler._stripe.v1.invoices.line_items.list_async = list_async

    lines = await handler._all_lines(_paged_invoice(), None)

    list_async.assert_not_awaited()
    assert [line["id"] for line in lines] == ["il_a"]


# ── Review #1: capture gates on per-line discounts, not the rollup ─────────


async def test_capture_discounts_dahlia_no_top_level_rollup() -> None:
    """A dahlia invoice with NO ``total_discount_amounts`` but per-line
    ``discount_amounts`` still records the per-line audit rows."""
    handler = _handler()
    handler._fetch_invoice_coupons = AsyncMock(  # type: ignore[method-assign]
        return_value={"di_a": "cpn_a", "di_b": "cpn_b"}
    )
    lines = [
        {"id": "il_a", "discount_amounts": [{"amount": 100, "discount": "di_a"}]},
        {"id": "il_b", "discount_amounts": [{"amount": 200, "discount": "di_b"}]},
    ]
    session = _FakeSession()

    await handler._capture_discounts(
        session,
        {"id": "in_dahlia"},  # no total_discount_amounts rollup at all
        lines,
        gym_id=uuid4(),
        invoice_id=uuid4(),
        stripe_account_id="acct_1",
    )

    inserts = [p for p in session.executed if "stripe_coupon_id" in p]
    assert {p["line_item_id"] for p in inserts} == {"il_a", "il_b"}
    by_line = {p["line_item_id"]: p for p in inserts}
    assert by_line["il_a"]["stripe_coupon_id"] == "cpn_a"
    assert by_line["il_b"]["amount_off"] == 200


async def test_capture_discounts_noop_when_no_line_discounts() -> None:
    """No line carries ``discount_amounts`` -> no coupon fetch, no rows."""
    handler = _handler()
    handler._fetch_invoice_coupons = AsyncMock()  # type: ignore[method-assign]
    session = _FakeSession()

    await handler._capture_discounts(
        session,
        {"id": "in_none"},
        [{"id": "il_a", "amount": 5000}],
        gym_id=uuid4(),
        invoice_id=uuid4(),
        stripe_account_id="acct_1",
    )

    handler._fetch_invoice_coupons.assert_not_called()
    assert session.executed == []
