"""Unit tests for the shared settle path (no DB / Stripe / network).

``MemberMembershipsSettle.settle_open_invoice`` is the ONE body behind both
``mark_paid_cash`` and ``retry_card``. They differ only in the ``pay`` callable
passed in — out of band for cash, on the saved default card for a retry — so
every validation, the payer/subscription/account resolution, and the
in-request apply of the paid invoice are exercised here once.

Scenarios:

1. ``test_settle_pays_then_applies_the_invoice`` — happy path: ``pay`` is
   called with the PAYER's monthly subscription, the gym's Connect account,
   and the op's idempotency key, and the invoice it returns is applied BY VALUE
   through ``invoice_fetch.apply_invoice`` IN-REQUEST (the fix — so
   ``next_due_date`` + the invoice/charge rows are current before the op
   returns, not left to the webhook/sweep, which never cover an old
   failed-renewal invoice).
1b. ``test_settle_apply_failure_does_not_fail_the_charge`` — an apply failure
   AFTER a successful charge is swallowed (logged), never surfaced as a failed
   settle, so a charged card is never reported to staff as a failure.
2. non-recurring / unlinked / canceled / no-subscription — each raises
   ``ValueError`` before any Stripe call, and nothing is applied.
3. ``test_settle_no_open_invoice_propagates`` — the "already settled"
   ``ValueError`` propagates and nothing is applied.
4. ``test_settle_decline_propagates_and_applies_nothing`` — a Stripe decline
   propagates (a failed settle must never read as success) and applies nothing.
5. ``test_endpoint_surfaces_card_decline_reason`` — the router maps a
   ``CardError`` to a 500 whose detail is Stripe's own reason.
"""

from datetime import timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
import stripe
from schema.membership_plan import PlanType

from src.memberships.service.memberships_settle import (
    MemberMembershipsSettle,
)
from src.shared.gym_timezone import gym_today
from src.shared.payer_profile import PayerProfile

GYM_TIMEZONE = "America/Chicago"
STRIPE_ACCOUNT_ID = "acct_test_settle"
STRIPE_SUB_ID = "sub_test_settle"
PAID_INVOICE_ID = "in_test_settle"
# The ``pay`` strategy returns the now-paid invoice BY VALUE (the plain nested
# dict the record seam consumes), not just its id — so apply records it
# without a re-retrieve.
PAID_INVOICE = {"id": PAID_INVOICE_ID, "status": "paid"}


def _membership_row(**overrides) -> dict:
    """A ``member_memberships_get.sql`` row for a healthy recurring row."""
    row = {
        "member_id": uuid4(),
        "plan_id": uuid4(),
        "paid_by_member_id": uuid4(),
        "gym_id": uuid4(),
        "plan_type": PlanType.recurring.value,
        "duration_unit": None,
        "duration_amount": None,
        "next_due_date": None,
        "cancel_date": None,
        "end_date": None,
        "price_id": uuid4(),
        "stripe_price_id": "price_test_settle",
        "stripe_item_id": "si_test_settle",
        "quantity": 1,
        "price": 10000,
        "timezone": GYM_TIMEZONE,
    }
    row.update(overrides)
    return row


def _db_pool_returning(row: dict) -> MagicMock:
    """A db_pool double whose session yields exactly ``row``."""
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = row
    session = MagicMock()
    session.execute = AsyncMock(return_value=result)
    session.commit = AsyncMock()
    cm = MagicMock()
    cm.__aenter__ = AsyncMock(return_value=session)
    cm.__aexit__ = AsyncMock(return_value=False)
    db_pool = MagicMock()
    db_pool.session = MagicMock(return_value=cm)
    return db_pool


