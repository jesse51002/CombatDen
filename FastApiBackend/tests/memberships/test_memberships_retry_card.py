"""Unit tests for retry-card (no DB / Stripe / network).

``MemberMembershipsRetryCard`` is the CARD twin of
``MemberMembershipsMarkPaidCash``: identical validations and payer
resolution, but it delegates to ``pay_open_subscription_invoice_on_card`` so
Stripe charges the payer's saved DEFAULT card instead of settling the invoice
out of band.

Scenarios (mirroring the mark-paid-cash boundary cases in
``test_memberships_cash.py``, at unit level):

1. ``test_retry_card_pays_open_invoice_on_card`` — happy path: the payment
   service is called with the PAYER's monthly subscription, the gym's Connect
   account, and the op's idempotency key — and the out-of-band (cash) path is
   never touched.
2. ``test_retry_card_non_recurring_rejected`` — a one_time membership raises
   ``ValueError`` before any Stripe call.
3. ``test_retry_card_unlinked_membership_rejected`` — a membership with no
   ``stripe_item_id`` raises ``ValueError`` before any Stripe call.
4. ``test_retry_card_canceled_membership_rejected`` — a membership whose
   ``cancel_date`` has passed raises ``ValueError`` (staff re-enroll instead
   of paying a dead membership).
5. ``test_retry_card_no_open_invoice_raises`` — the payment service's "no open
   invoice" ``ValueError`` propagates; nothing swallows it.
6. ``test_retry_card_declined_propagates`` — a Stripe decline propagates to
   the caller (a failed retry must never read as success).
"""

from datetime import timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
import stripe
from schema.membership_plan import PlanType

from src.memberships.service.memberships_retry_card import (
    MemberMembershipsRetryCard,
)
from src.shared.gym_timezone import gym_today
from src.shared.payer_profile import PayerProfile

GYM_TIMEZONE = "America/Chicago"
STRIPE_ACCOUNT_ID = "acct_test_retry_card"
STRIPE_SUB_ID = "sub_test_retry_card"


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
        "stripe_price_id": "price_test_retry_card",
        "stripe_item_id": "si_test_retry_card",
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


def _build_service(
    row: dict,
    *,
    sub_id: str | None = STRIPE_SUB_ID,
) -> tuple[MemberMembershipsRetryCard, MagicMock]:
    """Build the service over doubles; return it plus the payment service."""
    payment_service = MagicMock()
    payment_service.pay_open_subscription_invoice_on_card = AsyncMock(
        return_value="in_test_retry_card",
    )
    payment_service.pay_open_subscription_invoice_out_of_band = AsyncMock()

    payer_resolver = MagicMock()
    payer_resolver.resolve_payer = AsyncMock(
        return_value=PayerProfile(
            member_id=row["paid_by_member_id"],
            gym_id=row["gym_id"],
            stripe_customer_id="cus_test_retry_card",
            stripe_sub_id_month=sub_id,
            timezone=GYM_TIMEZONE,
        ),
    )

    gym_stripe_service = MagicMock()
    gym_stripe_service.get_stripe_account_id = AsyncMock(
        return_value=STRIPE_ACCOUNT_ID,
    )

    service = MemberMembershipsRetryCard(
        _db_pool_returning(row),
        MagicMock(),
        gym_stripe_service,
        payment_service=payment_service,
        payer_resolver=payer_resolver,
    )
    return service, payment_service


@pytest.mark.asyncio
async def test_retry_card_pays_open_invoice_on_card() -> None:
    row = _membership_row()
    service, payment_service = _build_service(row)
    idempotency_key = uuid4()

    await service.retry_card(uuid4(), row["member_id"], idempotency_key)

    payment_service.pay_open_subscription_invoice_on_card.assert_awaited_once_with(
        stripe_subscription_id=STRIPE_SUB_ID,
        stripe_account_id=STRIPE_ACCOUNT_ID,
        idempotency_key=str(idempotency_key),
    )
    # The card retry must never route through the cash (out-of-band) path.
    payment_service.pay_open_subscription_invoice_out_of_band.assert_not_awaited()


@pytest.mark.asyncio
async def test_retry_card_non_recurring_rejected() -> None:
    row = _membership_row(plan_type=PlanType.one_time.value)
    service, payment_service = _build_service(row)

    with pytest.raises(ValueError, match="only applies to recurring"):
        await service.retry_card(uuid4(), row["member_id"], uuid4())

    payment_service.pay_open_subscription_invoice_on_card.assert_not_awaited()


@pytest.mark.asyncio
async def test_retry_card_unlinked_membership_rejected() -> None:
    row = _membership_row(stripe_item_id=None)
    service, payment_service = _build_service(row)

    with pytest.raises(ValueError, match="not linked to a Stripe subscription"):
        await service.retry_card(uuid4(), row["member_id"], uuid4())

    payment_service.pay_open_subscription_invoice_on_card.assert_not_awaited()


@pytest.mark.asyncio
async def test_retry_card_canceled_membership_rejected() -> None:
    row = _membership_row(
        cancel_date=gym_today(GYM_TIMEZONE) - timedelta(days=1),
    )
    service, payment_service = _build_service(row)

    with pytest.raises(ValueError, match="canceled membership"):
        await service.retry_card(uuid4(), row["member_id"], uuid4())

    payment_service.pay_open_subscription_invoice_on_card.assert_not_awaited()


@pytest.mark.asyncio
async def test_retry_card_no_monthly_subscription_rejected() -> None:
    row = _membership_row()
    service, payment_service = _build_service(row, sub_id=None)

    with pytest.raises(ValueError, match="No active monthly subscription"):
        await service.retry_card(uuid4(), row["member_id"], uuid4())

    payment_service.pay_open_subscription_invoice_on_card.assert_not_awaited()


@pytest.mark.asyncio
async def test_retry_card_no_open_invoice_raises() -> None:
    row = _membership_row()
    service, payment_service = _build_service(row)
    payment_service.pay_open_subscription_invoice_on_card.side_effect = (
        ValueError("This invoice is already settled — nothing left to collect.")
    )

    with pytest.raises(ValueError, match="already settled"):
        await service.retry_card(uuid4(), row["member_id"], uuid4())


@pytest.mark.asyncio
async def test_retry_card_declined_propagates() -> None:
    """A declined retry must surface — never be swallowed into a success."""
    row = _membership_row()
    service, payment_service = _build_service(row)
    payment_service.pay_open_subscription_invoice_on_card.side_effect = (
        stripe.CardError(
            "Your card was declined.",
            param=None,
            code="card_declined",
        )
    )

    with pytest.raises(stripe.CardError):
        await service.retry_card(uuid4(), row["member_id"], uuid4())


@pytest.mark.asyncio
async def test_endpoint_surfaces_card_decline_reason() -> None:
    """A declined retry returns 500 whose detail is Stripe's own reason.

    The whole value of the button is that staff learn WHY it failed (expired
    -> Update Card; insufficient funds -> tell the member). Stripe writes
    ``user_message`` to be shown to an end user, so the handler surfaces it
    rather than a generic "Failed to retry".
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
