"""Hand-crafted Stripe event payloads for webhook handler tests.

Each builder returns a ``dict`` that mirrors the minimum shape of a
real Stripe event as consumed by our handlers. These bypass Stripe
entirely — we're testing our dispatcher + SQL, not Stripe's API.
"""

import time
import uuid
from decimal import Decimal
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
    subscription_id: str | None = None,
    paid_at: int | None = None,
    period_end: int | None = None,
    event_id: str | None = None,
    metadata: dict[str, str] | None = None,
    total_discount_amounts: list[dict[str, Any]] | None = None,
    one_time_line_ids: list[str] | None = None,
) -> dict[str, Any]:
    """Build an ``invoice.paid`` event payload in the Stripe "dahlia" shape.

    One line per ``stripe_item_id`` is emitted with an identical
    ``period.end`` (simulating a multi-item subscription renewal). The
    subscription item id and subscription metadata live under the nested
    ``parent`` discriminator (dahlia). ``invoice.charge`` / ``payment_intent``
    are gone — the charge arrives separately on ``invoice_payment.paid``.

    A subscription invoice (non-empty ``stripe_item_ids``) carries its
    metadata under ``parent.subscription_details.metadata``; a one-time
    invoice (empty) carries it on the invoice root.

    ``one_time_line_ids`` adds one-time / trial membership lines — each has an
    ``id`` but NO ``subscription_item`` (its dahlia parent is an invoice-item
    discriminator). A one-time membership's ``stripe_item_id`` IS this line id,
    so the line→membership resolver falls back to the line id. Pair it with an
    empty ``stripe_item_ids`` + ``crm_one_time_payment`` root metadata to model
    a real one-time membership invoice.
    """
    now = int(time.time())
    paid_at = paid_at or now
    period_end = period_end or (now + 30 * 24 * 60 * 60)
    stripe_invoice_id = stripe_invoice_id or f"in_test_{uuid.uuid4().hex[:16]}"
    subscription_id = subscription_id or f"sub_test_{uuid.uuid4().hex[:16]}"

    lines = [
        {
            "id": f"il_test_{i}",
            "amount": amount_paid,
            "currency": currency,
            "period": {"start": now, "end": period_end},
            # Stripe's ``Event.to_dict()`` yields ``Decimal`` here — the
            # field that crashed the webhook before ``dump_stripe_payload``.
            "pricing": {"unit_amount_decimal": Decimal(str(amount_paid))},
            "parent": {
                "type": "subscription_item_details",
                "subscription_item_details": {
                    "subscription": subscription_id,
                    "subscription_item": si,
                },
            },
        }
        for i, si in enumerate(stripe_item_ids)
    ]
    # A one-time / trial line has NO subscription_item — its dahlia parent is an
    # invoice-item discriminator, so ``line_subscription_item`` returns None and
    # the resolver falls back to the line id (== the membership's stripe_item_id).
    for line_id in one_time_line_ids or []:
        lines.append(
            {
                "id": line_id,
                "amount": amount_paid,
                "currency": currency,
                "period": {"start": now, "end": period_end},
                "pricing": {"unit_amount_decimal": Decimal(str(amount_paid))},
                "parent": {
                    "type": "invoice_item_details",
                    "invoice_item_details": {},
                },
            }
        )

    invoice = {
        "id": stripe_invoice_id,
        "object": "invoice",
        "status": "paid",
        "amount_paid": amount_paid,
        "amount_due": amount_paid,
        "total": amount_paid,
        "currency": currency,
        "customer": f"cus_test_{uuid.uuid4().hex[:16]}",
        "status_transitions": {"paid_at": paid_at},
        "created": now,
        "lines": {"data": lines, "object": "list"},
        # dahlia: amounts + opaque di_ Discount ids (no coupon inline).
        "total_discount_amounts": total_discount_amounts or [],
    }
    if stripe_item_ids:
        invoice["parent"] = {
            "type": "subscription_details",
            "subscription_details": {
                "subscription": subscription_id,
                "metadata": metadata or {},
            },
        }
        invoice["metadata"] = {}
    else:
        invoice["metadata"] = metadata or {}

    return {
        "id": event_id or _evt_id("evt_test_paid"),
        "type": "invoice.paid",
        "account": stripe_account_id,
        "created": now,
        "data": {"object": invoice},
    }


def make_invoice_payment_paid_event(
    *,
    stripe_account_id: str,
    stripe_invoice_id: str,
    amount_paid: int = 5000,
    currency: str = "usd",
    payment_type: str = "payment_intent",
    payment_intent_id: str | None = None,
    paid_at: int | None = None,
    event_id: str | None = None,
) -> dict[str, Any]:
    """Build an ``invoice_payment.paid`` event payload (an InvoicePayment).

    ``payment_type='payment_intent'`` (card/bank) carries a PaymentIntent the
    handler retrieves to resolve the charge id; ``payment_type='out_of_band'``
    is a cash payment with no PaymentIntent.
    """
    now = int(time.time())
    paid_at = paid_at or now
    payment_intent_id = payment_intent_id or f"pi_test_{uuid.uuid4().hex[:16]}"

    if payment_type == "out_of_band":
        payment: dict[str, Any] = {"type": "out_of_band"}
    else:
        payment = {"type": "payment_intent", "payment_intent": payment_intent_id}

    invoice_payment = {
        "id": f"inpay_test_{uuid.uuid4().hex[:16]}",
        "object": "invoice_payment",
        "invoice": stripe_invoice_id,
        "status": "paid",
        "amount_paid": amount_paid,
        "amount_requested": amount_paid,
        "currency": currency,
        "is_default": True,
        "created": now,
        "status_transitions": {"paid_at": paid_at},
        "payment": payment,
    }
    return {
        "id": event_id or _evt_id("evt_test_inpay"),
        "type": "invoice_payment.paid",
        "account": stripe_account_id,
        "created": now,
        "data": {"object": invoice_payment},
    }


