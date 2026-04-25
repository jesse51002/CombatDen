"""Direct Stripe SDK helpers for the seed script.

The seed normally goes through the FastAPI backend for anything Stripe-backed
so real `cus_*` / `sub_*` IDs end up in the DB. The overdue-member flow can't
use that path because:
  - A Stripe customer has to be created UNDER a test clock (can't attach
    later), and the backend's members-create endpoint always creates its own
    customer.
  - We need to advance the clock after subscription creation to force a
    failed renewal.

So for the 2 overdue members per gym we talk to Stripe directly from here.
Reads `STRIPE_SECRET_KEY` from env; every call is stamped with the gym's
Connect account via `stripe_account=`.

Requires `stripe listen --forward-to localhost:8000/api/v1/webhooks/stripe`
running if you want webhook-driven state (e.g. `invoice.paid` updating
`next_due_date`/`last_paid_date`) to land in the DB after `mark_paid_cash`.
"""

from __future__ import annotations

import os
import time
from datetime import datetime

import stripe

_POLL_INTERVAL_S = 1.0
_POLL_MAX_WAIT_S = 60


def _api_key() -> str:
    key = os.environ.get("STRIPE_SECRET_KEY")
    if not key:
        raise RuntimeError(
            "STRIPE_SECRET_KEY not set — required for the overdue-member seed path"
        )
    return key


def create_test_clock(stripe_account_id: str, frozen_time: datetime) -> str:
    """Create a Stripe test clock frozen at ``frozen_time`` (UTC)."""
    ts = int(frozen_time.timestamp())
    clock = stripe.test_helpers.TestClock.create(
        frozen_time=ts,
        name="seed-overdue",
        api_key=_api_key(),
        stripe_account=stripe_account_id,
    )
    return clock.id


def advance_clock(
    stripe_account_id: str,
    clock_id: str,
    advance_to: datetime,
) -> None:
    """Advance a test clock and block until Stripe reports it ready."""
    ts = int(advance_to.timestamp())
    stripe.test_helpers.TestClock.advance(
        clock_id,
        frozen_time=ts,
        api_key=_api_key(),
        stripe_account=stripe_account_id,
    )

    elapsed = 0.0
    while elapsed < _POLL_MAX_WAIT_S:
        clock = stripe.test_helpers.TestClock.retrieve(
            clock_id,
            api_key=_api_key(),
            stripe_account=stripe_account_id,
        )
        if clock.status == "ready":
            return
        if clock.status == "internal_failure":
            raise RuntimeError(f"Test clock {clock_id} entered internal_failure")
        time.sleep(_POLL_INTERVAL_S)
        elapsed += _POLL_INTERVAL_S
    raise TimeoutError(f"Test clock {clock_id} not ready within {_POLL_MAX_WAIT_S}s")


def create_customer_under_clock(
    stripe_account_id: str,
    clock_id: str,
    name: str,
    email: str,
    phone: str,
    metadata: dict,
) -> str:
    """Create a customer locked to ``clock_id``. Returns the customer ID."""
    customer = stripe.Customer.create(
        name=name,
        email=email,
        phone=phone,
        test_clock=clock_id,
        metadata=metadata,
        api_key=_api_key(),
        stripe_account=stripe_account_id,
    )
    return customer.id


def _attach_pm(
    stripe_account_id: str,
    stripe_customer_id: str,
    pm_token: str,
) -> str:
    pm = stripe.PaymentMethod.attach(
        pm_token,
        customer=stripe_customer_id,
        api_key=_api_key(),
        stripe_account=stripe_account_id,
    )
    stripe.Customer.modify(
        stripe_customer_id,
        invoice_settings={"default_payment_method": pm.id},
        api_key=_api_key(),
        stripe_account=stripe_account_id,
    )
    return pm.id


def attach_working_payment_method(
    stripe_account_id: str,
    stripe_customer_id: str,
) -> str:
    """Attach ``pm_card_visa`` and make it the default. Returns the PM id."""
    return _attach_pm(stripe_account_id, stripe_customer_id, "pm_card_visa")


def attach_declining_payment_method(
    stripe_account_id: str,
    stripe_customer_id: str,
) -> str:
    """Attach ``pm_card_chargeDeclined`` and make it the default.

    Charges against this PM are declined by Stripe's test backend. Use this
    AFTER the first invoice has settled so the initial subscription creation
    doesn't fail.
    """
    return _attach_pm(stripe_account_id, stripe_customer_id, "pm_card_chargeDeclined")


def create_recurring_subscription(
    stripe_account_id: str,
    stripe_customer_id: str,
    stripe_price_id: str,
    metadata: dict,
) -> tuple[str, str, int]:
    """Create a recurring subscription.

    Returns ``(subscription_id, subscription_item_id, current_period_end)``.
    """
    sub = stripe.Subscription.create(
        customer=stripe_customer_id,
        items=[{"price": stripe_price_id}],
        metadata=metadata,
        # Let the first invoice be paid through the card (which will decline
        # for overdue seeding). `default_incomplete` would block us in
        # incomplete-payment state instead of generating an unpaid invoice.
        payment_behavior="allow_incomplete",
        api_key=_api_key(),
        stripe_account=stripe_account_id,
    )
    item = sub["items"]["data"][0]
    return sub.id, item.id, item.current_period_end
