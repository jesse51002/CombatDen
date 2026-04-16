"""Hand-crafted Stripe event payloads for webhook handler tests.

Each builder returns a ``dict`` that mirrors the minimum shape of a
real Stripe event as consumed by our handlers. These bypass Stripe
entirely — we're testing our dispatcher + SQL, not Stripe's API.
"""

import time
import uuid
from typing import Any


def _evt_id(prefix: str = "evt_test") -> str:
    return f"{prefix}_{uuid.uuid4().hex[:20]}"


def make_invoice_paid_event(
    *,
    stripe_account_id: str,
    stripe_item_ids: list[str],
    amount_paid: int = 5000,
    currency: str = "usd",
    stripe_invoice_id: str | None = None,
    stripe_charge_id: str | None = "ch_test_paid_1",
    paid_at: int | None = None,
    period_end: int | None = None,
    event_id: str | None = None,
    metadata: dict[str, str] | None = None,
) -> dict[str, Any]:
    """Build an ``invoice.paid`` event payload.

    One line per ``stripe_item_id`` is emitted with an identical
    ``period.end`` (simulating a multi-item subscription renewal).
    """
    now = int(time.time())
    paid_at = paid_at or now
    period_end = period_end or (now + 30 * 24 * 60 * 60)
    stripe_invoice_id = stripe_invoice_id or f"in_test_{uuid.uuid4().hex[:16]}"

    lines = [
        {
            "id": f"il_test_{i}",
            "subscription_item": si,
            "amount": amount_paid,
            "currency": currency,
            "period": {"start": now, "end": period_end},
        }
        for i, si in enumerate(stripe_item_ids)
    ]

    invoice = {
        "id": stripe_invoice_id,
        "object": "invoice",
        "status": "paid",
        "amount_paid": amount_paid,
        "amount_due": amount_paid,
        "total": amount_paid,
        "currency": currency,
        "charge": stripe_charge_id,
        "payment_intent": f"pi_test_{uuid.uuid4().hex[:16]}",
        "customer": f"cus_test_{uuid.uuid4().hex[:16]}",
        "status_transitions": {"paid_at": paid_at},
        "created": now,
        "lines": {"data": lines, "object": "list"},
        "metadata": metadata or {},
    }
    return {
        "id": event_id or _evt_id("evt_test_paid"),
        "type": "invoice.paid",
        "account": stripe_account_id,
        "created": now,
        "data": {"object": invoice},
    }


def make_invoice_payment_failed_event(
    *,
    stripe_account_id: str,
    stripe_item_ids: list[str],
    amount_due: int = 5000,
    currency: str = "usd",
    stripe_invoice_id: str | None = None,
    event_id: str | None = None,
) -> dict[str, Any]:
    """Build an ``invoice.payment_failed`` event payload."""
    now = int(time.time())
    stripe_invoice_id = stripe_invoice_id or f"in_test_{uuid.uuid4().hex[:16]}"

    lines = [
        {
            "id": f"il_test_{i}",
            "subscription_item": si,
            "amount": amount_due,
            "currency": currency,
            "period": {"start": now, "end": now + 30 * 24 * 60 * 60},
        }
        for i, si in enumerate(stripe_item_ids)
    ]

    invoice = {
        "id": stripe_invoice_id,
        "object": "invoice",
        "status": "open",
        "amount_due": amount_due,
        "amount_paid": 0,
        "total": amount_due,
        "currency": currency,
        "charge": None,
        "attempt_count": 1,
        "payment_intent": f"pi_test_{uuid.uuid4().hex[:16]}",
        "customer": f"cus_test_{uuid.uuid4().hex[:16]}",
        "created": now,
        "lines": {"data": lines, "object": "list"},
    }
    return {
        "id": event_id or _evt_id("evt_test_failed"),
        "type": "invoice.payment_failed",
        "account": stripe_account_id,
        "created": now,
        "data": {"object": invoice},
    }


def make_charge_refunded_event(
    *,
    stripe_account_id: str,
    stripe_charge_id: str,
    refund_amounts: list[int],
    currency: str = "usd",
    event_id: str | None = None,
) -> dict[str, Any]:
    """Build a ``charge.refunded`` event payload.

    One refund per entry in ``refund_amounts``.
    """
    now = int(time.time())
    refunds = [
        {
            "id": f"re_test_{uuid.uuid4().hex[:16]}",
            "amount": amount,
            "currency": currency,
            "created": now,
            "charge": stripe_charge_id,
        }
        for amount in refund_amounts
    ]
    charge = {
        "id": stripe_charge_id,
        "object": "charge",
        "amount": sum(refund_amounts),
        "amount_refunded": sum(refund_amounts),
        "currency": currency,
        "refunds": {"data": refunds, "object": "list"},
    }
    return {
        "id": event_id or _evt_id("evt_test_refund"),
        "type": "charge.refunded",
        "account": stripe_account_id,
        "created": now,
        "data": {"object": charge},
    }
