"""LIVE end-to-end proof that retry-card charges a REAL failed renewal.

This is the money-moves test for ``MemberMembershipsService.retry_card`` →
``PaymentsStripePaymentService.pay_open_subscription_invoice_on_card``. It runs
against real Stripe test mode on the shared test Connect account; the unit
tests in ``test_memberships_retry_card.py`` cover the validations, this one
proves Stripe actually collects.

**Why it manufactures its own overdue member.** The seeded "overdue" members are
false overdue — their Stripe subscriptions are ``active`` with every invoice
``paid`` and only the CRM's ``next_due_date`` is stale, so there is no open
invoice to retry. A genuine failed renewal has to be built here: a member whose
saved DEFAULT card is ``tok_chargeCustomerFail`` (attaches fine, declines every
charge), on a Stripe test clock advanced past the monthly billing anchor so
Stripe cuts the renewal invoice, attempts it, and fails.

The membership starts with ``proration_behavior=no_charge`` on purpose: nothing
is due at start (the anchor is in the future), so the ONLY charge attempt in the
test is the renewal — which is where real-world overdue actually comes from. A
decline at *start* is a different path (``payment_behavior=error_if_incomplete``
makes Stripe 402 the create and leave no subscription behind) and is not what
this test is about.

**Assertions are Stripe-side only.** Stripe cannot reach localhost, so the
``invoice.paid`` webhook never fires here and no CRM ``member_invoices`` /
``member_charges`` row is written by this test. The on-demand invoice-fetch
fast path is also disabled suite-wide by the ``_disable_on_demand_invoice_fetch``
autouse fixture. CRM-side mirroring is covered by
``tests/memberships/test_invoice_fetch_e2e.py`` and the webhook tests; here the
proof of record is Stripe's own invoice status / ``amount_paid`` and the
subscription status.
"""

from __future__ import annotations

import asyncio
from datetime import datetime
from uuid import uuid4

import pytest
import stripe
from schema.task import ProrationBehavior

from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from tests.helpers.db_reads import (
    get_active_membership_item_id,
    get_profile_stripe_ids,
)
from tests.helpers.stripe_assertions import (
    advance_to_next_cycle_and_fetch_invoice,
    snapshot_billing_state,
)

# Attaches to a customer cleanly, then declines EVERY charge against that
# customer (card 4000 0000 0000 0341) — exactly the "card on file went bad"
# shape that produces a real overdue member.
FAILING_CARD_TOKEN = "tok_chargeCustomerFail"
GOOD_CARD_TOKEN = "tok_visa"

CLOCK_START = datetime(2026, 1, 15, 0, 0, 0)
# ``settings.monthly_billing_anchor_day`` is the 1st and the seeded gym is
# America/Chicago, so the first RENEWAL invoice is cut at 2026-02-01 06:00 UTC.
# Land ~18h past it: long enough for Stripe to finalize + attempt + fail it,
# short enough that no automatic (Smart Retry) second attempt has fired.
RENEWAL_ADVANCE = datetime(2026, 2, 2, 0, 0, 0)

PLAN_PRICE_CENTS = 5000

# Stripe finalizes/attempts a clock-generated invoice asynchronously; the list
# call can catch it while still ``draft``. Third-party settle latency, not our
# state — poll briefly for it to leave draft.
FINALIZE_POLL_INTERVAL_S = 1.0
FINALIZE_POLL_MAX_WAIT_S = 30


async def _retrieve_invoice(
    stripe_client: PaymentsStripeClient,
    invoice_id: str,
    connect_opts: stripe.RequestOptions,
) -> stripe.Invoice:
    return await stripe_client.client.v1.invoices.retrieve_async(
        invoice_id,
        options=connect_opts,
    )


async def _await_finalized_invoice(
    stripe_client: PaymentsStripeClient,
    invoice_id: str,
    connect_opts: stripe.RequestOptions,
) -> stripe.Invoice:
    """Return the invoice once Stripe has moved it out of ``draft``."""
    elapsed = 0.0
    invoice = await _retrieve_invoice(stripe_client, invoice_id, connect_opts)
    while invoice.status == "draft" and elapsed < FINALIZE_POLL_MAX_WAIT_S:
        await asyncio.sleep(FINALIZE_POLL_INTERVAL_S)
        elapsed += FINALIZE_POLL_INTERVAL_S
        invoice = await _retrieve_invoice(stripe_client, invoice_id, connect_opts)
    return invoice


async def _set_default_card(
    stripe_client: PaymentsStripeClient,
    connect_opts: stripe.RequestOptions,
    customer_id: str,
    payment_method_id: str,
) -> None:
    """Attach a payment method and make it the customer's invoice default.

    The same two Stripe calls the production card-swap
    (``PaymentsStripeMembersService.update_customer``) makes; inlined here
    because this is test SETUP for the second retry, not the path under test.
    """
    await stripe_client.client.v1.payment_methods.attach_async(
        payment_method_id,
        params={"customer": customer_id},
        options=connect_opts,
    )
    await stripe_client.client.v1.customers.update_async(
        customer_id,
        params={
            "invoice_settings": {"default_payment_method": payment_method_id},
        },
        options=connect_opts,
    )


