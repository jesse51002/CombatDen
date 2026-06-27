"""Pure-unit tests for two ``invoice.paid`` handler fixes (no DB/Stripe).

Covers:
  #12 — ``_insert_line_items`` skips proration lines (incl. the zero-dollar
        edge), mirroring ``_update_memberships`` / ``_capture_discounts``.
  #7  — ``_capture_discounts`` paginates the invoice lines (``_all_lines``) so
        a >10-line family invoice records audit rows for lines beyond Stripe's
        embedded first page; a non-paged invoice makes no extra Stripe call.
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
    invoice = {
        "id": "in_1",
        "lines": {
            "data": [
                {
                    "id": "il_pro",
                    "amount": 0,
                    "parent": {
                        "subscription_item_details": {"proration": True}
                    },
                },
                {
                    "id": "il_normal",
                    "amount": 5000,
                    "description": "Membership",
                },
            ]
        },
    }
    session = _FakeSession()

    await handler._insert_line_items(
        session, invoice, gym_id=uuid4(), invoice_id=uuid4()
    )

    inserts = [p for p in session.executed if "item_type" in p]
    assert {p["line_item_id"] for p in inserts} == {"il_normal"}
    # The proration line drove no DB call at all (not even a membership lookup).
    assert not any(
        p.get("line_item_id") == "il_pro" or p.get("stripe_item_id") == "il_pro"
        for p in session.executed
    )


# ── #7: _capture_discounts paginates lines across pages ────────────────────


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


async def test_capture_discounts_captures_across_paginated_lines() -> None:
    """An embedded page with ``has_more`` is followed through the line-items
    endpoint; a second-page line's coupon is recorded."""
    handler = _handler()
    handler._fetch_invoice_coupons = AsyncMock(  # type: ignore[method-assign]
        return_value={"di_a": "cpn_a", "di_b": "cpn_b", "di_c": "cpn_c"}
    )

    page_one = _FakePage(
        [_FakeLineObj({"id": "il_b", "discount_amounts": [
            {"amount": 200, "discount": "di_b"}
        ]})],
        has_more=True,
    )
    page_two = _FakePage(
        [_FakeLineObj({"id": "il_c", "discount_amounts": [
            {"amount": 300, "discount": "di_c"}
        ]})],
        has_more=False,
    )
    list_async = AsyncMock(side_effect=[page_one, page_two])
    handler._stripe.v1.invoices.line_items.list_async = list_async

    invoice = {
        "id": "in_paged",
        "total_discount_amounts": [{"amount": 100, "discount": "di_a"}],
        "lines": {
            "has_more": True,
            "data": [
                {
                    "id": "il_a",
                    "discount_amounts": [{"amount": 100, "discount": "di_a"}],
                }
            ],
        },
    }
    session = _FakeSession()

    await handler._capture_discounts(
        session,
        invoice,
        gym_id=uuid4(),
        invoice_id=uuid4(),
        stripe_account_id="acct_1",
    )

    inserts = [p for p in session.executed if "stripe_coupon_id" in p]
    assert {p["line_item_id"] for p in inserts} == {"il_a", "il_b", "il_c"}
    by_line = {p["line_item_id"]: p for p in inserts}
    # The second-page line is the load-bearing assertion (the truncation gap).
    assert by_line["il_c"]["stripe_coupon_id"] == "cpn_c"
    assert by_line["il_c"]["amount_off"] == 300
    assert list_async.await_count == 2


async def test_capture_discounts_no_pagination_when_not_has_more() -> None:
    """A single embedded page makes NO line-items list call."""
    handler = _handler()
    handler._fetch_invoice_coupons = AsyncMock(  # type: ignore[method-assign]
        return_value={"di_a": "cpn_a"}
    )
    list_async = AsyncMock()
    handler._stripe.v1.invoices.line_items.list_async = list_async

    invoice = {
        "id": "in_single",
        "total_discount_amounts": [{"amount": 100, "discount": "di_a"}],
        "lines": {
            "has_more": False,
            "data": [
                {
                    "id": "il_a",
                    "discount_amounts": [{"amount": 100, "discount": "di_a"}],
                }
            ],
        },
    }
    session = _FakeSession()

    await handler._capture_discounts(
        session,
        invoice,
        gym_id=uuid4(),
        invoice_id=uuid4(),
        stripe_account_id="acct_1",
    )

    list_async.assert_not_awaited()
    inserts = [p for p in session.executed if "stripe_coupon_id" in p]
    assert {p["line_item_id"] for p in inserts} == {"il_a"}