def _build(row: dict, *, sub_id: str | None = STRIPE_SUB_ID):
    """Build the settle service over doubles.

    Returns ``(settle, pay, invoice_fetch)`` where ``pay`` is the AsyncMock
    strategy that returns the paid invoice (by value), and ``invoice_fetch``
    carries the ``apply_invoice`` AsyncMock the settle must call in-request.
    """
    pay = AsyncMock(return_value=PAID_INVOICE)

    payer_resolver = MagicMock()
    payer_resolver.resolve_payer = AsyncMock(
        return_value=PayerProfile(
            member_id=row["paid_by_member_id"],
            gym_id=row["gym_id"],
            stripe_customer_id="cus_test_settle",
            stripe_sub_id_month=sub_id,
            timezone=GYM_TIMEZONE,
        ),
    )

    gym_stripe_service = MagicMock()
    gym_stripe_service.get_stripe_account_id = AsyncMock(
        return_value=STRIPE_ACCOUNT_ID,
    )

    invoice_fetch = MagicMock()
    invoice_fetch.apply_invoice = AsyncMock()

    settle = MemberMembershipsSettle(
        _db_pool_returning(row),
        MagicMock(),  # payment_sync_service (unused by the settle path)
        gym_stripe_service,
        payer_resolver=payer_resolver,
        invoice_fetch=invoice_fetch,
    )
    return settle, pay, invoice_fetch


@pytest.mark.asyncio
async def test_settle_pays_then_applies_the_invoice() -> None:
    row = _membership_row()
    settle, pay, invoice_fetch = _build(row)
    key = uuid4()

    await settle.settle_open_invoice(uuid4(), row["member_id"], key, pay=pay)

    pay.assert_awaited_once_with(
        STRIPE_SUB_ID,
        STRIPE_ACCOUNT_ID,
        idempotency_key=str(key),
    )
    # THE FIX: the exact invoice just paid is applied in-request BY VALUE, so
    # next_due_date + the invoice/charge rows are current before we return
    # — not left to the webhook/sweep (which never cover an old invoice), and
    # with no re-retrieve that could read a stale state.
    invoice_fetch.apply_invoice.assert_awaited_once_with(
        row["gym_id"], STRIPE_ACCOUNT_ID, PAID_INVOICE
    )


@pytest.mark.asyncio
async def test_settle_apply_failure_does_not_fail_the_charge() -> None:
    """An apply failure AFTER a successful charge must NOT surface as a failed
    settle — the card already moved money, so reporting failure would tell
    staff nothing was collected and invite a double collection. The apply is
    swallowed (logged); the webhook + reconciler finalize the CRM rows."""
    row = _membership_row()
    settle, pay, invoice_fetch = _build(row)
    invoice_fetch.apply_invoice.side_effect = RuntimeError("stripe read blew up")
    key = uuid4()

    # Must NOT raise, even though apply_invoice did.
    await settle.settle_open_invoice(uuid4(), row["member_id"], key, pay=pay)

    # The charge happened and the apply was attempted with the paid invoice.
    pay.assert_awaited_once_with(
        STRIPE_SUB_ID,
        STRIPE_ACCOUNT_ID,
        idempotency_key=str(key),
    )
    invoice_fetch.apply_invoice.assert_awaited_once_with(
        row["gym_id"], STRIPE_ACCOUNT_ID, PAID_INVOICE
    )


def test_facade_exposes_both_pay_strategies() -> None:
    """The two strategies the facade passes into settle both exist — a guard
    that neither method name silently drifts."""
    from src.payments.service.payments_stripe_payment_service import (
        PaymentsStripePaymentService,
    )

    assert hasattr(
        PaymentsStripePaymentService, "pay_open_subscription_invoice_on_card"
    )
    assert hasattr(
        PaymentsStripePaymentService,
        "pay_open_subscription_invoice_out_of_band",
    )


@pytest.mark.asyncio
async def test_settle_non_recurring_rejected() -> None:
    row = _membership_row(plan_type=PlanType.one_time.value)
    settle, pay, invoice_fetch = _build(row)

    with pytest.raises(ValueError, match="recurring"):
        await settle.settle_open_invoice(uuid4(), row["member_id"], uuid4(), pay=pay)

    pay.assert_not_awaited()
    invoice_fetch.apply_invoice.assert_not_awaited()


