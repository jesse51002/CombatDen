"""``refund_payment``: assembling the response must never un-do a real refund.

By the time ``PaymentsRefundResponse(...)`` is built, ``refunds.create_async``
has already put the money back. A raise there cost two things at once:

* ``MemberMembershipsRefund._refund_card`` never reached ``_insert_refund_row``,
  so the negative ``member_charges`` row was simply missing — the refund existed
  at Stripe and nowhere in the CRM;
* and ``pydantic.ValidationError`` **subclasses ``ValueError``**, so the refund
  router's generic ``except ValueError`` arm answered a COMPLETED refund with
  **400 "bad request"**. Staff read that as "it didn't go through" and retry —
  and because no row was written, ``_assert_refundable_under_lock`` still sees
  the full balance as refundable, so a second real refund goes out (Stripe's
  idempotency key only dedups a retry that reuses the same key).

The response is therefore assembled through ``_response_after_refunding``, which
degrades instead of raising. What it will and will NOT invent is the contract
pinned here: ``currency`` and ``created`` have safe fallbacks so the row still
gets written, but ``status`` is never guessed — an unreadable Stripe answer
reports ``pending``, which routes to the ``refund.*`` webhook backstop rather
than putting a refund into the books on a guess.

Pure unit tests over a fake Stripe client — no network, no DB.
"""

from unittest.mock import AsyncMock, MagicMock

import pytest

from src.payments.schema.payments_payment_schema import PaymentsRefundRequest
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.payments_stripe_payment_service import (
    PaymentsStripePaymentService,
)

STRIPE_ACCOUNT_ID = "acct_test_refund_guard"
CHARGE_ID = "ch_test_refund_guard"
REFUND_ID = "re_test_refund_guard"
IDEMPOTENCY_KEY = "22222222-2222-2222-2222-222222222222"
AMOUNT = 2500


def _refund(**overrides: object) -> MagicMock:
    """A Stripe Refund double; overrides model a field reading back wrong."""
    refund = MagicMock()
    refund.id = REFUND_ID
    refund.amount = AMOUNT
    refund.status = "succeeded"
    refund.currency = "usd"
    refund.created = 1_700_000_000
    for name, value in overrides.items():
        setattr(refund, name, value)
    return refund


def _build_service(refund: MagicMock) -> PaymentsStripePaymentService:
    """The payment service over a Stripe double whose refund create succeeds."""
    fake_stripe = MagicMock()
    fake_stripe.v1.refunds.create_async = AsyncMock(return_value=refund)

    stripe_client = MagicMock()
    stripe_client.client = fake_stripe
    stripe_client.connect_opts = PaymentsStripeClient.connect_opts
    stripe_client.connect_opts_readonly = (
        PaymentsStripeClient.connect_opts_readonly
    )
    return PaymentsStripePaymentService(stripe_client, MagicMock())


def _request(amount: int | None = AMOUNT) -> PaymentsRefundRequest:
    return PaymentsRefundRequest(
        stripe_charge_id=CHARGE_ID,
        amount=amount,
        idempotency_key=IDEMPOTENCY_KEY,
    )


@pytest.mark.asyncio
async def test_clean_refund_reports_exactly_what_stripe_said() -> None:
    """The happy path is untouched — the guard only wraps, never rewrites."""
    service = _build_service(_refund())

    resp = await service.refund_payment(_request(), STRIPE_ACCOUNT_ID)

    assert resp.stripe_refund_id == REFUND_ID
    assert resp.stripe_charge_id == CHARGE_ID
    assert resp.amount == AMOUNT
    assert resp.status == "succeeded"
    assert resp.currency == "usd"
    assert resp.created == 1_700_000_000


@pytest.mark.asyncio
async def test_unreadable_created_still_returns_a_recordable_refund() -> None:
    """The common case: ONE field reads back wrong, and the row must still land.

    ``created`` is the timestamp on the negative ``member_charges`` row. A
    ``None`` there fails ``created: int`` validation — a ``ValueError``, so the
    old code reported a completed refund as a 400 and wrote nothing. Now it
    degrades to now and the caller records the refund.
    """
    service = _build_service(_refund(created=None))

    resp = await service.refund_payment(_request(), STRIPE_ACCOUNT_ID)

    assert resp.stripe_refund_id == REFUND_ID
    assert resp.amount == AMOUNT
    # Still ``succeeded``: Stripe's own answer read back fine, so the caller
    # inserts the negative row — which is the whole point of not raising.
    assert resp.status == "succeeded"
    assert resp.created > 0


@pytest.mark.asyncio
async def test_unreadable_currency_still_returns_a_recordable_refund() -> None:
    """``currency`` is not even used by the caller's row (it takes the CRM
    charge's currency), so losing a refund over it would be pure waste."""
    service = _build_service(_refund(currency=None))

    resp = await service.refund_payment(_request(), STRIPE_ACCOUNT_ID)

    assert resp.status == "succeeded"
    assert resp.amount == AMOUNT
    assert resp.currency == "usd"


@pytest.mark.asyncio
async def test_unreadable_amount_falls_back_to_the_requested_amount() -> None:
    """The caller always passes an explicit amount, so it is a truthful
    fallback — and it keeps the refund recordable."""
    service = _build_service(_refund(amount=None))

    resp = await service.refund_payment(_request(), STRIPE_ACCOUNT_ID)

    assert resp.amount == AMOUNT
    assert resp.status == "succeeded"


@pytest.mark.asyncio
async def test_unreadable_status_is_reported_pending_never_guessed() -> None:
    """The one thing the degraded response refuses to invent.

    A negative ``member_charges`` row is real money in the books. If Stripe's
    own answer cannot be read we do not claim it succeeded — ``pending`` makes
    the caller write nothing and lets the ``refund.*`` webhook record it from
    Stripe's copy, the same backstop a genuinely async refund already uses.
    """
    service = _build_service(_refund(status=None))

    resp = await service.refund_payment(_request(), STRIPE_ACCOUNT_ID)

    assert resp.status == "pending"
    assert resp.stripe_refund_id == REFUND_ID


@pytest.mark.asyncio
async def test_unreadable_refund_id_is_reported_pending() -> None:
    """No usable identity ⇒ nothing recordable (``stripe_refund_id`` is NOT NULL
    for a card refund), so the response must not claim a row can be written."""
    service = _build_service(_refund(id=None))

    resp = await service.refund_payment(_request(), STRIPE_ACCOUNT_ID)

    assert resp.status == "pending"


@pytest.mark.asyncio
async def test_a_broken_refund_object_never_raises() -> None:
    """Everything unreadable at once still returns — the refund happened, so the
    caller's transaction must commit and release the charge-row lock instead of
    dying inside the money window."""
    service = _build_service(
        _refund(id=None, amount=None, status=None, currency=None, created=None),
    )

    resp = await service.refund_payment(
        _request(amount=None), STRIPE_ACCOUNT_ID
    )

    assert resp.status == "pending"
    assert resp.stripe_charge_id == CHARGE_ID
