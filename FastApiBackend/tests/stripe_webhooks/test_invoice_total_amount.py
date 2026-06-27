"""Regression (review round-9): invoice.paid records the invoice's billed total.

``member_invoices.total_amount`` is the invoice's post-discount billed amount,
which is exactly Stripe's ``invoice.total`` (0 for a fully-discounted invoice,
the real total for a cash / customer-credit-funded one where ``amount_paid`` can
be 0). It must NOT be derived from ``amount_paid`` — that understates a
credit/out-of-band-funded invoice the member still owes the full total on. Pure
unit test over ``_upsert_invoice`` (no DB / Stripe / network).
"""

from __future__ import annotations

from typing import Any
from unittest.mock import MagicMock
from uuid import uuid4

import pytest

from src.stripe_webhooks.service.invoice_paid_handler import InvoicePaidHandler


class _FakeStripeClient:
    def __init__(self) -> None:
        self.client = MagicMock()


class _CaptureResult:
    def mappings(self) -> _CaptureResult:
        return self

    def fetchone(self) -> dict[str, Any]:
        return {"invoice_id": uuid4()}


class _CaptureSession:
    """Records the params of the upsert execute()."""

    def __init__(self) -> None:
        self.params: dict[str, Any] | None = None

    async def execute(
        self, _sql: Any, params: dict[str, Any]
    ) -> _CaptureResult:
        self.params = params
        return _CaptureResult()


def _handler() -> InvoicePaidHandler:
    return InvoicePaidHandler(_FakeStripeClient())


@pytest.mark.parametrize(
    ("total", "amount_paid", "expected"),
    [
        (0, 0, 0),  # fully discounted: post-discount total is 0
        (5000, 5000, 5000),  # normal paid invoice
        (5000, 0, 5000),  # credit/out-of-band funded: amount_paid=0, owes total
        (5000, 3000, 5000),  # split (credit+card): billed total, NOT amount_paid
        (-200, 0, 0),  # net-credit proration invoice: clamped to >= 0
        (None, None, 0),  # total absent -> 0
    ],
)
async def test_upsert_records_invoice_total(
    total: int | None, amount_paid: int | None, expected: int
) -> None:
    handler = _handler()
    session = _CaptureSession()
    invoice: dict[str, Any] = {"id": "in_x", "currency": "usd", "created": 1700000000}
    if total is not None:
        invoice["total"] = total
    if amount_paid is not None:
        invoice["amount_paid"] = amount_paid

    await handler._upsert_invoice(
        session,
        invoice,
        gym_id=uuid4(),
        paid_by_member_id=uuid4(),
        paid_for=[uuid4()],
    )

    assert session.params is not None
    assert session.params["total_amount"] == expected


async def test_upsert_tolerates_null_status_transitions() -> None:
    """A present-but-null status_transitions must not AttributeError (the
    handler would 500 and Stripe would retry the webhook forever)."""
    handler = _handler()
    session = _CaptureSession()
    invoice: dict[str, Any] = {
        "id": "in_y",
        "currency": "usd",
        "total": 5000,
        "created": 1700000000,
        "status_transitions": None,  # present but null
    }

    await handler._upsert_invoice(
        session,
        invoice,
        gym_id=uuid4(),
        paid_by_member_id=uuid4(),
        paid_for=[uuid4()],
    )

    assert session.params is not None
    assert session.params["total_amount"] == 5000
