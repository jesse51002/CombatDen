"""Regression tests for G7 billing-webhook fixes (pure unit, no DB/Stripe).

Covers:
  C-048 — ``stripe_payment_intent_id`` reads the dahlia-nested
          ``parent.payment_intent_details.payment_intent`` (flat field removed),
          with a pre-dahlia flat fallback.
  C-049 — discount capture records one row per invoice LINE, so a coupon shared
          across two family lines is no longer collapsed into a single row.
  C-050 — a mid-cycle proration line never drives ``next_due_date``.
"""

from __future__ import annotations

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


# ── C-048: payment intent id (dahlia-nested first, flat fallback) ──────────


def test_payment_intent_id_reads_dahlia_nested_location() -> None:
    invoice = {
        "parent": {"payment_intent_details": {"payment_intent": "pi_new"}},
        "payment_intent": "pi_legacy",  # would win pre-fix
    }
    assert InvoicePaidHandler._invoice_payment_intent_id(invoice) == "pi_new"


def test_payment_intent_id_falls_back_to_flat_field() -> None:
    invoice = {"payment_intent": "pi_legacy"}
    assert InvoicePaidHandler._invoice_payment_intent_id(invoice) == "pi_legacy"


def test_payment_intent_id_none_when_dahlia_drops_flat_field() -> None:
    # Dahlia: flat field removed (None), nested absent -> None, not a crash.
    invoice = {"parent": {"subscription_details": {}}, "payment_intent": None}
    assert InvoicePaidHandler._invoice_payment_intent_id(invoice) is None


def test_payment_intent_id_nested_empty_falls_back() -> None:
    invoice = {
        "parent": {"payment_intent_details": {"payment_intent": None}},
        "payment_intent": "pi_legacy",
    }
    assert (
        InvoicePaidHandler._invoice_payment_intent_id(invoice) == "pi_legacy"
    )


# ── C-050: proration detection (dahlia-nested + legacy) ────────────────────


def test_is_proration_subscription_item_details() -> None:
    line = {"parent": {"subscription_item_details": {"proration": True}}}
    assert InvoicePaidHandler._is_proration(line) is True


def test_is_proration_invoice_item_details() -> None:
    line = {"parent": {"invoice_item_details": {"proration": True}}}
    assert InvoicePaidHandler._is_proration(line) is True


def test_is_proration_legacy_flat_flag() -> None:
    assert InvoicePaidHandler._is_proration({"proration": True}) is True


def test_regular_recurring_line_is_not_proration() -> None:
    line = {"parent": {"subscription_item_details": {"proration": False}}}
    assert InvoicePaidHandler._is_proration(line) is False


# ── C-049: discount capture is per-line, not per-invoice-rollup ────────────


class _AsyncNullCtx:
    async def __aenter__(self) -> _AsyncNullCtx:
        return self

    async def __aexit__(self, *exc: object) -> bool:
        return False


class _FakeSession:
    """Records every execute() params dict; begin_nested() is a no-op ctx."""

    def __init__(self) -> None:
        self.executed: list[dict[str, Any]] = []

    async def execute(
        self, statement: Any, params: dict[str, Any] | None = None
    ) -> MagicMock:
        if params is not None:
            self.executed.append(params)
        return MagicMock()

    def begin_nested(self) -> _AsyncNullCtx:
        return _AsyncNullCtx()


async def test_shared_coupon_records_one_row_per_family_line() -> None:
    """A coupon shared across two sibling lines yields TWO rows (one per
    line id), not a single collapsed row."""
    handler = _handler()
    # Skip the Stripe expand-retrieve; map the di_ -> coupon directly.
    handler._fetch_invoice_coupons = AsyncMock(  # type: ignore[method-assign]
        return_value={"di_shared": "cpn_fam"}
    )

    invoice = {
        "id": "in_1",
        # invoice-level rollup is only the cheap "has discounts?" gate
        "total_discount_amounts": [{"amount": 1000, "discount": "di_shared"}],
        "lines": {
            "data": [
                {
                    "id": "il_a",
                    "discount_amounts": [
                        {"amount": 500, "discount": "di_shared"}
                    ],
                },
                {
                    "id": "il_b",
                    "discount_amounts": [
                        {"amount": 500, "discount": "di_shared"}
                    ],
                },
            ]
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
    assert len(inserts) == 2
    line_ids = {p["line_item_id"] for p in inserts}
    assert line_ids == {"il_a", "il_b"}
    assert all(p["stripe_coupon_id"] == "cpn_fam" for p in inserts)
    assert all(p["amount_off"] == 500 for p in inserts)


async def test_capture_noop_when_no_discounts_makes_no_stripe_call() -> None:
    handler = _handler()
    handler._fetch_invoice_coupons = AsyncMock()  # type: ignore[method-assign]
    session = _FakeSession()

    await handler._capture_discounts(
        session,
        {"id": "in_2", "total_discount_amounts": [], "lines": {"data": []}},
        gym_id=uuid4(),
        invoice_id=uuid4(),
        stripe_account_id="acct_1",
    )

    handler._fetch_invoice_coupons.assert_not_called()
    assert session.executed == []