@pytest.mark.timeout(300)
async def test_retry_card_pays_a_real_failed_renewal(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
) -> None:
    """A real declined renewal: retry on the bad card fails, on a good card pays.

    1. Manufacture the overdue state — advance a test clock past the billing
       anchor with a failing default card, and assert Stripe genuinely left an
       ``open`` unpaid renewal invoice (``past_due`` subscription).
    2. Decline path — ``retry_card`` raises and the invoice is STILL unpaid.
    3. Success path — swap the default to a good card, ``retry_card`` again,
       and the invoice is ``paid`` on Stripe for the full amount.
    """
    clock_id = await created.test_clock(CLOCK_START)
    bad_pm_id = await created.payment_method(token=FAILING_CARD_TOKEN)
    member = await created.member(
        gym_id,
        payment_method_id=bad_pm_id,
        test_clock_id=clock_id,
    )
    plan = await created.plan(gym_id, price_cents=PLAN_PRICE_CENTS)

    # ── Start the membership (nothing due yet: the anchor is in the future) ──
    await memberships_service.start(
        MemberMembershipsStartRequest(
            payer_member_id=member.member_id,
            gym_id=gym_id,
            idempotency_key=uuid4(),
            proration_behavior=ProrationBehavior.no_charge,
            memberships=[
                MemberMembershipsStartItem(
                    member_id=member.member_id,
                    price_id=plan.price_id,
                ),
            ],
        )
    )
    item_id = await get_active_membership_item_id(db_pool, member.member_id, gym_id)
    profile = await get_profile_stripe_ids(db_pool, member.member_id, gym_id)
    assert profile.stripe_sub_id_month is not None, (
        "start did not link a monthly Stripe subscription — the rest of this "
        "test has nothing to retry"
    )

    before = await snapshot_billing_state(
        stripe_client,
        profile.stripe_customer_id,
        connect_opts,
    )

    # ── 1. Manufacture the genuine overdue state ────────────────────────
    renewal = await advance_to_next_cycle_and_fetch_invoice(
        stripe_client,
        clock_id,
        RENEWAL_ADVANCE,
        profile.stripe_sub_id_month,
        before,
        connect_opts,
    )
    renewal = await _await_finalized_invoice(stripe_client, renewal.id, connect_opts)

    assert renewal.status == "open", (
        f"Expected the renewal invoice {renewal.id} to be OPEN (the failing "
        f"card could not pay it), got status={renewal.status}. Without a real "
        f"open invoice there is nothing for retry-card to prove."
    )
    assert renewal.amount_due == PLAN_PRICE_CENTS, (
        f"Renewal invoice {renewal.id} amount_due={renewal.amount_due}, "
        f"expected {PLAN_PRICE_CENTS}"
    )
    assert renewal.amount_paid == 0, (
        f"Renewal invoice {renewal.id} already collected "
        f"{renewal.amount_paid} — the failing card should have paid nothing"
    )

    sub = await stripe_client.client.v1.subscriptions.retrieve_async(
        profile.stripe_sub_id_month,
        options=connect_opts,
    )
    assert sub.status == "past_due", (
        f"Subscription {sub.id} status={sub.status}, expected past_due after a "
        f"failed renewal"
    )

    # ── 2. Decline path: same bad card, retry must FAIL ─────────────────
    # A fresh idempotency key per attempt — Stripe replays a cached 402 for a
    # reused one, which would make the second (good-card) retry a no-op.
    with pytest.raises(stripe.CardError) as declined:
        await memberships_service.retry_card(item_id, member.member_id, uuid4())
    assert declined.value.code is not None

    still_open = await _retrieve_invoice(stripe_client, renewal.id, connect_opts)
    assert still_open.status == "open", (
        f"A DECLINED retry must never settle the invoice: {renewal.id} is now "
        f"{still_open.status}"
    )
    assert still_open.amount_paid == 0, (
        f"A DECLINED retry must collect nothing: {renewal.id} amount_paid="
        f"{still_open.amount_paid}"
    )

    # ── 3. Success path: good card on file, retry must PAY ──────────────
    good_pm_id = await created.payment_method(token=GOOD_CARD_TOKEN)
    await _set_default_card(
        stripe_client,
        connect_opts,
        profile.stripe_customer_id,
        good_pm_id,
    )

    await memberships_service.retry_card(item_id, member.member_id, uuid4())

    paid = await _retrieve_invoice(stripe_client, renewal.id, connect_opts)
    assert paid.status == "paid", (
        f"retry-card did not collect: invoice {renewal.id} status={paid.status}"
    )
    assert paid.amount_paid == PLAN_PRICE_CENTS, (
        f"Invoice {renewal.id} amount_paid={paid.amount_paid}, "
        f"expected the full {PLAN_PRICE_CENTS}"
    )
    assert paid.amount_remaining == 0, (
        f"Invoice {renewal.id} still has {paid.amount_remaining} outstanding"
    )

    settled_sub = await stripe_client.client.v1.subscriptions.retrieve_async(
        profile.stripe_sub_id_month,
        options=connect_opts,
    )
    assert settled_sub.status == "active", (
        f"Subscription {settled_sub.id} status={settled_sub.status}, expected "
        f"active once the open invoice was paid"
    )
