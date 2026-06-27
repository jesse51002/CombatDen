"""Regression tests for Group G8 billing fixes.

C-053 — ``InvoicePaymentPaidHandler`` must not be forced to make its live
Stripe ``payment_intents.retrieve`` *inside* the caller's open DB transaction:
a caller may pre-resolve the charge (``resolve_charge``) and hand it to
``record`` via ``charge_details``, in which case ``record`` makes **no** Stripe
call. These pure tests lock in that seam (mocked Stripe + session — no DB,
no network).

C-083 — cash payments carry ``stripe_charge_id IS NULL`` and so get no
idempotency from the ``stripe_charge_id`` UNIQUE; the schema must add a partial
unique index scoped to succeeded cash payments per invoice, and the insert must
keep its target-less ``ON CONFLICT DO NOTHING`` (which arbitrates on that index
too). These are static assertions on the SQL source — no DB needed.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.stripe_webhooks.service.invoice_payment_paid_handler import (
    InvoicePaymentPaidHandler,
)

# Anchor on the FastApiBackend root (the dir holding both ``src`` and ``tests``)
# so these file paths don't depend on how deep this test is nested.
FASTAPI_ROOT = next(
    p
    for p in Path(__file__).resolve().parents
    if (p / "src").is_dir() and (p / "tests").is_dir()
)
SCHEMA_SQL = (
    FASTAPI_ROOT.parent
    / "Database"
    / "supabase"
    / "schemas"
    / "member_charges.sql"
)
INSERT_SQL = (
    FASTAPI_ROOT
    / "src"
    / "stripe_webhooks"
    / "sql"
    / "member_charge_insert.sql"
)


def _build_handler() -> tuple[InvoicePaymentPaidHandler, AsyncMock]:
    """Handler whose Stripe ``payment_intents.retrieve_async`` is a tripwire."""
    retrieve = AsyncMock(
        side_effect=AssertionError("Stripe must not be called")
    )
    stripe_client = MagicMock()
    stripe_client.client.v1.payment_intents.retrieve_async = retrieve
    handler = InvoicePaymentPaidHandler(stripe_client)
    return handler, retrieve


def _mock_session(invoice_row: dict[str, Any]) -> AsyncMock:
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = invoice_row
    session = AsyncMock()
    session.execute = AsyncMock(return_value=result)
    return session


def _insert_params(session: AsyncMock) -> dict[str, Any]:
    """The params dict of the member_charges INSERT (the call with ``kind``)."""
    for call in session.execute.call_args_list:
        params = call.args[1] if len(call.args) > 1 else call.kwargs.get(
            "parameters"
        )
        if isinstance(params, dict) and params.get("kind") == "payment":
            return params
    raise AssertionError("no member_charges insert was executed")


@pytest.mark.asyncio
async def test_record_uses_pre_resolved_charge_no_stripe_call() -> None:
    """C-053: with ``charge_details`` supplied, ``record`` makes no Stripe call
    and writes exactly the pre-resolved charge fields."""
    handler, retrieve = _build_handler()
    handler._resolve_charge = AsyncMock(  # type: ignore[method-assign]
        side_effect=AssertionError("must use the pre-resolved charge_details")
    )
    invoice_row = {"paid_by_member_id": uuid4(), "invoice_id": uuid4()}
    session = _mock_session(invoice_row)
    invoice_payment = {
        "status": "paid",
        "invoice": "in_123",
        "amount_paid": 1000,
        "currency": "usd",
        "payment": {"type": "payment_intent", "payment_intent": "pi_1"},
        "created": 1_700_000_000,
    }

    await handler.record(
        session,
        invoice_payment,
        uuid4(),
        stripe_account_id="acct_x",
        charge_details=("ch_seam", "card", "4242"),
    )

    retrieve.assert_not_awaited()
    handler._resolve_charge.assert_not_awaited()
    params = _insert_params(session)
    assert params["stripe_charge_id"] == "ch_seam"
    assert params["payment_method_type"] == "card"
    assert params["card_last_four"] == "4242"


@pytest.mark.asyncio
async def test_record_falls_back_to_internal_resolution() -> None:
    """C-053: when ``charge_details`` is omitted (today's callers), ``record``
    resolves internally — preserving existing behavior."""
    handler, _retrieve = _build_handler()
    handler._resolve_charge = AsyncMock(  # type: ignore[method-assign]
        return_value=(None, "cash", None)
    )
    invoice_row = {"paid_by_member_id": uuid4(), "invoice_id": uuid4()}
    session = _mock_session(invoice_row)
    invoice_payment = {
        "status": "paid",
        "invoice": "in_456",
        "amount_paid": 500,
        "currency": "usd",
        "payment": {"type": "out_of_band"},
        "created": 1_700_000_000,
    }

    await handler.record(session, invoice_payment, uuid4())

    handler._resolve_charge.assert_awaited_once()
    params = _insert_params(session)
    assert params["stripe_charge_id"] is None
    assert params["payment_method_type"] == "cash"


@pytest.mark.asyncio
async def test_resolve_charge_cash_makes_no_stripe_call() -> None:
    """C-053: the public seam resolves an out-of-band (cash) payment with no
    DB and no Stripe I/O."""
    handler, retrieve = _build_handler()

    details = await handler.resolve_charge(
        {"payment": {"type": "out_of_band"}}, "acct_x"
    )

    assert details == (None, "cash", None)
    retrieve.assert_not_awaited()


def test_schema_has_cash_payment_dedup_index() -> None:
    """C-083: a partial unique index deduplicates succeeded cash payments per
    invoice, scoped so it never collides with a cash refund or a failed
    NULL-charge-id attempt."""
    sql = SCHEMA_SQL.read_text().lower()
    assert "create unique index" in sql
    # The predicate must pin all four scoping conditions.
    assert "stripe_charge_id is null" in sql
    assert "kind = 'payment'" in sql
    assert "status = 'succeeded'" in sql
    assert "payment_method_type = 'cash'" in sql
    # Keyed on the invoice (one succeeded cash payment per invoice).
    idx = sql.index("create unique index")
    body = sql[idx : idx + 400]
    assert "(invoice_id)" in body
    assert "where" in body


def test_insert_keeps_targetless_on_conflict() -> None:
    """C-083: the insert keeps a target-less ``ON CONFLICT DO NOTHING`` so it
    arbitrates on the new partial index (and the existing UNIQUEs) — a specific
    conflict target would only cover one arbiter and reintroduce the dup."""
    sql = INSERT_SQL.read_text()
    upper = sql.upper()
    assert "ON CONFLICT DO NOTHING" in upper
    # No parenthesised conflict target between ON CONFLICT and DO NOTHING.
    assert "ON CONFLICT (" not in upper