def make_invoice_payment_failed_event(
    *,
    stripe_account_id: str,
    stripe_item_ids: list[str],
    amount_due: int = 5000,
    currency: str = "usd",
    stripe_invoice_id: str | None = None,
    event_id: str | None = None,
    attempt_count: int = 1,
) -> dict[str, Any]:
    """Build an ``invoice.payment_failed`` event payload (dahlia shape).

    ``attempt_count`` is Stripe's per-invoice attempt counter; the failed-charge
    row is keyed on (invoice id, attempt_count), so distinct attempts produce
    distinct rows while a re-delivered/re-swept same attempt dedupes.
    """
    now = int(time.time())
    stripe_invoice_id = stripe_invoice_id or f"in_test_{uuid.uuid4().hex[:16]}"
    subscription_id = f"sub_test_{uuid.uuid4().hex[:16]}"

    lines = [
        {
            "id": f"il_test_{i}",
            "amount": amount_due,
            "currency": currency,
            "period": {"start": now, "end": now + 30 * 24 * 60 * 60},
            # Stripe's ``Event.to_dict()`` yields ``Decimal`` here — the
            # field that crashed the webhook before ``dump_stripe_payload``.
            "pricing": {"unit_amount_decimal": Decimal(str(amount_due))},
            "parent": {
                "type": "subscription_item_details",
                "subscription_item_details": {
                    "subscription": subscription_id,
                    "subscription_item": si,
                },
            },
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
        "attempt_count": attempt_count,
        "customer": f"cus_test_{uuid.uuid4().hex[:16]}",
        "created": now,
        "lines": {"data": lines, "object": "list"},
        "parent": {
            "type": "subscription_details",
            "subscription_details": {"subscription": subscription_id, "metadata": {}},
        },
        "metadata": {},
    }
    return {
        "id": event_id or _evt_id("evt_test_failed"),
        "type": "invoice.payment_failed",
        "account": stripe_account_id,
        "created": now,
        "data": {"object": invoice},
    }


def make_refund_event(
    *,
    stripe_account_id: str,
    stripe_charge_id: str,
    amount: int,
    currency: str = "usd",
    status: str = "succeeded",
    event_type: str = "refund.created",
    refund_id: str | None = None,
    created: int | None = None,
    event_id: str | None = None,
) -> dict[str, Any]:
    """Build a ``refund.created`` / ``refund.updated`` event payload.

    The event's data object is the Refund itself (dahlia shape). One refund
    per event; ``refund.charge`` links back to the original charge. ``status``
    and ``event_type`` are configurable to cover the pending→succeeded path.
    """
    now = int(time.time())
    refund = {
        "id": refund_id or f"re_test_{uuid.uuid4().hex[:16]}",
        "object": "refund",
        "amount": amount,
        "currency": currency,
        "status": status,
        "charge": stripe_charge_id,
        "payment_intent": f"pi_test_{uuid.uuid4().hex[:16]}",
        "created": created or now,
    }
    return {
        "id": event_id or _evt_id("evt_test_refund"),
        "type": event_type,
        "account": stripe_account_id,
        "created": now,
        "data": {"object": refund},
    }


def make_account_updated_event(
    *,
    stripe_account_id: str,
    details_submitted: bool = True,
    charges_enabled: bool = True,
    payouts_enabled: bool = True,
    disabled_reason: str | None = None,
    currently_due: list[str] | None = None,
    event_id: str | None = None,
) -> dict[str, Any]:
    """Build an ``account.updated`` event payload.

    The connected account being updated is ``stripe_account_id`` (both
    the event's ``account`` and ``data.object.id``). The capability
    flags + ``requirements`` drive the canonical status mapping.
    """
    now = int(time.time())
    account = {
        "id": stripe_account_id,
        "object": "account",
        "details_submitted": details_submitted,
        "charges_enabled": charges_enabled,
        "payouts_enabled": payouts_enabled,
        "requirements": {
            "disabled_reason": disabled_reason,
            "currently_due": currently_due or [],
        },
    }
    return {
        "id": event_id or _evt_id("evt_test_account"),
        "type": "account.updated",
        "account": stripe_account_id,
        "created": now,
        "data": {"object": account},
    }


def make_customer_subscription_deleted_event(
    *,
    stripe_account_id: str,
    member_id: str | None,
    gym_id: str | None = None,
    stripe_subscription_id: str | None = None,
    event_id: str | None = None,
) -> dict[str, Any]:
    """Build a ``customer.subscription.deleted`` event payload.

    ``member_id`` is the value stamped in the sub's metadata by the sync
    (the paying parent). Pass ``None`` to omit it (missing-metadata case) or a
    non-UUID string to exercise the malformed-member-id guard.
    """
    now = int(time.time())
    stripe_subscription_id = (
        stripe_subscription_id or f"sub_test_{uuid.uuid4().hex[:16]}"
    )
    metadata: dict[str, str] = {}
    if member_id is not None:
        metadata["member_id"] = member_id
    if gym_id is not None:
        metadata["gym_id"] = gym_id
    subscription = {
        "id": stripe_subscription_id,
        "object": "subscription",
        "status": "canceled",
        "metadata": metadata,
        "created": now,
    }
    return {
        "id": event_id or _evt_id("evt_test_subdel"),
        "type": "customer.subscription.deleted",
        "account": stripe_account_id,
        "created": now,
        "data": {"object": subscription},
    }