@pytest.mark.asyncio
async def test_settle_unlinked_membership_rejected() -> None:
    row = _membership_row(stripe_item_id=None)
    settle, pay, invoice_fetch = _build(row)

    with pytest.raises(ValueError, match="not linked to a Stripe subscription"):
        await settle.settle_open_invoice(uuid4(), row["member_id"], uuid4(), pay=pay)

    pay.assert_not_awaited()
    invoice_fetch.apply_invoice.assert_not_awaited()


@pytest.mark.asyncio
async def test_settle_canceled_membership_rejected() -> None:
    row = _membership_row(
        cancel_date=gym_today(GYM_TIMEZONE) - timedelta(days=1),
    )
    settle, pay, invoice_fetch = _build(row)

    with pytest.raises(ValueError, match="canceled membership"):
        await settle.settle_open_invoice(uuid4(), row["member_id"], uuid4(), pay=pay)

    pay.assert_not_awaited()
    invoice_fetch.apply_invoice.assert_not_awaited()


@pytest.mark.asyncio
async def test_settle_no_monthly_subscription_rejected() -> None:
    row = _membership_row()
    settle, pay, invoice_fetch = _build(row, sub_id=None)

    with pytest.raises(ValueError, match="No active monthly subscription"):
        await settle.settle_open_invoice(uuid4(), row["member_id"], uuid4(), pay=pay)

    pay.assert_not_awaited()
    invoice_fetch.apply_invoice.assert_not_awaited()


@pytest.mark.asyncio
async def test_settle_no_open_invoice_propagates() -> None:
    row = _membership_row()
    settle, pay, invoice_fetch = _build(row)
    pay.side_effect = ValueError(
        "This invoice is already settled — nothing left to collect."
    )

    with pytest.raises(ValueError, match="already settled"):
        await settle.settle_open_invoice(uuid4(), row["member_id"], uuid4(), pay=pay)

    # Pay failed → nothing to apply.
    invoice_fetch.apply_invoice.assert_not_awaited()


@pytest.mark.asyncio
async def test_settle_decline_propagates_and_applies_nothing() -> None:
    """A declined settle must surface — never be swallowed into a success, and
    must never apply a payment that did not happen."""
    row = _membership_row()
    settle, pay, invoice_fetch = _build(row)
    pay.side_effect = stripe.CardError(
        "Your card was declined.",
        param=None,
        code="card_declined",
    )

    with pytest.raises(stripe.CardError):
        await settle.settle_open_invoice(uuid4(), row["member_id"], uuid4(), pay=pay)

    invoice_fetch.apply_invoice.assert_not_awaited()


@pytest.mark.asyncio
async def test_endpoint_surfaces_card_decline_reason() -> None:
    """A declined retry returns 500 whose detail is Stripe's own reason.

    Stripe writes ``user_message`` to be shown to an end user, so the handler
    surfaces it rather than a generic "Failed to retry".
    """
    from fastapi import HTTPException

    from src.memberships.memberships_router import retry_membership_card

    auth = MagicMock()
    auth.get_current_user = MagicMock(return_value={})
    auth.verify_gym_employee_for_member = AsyncMock(return_value=None)

    decline = stripe.CardError(
        "Your card has insufficient funds.",
        param=None,
        code="card_declined",
    )
    service = MagicMock()
    service.retry_card = AsyncMock(side_effect=decline)
    tasks_service = MagicMock()
    tasks_service.assert_memberships_not_in_task = AsyncMock(return_value=None)

    with pytest.raises(HTTPException) as caught:
        await retry_membership_card(
            request=MagicMock(),
            credentials=MagicMock(),
            auth=auth,
            memberships_service=service,
            tasks_service=tasks_service,
        )

    assert caught.value.status_code == 500
    assert caught.value.detail == "Your card has insufficient funds."
