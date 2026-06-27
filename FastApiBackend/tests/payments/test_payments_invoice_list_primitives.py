"""Unit tests for PaymentsStripePaymentService's paginated list primitives.

The Stripe list → plain-nested-dict conversion + auto-pagination that the
on-demand / reconciler invoice fetch consumes. No Stripe, no DB — a fake
``list_fn`` / fake page objects drive the loop.
"""

import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from src.core.config import settings
from src.payments.payments_exceptions import PaymentsStripeError
from src.payments.service.payments_stripe_payment_service import (
    PaymentsStripePaymentService,
)


class _FakeObj:
    """A Stripe object whose ``str`` is its canonical JSON (plus an ``id``)."""

    def __init__(self, obj_id: str) -> None:
        self.id = obj_id

    def __str__(self) -> str:
        return json.dumps({"id": self.id, "amount": 100})


def _build_service() -> PaymentsStripePaymentService:
    # MagicMock client: ._client.connect_opts_readonly(...) returns a mock
    # (passed as options + ignored by the fake list_fn); ._stripe is mock too.
    return PaymentsStripePaymentService(MagicMock(), MagicMock())


async def test_paginate_collects_all_pages_as_plain_dicts():
    page1 = MagicMock(data=[_FakeObj("a"), _FakeObj("b")], has_more=True)
    page2 = MagicMock(data=[_FakeObj("c")], has_more=False)
    calls: list[dict] = []

    async def list_fn(params=None, options=None):
        calls.append(params)
        return page1 if len(calls) == 1 else page2

    out = await _build_service()._paginate(list_fn, {"limit": 100}, "acct_1")

    assert [o["id"] for o in out] == ["a", "b", "c"]
    assert all(isinstance(o, dict) for o in out)
    # The 2nd page is fetched with starting_after = last id of page 1.
    assert calls[1]["starting_after"] == "b"


async def test_paginate_single_page_does_not_paginate():
    page = MagicMock(data=[_FakeObj("only")], has_more=False)
    calls: list[dict] = []

    async def list_fn(params=None, options=None):
        calls.append(params)
        return page

    out = await _build_service()._paginate(list_fn, {"limit": 100}, "acct_1")

    assert [o["id"] for o in out] == ["only"]
    assert len(calls) == 1
    assert "starting_after" not in calls[0]


async def test_paginate_empty_returns_empty():
    page = MagicMock(data=[], has_more=False)

    async def list_fn(params=None, options=None):
        return page

    out = await _build_service()._paginate(list_fn, {"limit": 100}, "acct_1")
    assert out == []


async def test_list_invoices_threads_customer_and_created():
    svc = _build_service()
    captured: dict = {}

    async def list_async(params=None, options=None):
        captured.update(params)
        return MagicMock(data=[], has_more=False)

    svc._stripe.v1.invoices.list_async = list_async
    await svc.list_invoices(
        "acct_1", created_gte=123, limit=50, customer="cus_9"
    )

    assert captured["customer"] == "cus_9"
    assert captured["created"] == {"gte": 123}
    assert captured["limit"] == 50


async def test_list_refunds_has_no_customer():
    svc = _build_service()
    captured: dict = {}

    async def list_async(params=None, options=None):
        captured.update(params)
        return MagicMock(data=[], has_more=False)

    svc._stripe.v1.refunds.list_async = list_async
    await svc.list_refunds("acct_1", created_gte=7, limit=20)

    assert "customer" not in captured
    assert captured["created"] == {"gte": 7}


async def test_list_invoice_line_items_passes_invoice_positionally():
    svc = _build_service()
    seen: dict = {}

    async def list_async(invoice, params=None, options=None):
        seen["invoice"] = invoice
        seen["params"] = params
        return MagicMock(data=[_FakeObj("il_1")], has_more=False)

    svc._stripe.v1.invoices.line_items.list_async = list_async
    out = await svc.list_invoice_line_items("acct_1", "in_42", limit=99)

    assert seen["invoice"] == "in_42"  # bound positionally via partial
    assert seen["params"]["limit"] == 99
    assert [o["id"] for o in out] == ["il_1"]


