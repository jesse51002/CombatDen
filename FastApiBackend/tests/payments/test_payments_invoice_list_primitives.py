"""Unit tests for PaymentsStripePaymentService's paginated list primitives.

The Stripe list → plain-nested-dict conversion + auto-pagination that the
on-demand / reconciler invoice fetch consumes. No Stripe, no DB — a fake
``list_fn`` / fake page objects drive the loop.
"""

import json
from unittest.mock import MagicMock

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