def _line(line_id: str, invoice_item_id: str, subtotal: int) -> SimpleNamespace:
    """A minimal stand-in for a Stripe InvoiceLineItem — what ``_order_lines`` /
    ``post_discount_amount`` read: ``id``, ``subtotal``, and the dahlia
    ``parent.invoice_item_details.invoice_item`` back-reference."""
    return SimpleNamespace(
        id=line_id,
        subtotal=subtotal,
        amount=subtotal,
        discount_amounts=[],
        parent=SimpleNamespace(
            invoice_item_details=SimpleNamespace(invoice_item=invoice_item_id),
        ),
    )


# --------------------------------------------------------------------------- #
# C-026 — itemized one-time invoice line pagination (>10 lines must not truncate)
# --------------------------------------------------------------------------- #
def test_order_lines_maps_all_items_in_request_order() -> None:
    """Every item maps to its line, in request order, post-discount amount."""
    item_ids = [f"ii_{i}" for i in range(15)]
    lines = [
        _line(f"il_{i}", f"ii_{i}", subtotal=100 + i)
        for i in reversed(range(15))
    ]

    ordered = PaymentsStripePaymentService._order_lines(lines, item_ids)

    assert [line_id for line_id, _ in ordered] == [f"il_{i}" for i in range(15)]
    assert [amount for _, amount in ordered] == [100 + i for i in range(15)]


def test_order_lines_raises_for_genuinely_missing_item() -> None:
    """A truly absent item (not just paged out) still raises."""
    lines = [_line("il_0", "ii_0", subtotal=500)]
    with pytest.raises(PaymentsStripeError, match="ii_missing"):
        PaymentsStripePaymentService._order_lines(lines, ["ii_0", "ii_missing"])


async def test_all_invoice_lines_no_extra_call_when_no_more() -> None:
    """<=10-item invoice (has_more False): use the embedded page, no request."""
    service = _build_service()
    service._stripe = MagicMock()
    service._stripe.v1.invoices.line_items.list_async = AsyncMock()

    embedded = [_line(f"il_{i}", f"ii_{i}", 100) for i in range(3)]
    invoice = SimpleNamespace(
        id="in_1",
        lines=SimpleNamespace(data=embedded, has_more=False),
    )

    result = await service._all_invoice_lines(invoice, "acct_123")

    assert [line.id for line in result] == ["il_0", "il_1", "il_2"]
    service._stripe.v1.invoices.line_items.list_async.assert_not_called()


async def test_all_invoice_lines_pages_past_first_page() -> None:
    """>10-item invoice: embedded first page + every paged line, no truncation."""
    service = _build_service()
    service._client.connect_opts_readonly.return_value = {"opt": True}
    service._stripe = MagicMock()

    embedded = [_line(f"il_{i}", f"ii_{i}", 100) for i in range(10)]
    page_two = [_line(f"il_{i}", f"ii_{i}", 100) for i in range(10, 18)]

    list_async = AsyncMock(
        return_value=SimpleNamespace(data=page_two, has_more=False),
    )
    service._stripe.v1.invoices.line_items.list_async = list_async

    invoice = SimpleNamespace(
        id="in_2",
        lines=SimpleNamespace(data=embedded, has_more=True),
    )

    result = await service._all_invoice_lines(invoice, "acct_123")

    assert [line.id for line in result] == [f"il_{i}" for i in range(18)]
    _, kwargs = list_async.call_args
    assert kwargs["params"]["starting_after"] == "il_9"
    assert kwargs["params"]["limit"] == settings.invoice_line_items_page_limit
    assert kwargs["options"] == {"opt": True}


async def test_all_invoice_lines_full_set_maps_without_truncation() -> None:
    """A 13-item invoice maps every item — the pre-fix bug raised here because
    only the first 10 embedded lines were seen."""
    service = _build_service()
    service._client.connect_opts_readonly.return_value = {}
    service._stripe = MagicMock()

    item_ids = [f"ii_{i}" for i in range(13)]
    embedded = [_line(f"il_{i}", f"ii_{i}", 100) for i in range(10)]
    rest = [_line(f"il_{i}", f"ii_{i}", 100) for i in range(10, 13)]
    service._stripe.v1.invoices.line_items.list_async = AsyncMock(
        return_value=SimpleNamespace(data=rest, has_more=False),
    )
    invoice = SimpleNamespace(
        id="in_3",
        lines=SimpleNamespace(data=embedded, has_more=True),
    )

    all_lines = await service._all_invoice_lines(invoice, "acct_123")
    ordered = PaymentsStripePaymentService._order_lines(all_lines, item_ids)

    assert [line_id for line_id, _ in ordered] == [f"il_{i}" for i in range(13)]
