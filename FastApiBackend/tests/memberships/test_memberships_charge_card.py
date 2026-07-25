"""Integration tests for the charge-card flow.

Five scenarios:

1. ``test_charge_card_creates_paid_invoice`` — card is charged for an
   ad-hoc amount. Exactly one new Stripe invoice exists, is paid, and
   carries the ``reason`` as its description.

2. ``test_charge_card_with_cash_marks_invoice_paid_out_of_band`` —
   ``paid_cash=True`` creates the invoice, pays it out of band, tags
   it with ``crm_paid_with_cash`` metadata, and does not charge the
   customer's card.

3. ``test_charge_card_is_idempotent_on_repeat`` — two calls with the
   same ``idempotency_key`` produce exactly one Stripe invoice.

4. ``test_charge_card_gym_mismatch_raises`` — passing a ``gym_id``
   that does not match the member's profile raises ``ValueError``
   and creates no Stripe invoice.

5. ``test_charge_card_with_one_off_card_keeps_saved_default`` — a
   ``payment_method_id`` bills a one-off card (attach → pay → detach):
   the invoice is paid, the one-off card is detached afterward, and the
   customer's saved default payment method is left unchanged.

Plus the ROUTER contract (unit, no DB / Stripe / network), pinning the three
outcomes this endpoint can answer with:

6. ``test_endpoint_returns_not_collected_as_207_result`` — a definitive
   NOT-COLLECTED (``PaymentsNotCollectedError``: nothing refused, nothing
   collected — SCA) is a 207 RESULT carrying its own reason, never the 500 it
   used to get by falling through to the base ``PaymentsStripeError`` arm.
7. ``test_endpoint_returns_card_decline_as_207_result`` — a bank DECLINE is
   likewise a 207 RESULT carrying Stripe's own end-user wording. ``CardError``
   subclasses none of the typed arms, so without its own arm it lands on the
   blanket ``except Exception`` and the reason is lost entirely.
8. ``test_endpoint_success_is_still_204_with_no_body`` — the SUCCESS contract
   is untouched: a collected charge stays 204 with an empty body, so every
   existing caller keeps working.
9. ``test_endpoint_unrecognised_stripe_failure_is_still_500`` — the base
   ``PaymentsStripeError`` is STILL a 500. This is the ORDERING guard: the
   not-collected arm must sit ABOVE it (subclass), and this test is what fails
   if the two are ever swapped.
"""

import json
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
import stripe

from src.memberships.memberships_schema import (
    MemberMembershipsChargeCardRequest,
    MemberMembershipsRetryCardStatus,
)
from src.payments.payments_exceptions import (
    PaymentsNotCollectedError,
    PaymentsStripeError,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.stripe_assertions import snapshot_billing_state


async def _list_invoices(stripe_client, customer_id, connect_opts):
    result = await stripe_client.client.v1.invoices.list_async(
        params={"customer": customer_id, "limit": 100},
        options=connect_opts,
    )
    return result.data or []


async def test_charge_card_creates_paid_invoice(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Card charge creates and pays exactly one invoice."""
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.charge_card(
            MemberMembershipsChargeCardRequest(
                member_id=member.member_id,
                paid_by_member_id=member.member_id,
                gym_id=gym_id,
                amount_cents=1234,
                reason="Pro-shop T-shirt",
                paid_cash=False,
                idempotency_key=uuid4(),
            ),
        )

        after = await _list_invoices(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )
        new_invoices = [inv for inv in after if inv.id not in before.invoice_ids]
        assert len(new_invoices) == 1, f"Expected exactly 1 new invoice, got {len(new_invoices)}"
        invoice = new_invoices[0]
        assert invoice.status == "paid"
        assert invoice.amount_paid == 1234
        assert invoice.description == "Pro-shop T-shirt"
        # Card charge — no cash metadata.
        md = invoice.metadata.to_dict()
        assert md.get("crm_paid_with_cash") != "true"
        assert md.get("crm_one_time_payment") == "true"
        # Payer + beneficiary attribution rides in metadata (self-pay here, so
        # both are the member); paid_for is a JSON-array string.
        assert md.get("paid_by_member_id") == str(member.member_id)
        assert json.loads(md.get("paid_for")) == [str(member.member_id)]
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_charge_card_with_cash_marks_invoice_paid_out_of_band(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """``paid_cash=True`` pays the invoice out of band (no card charge)."""
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.charge_card(
            MemberMembershipsChargeCardRequest(
                member_id=member.member_id,
                paid_by_member_id=member.member_id,
                gym_id=gym_id,
                amount_cents=2500,
                reason="Late fee",
                paid_cash=True,
                idempotency_key=uuid4(),
            ),
        )

        after = await _list_invoices(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )
        new_invoices = [inv for inv in after if inv.id not in before.invoice_ids]
        assert len(new_invoices) == 1
        invoice = new_invoices[0]
        assert invoice.status == "paid"
        assert invoice.amount_paid == 2500
        assert invoice.metadata.to_dict().get("crm_paid_with_cash") == "true"
        assert invoice.metadata.to_dict().get("crm_one_time_payment") == "true"

        # Customer balance must not move (out-of-band = no card charge).
        customer = await stripe_client.client.v1.customers.retrieve_async(
            member.stripe_customer_id,
            options=connect_opts,
        )
        assert (customer.balance or 0) == before.customer_balance
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_charge_card_is_idempotent_on_repeat(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Two calls with the same idempotency_key produce one invoice."""
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        shared_key = uuid4()
        request_fn = lambda: MemberMembershipsChargeCardRequest(  # noqa: E731
            member_id=member.member_id,
            paid_by_member_id=member.member_id,
            gym_id=gym_id,
            amount_cents=4200,
            reason="Duplicate fire",
            paid_cash=False,
            idempotency_key=shared_key,
        )

        await memberships_service.charge_card(request_fn())
        await memberships_service.charge_card(request_fn())

        after = await _list_invoices(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )
        new_invoices = [inv for inv in after if inv.id not in before.invoice_ids]
        assert len(new_invoices) == 1, (
            f"Idempotency failed: got {len(new_invoices)} new invoices, "
            f"ids={[inv.id for inv in new_invoices]}"
        )
        assert new_invoices[0].status == "paid"
        assert new_invoices[0].amount_paid == 4200
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_charge_card_with_one_off_card_keeps_saved_default(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A one-off ``payment_method_id`` bills once, detaches, and leaves
    the saved default unchanged."""
    saved_pm = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=saved_pm)
    one_off_pm = await created.payment_method()

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )
        customer_before = await stripe_client.client.v1.customers.retrieve_async(
            member.stripe_customer_id,
            options=connect_opts,
        )

        await memberships_service.charge_card(
            MemberMembershipsChargeCardRequest(
                member_id=member.member_id,
                paid_by_member_id=member.member_id,
                gym_id=gym_id,
                amount_cents=3300,
                reason="One-off card charge",
                paid_cash=False,
                payment_method_id=one_off_pm,
                idempotency_key=uuid4(),
            ),
        )

        after = await _list_invoices(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )
        new_invoices = [inv for inv in after if inv.id not in before.invoice_ids]
        assert len(new_invoices) == 1, f"Expected 1 new invoice, got {len(new_invoices)}"
        invoice = new_invoices[0]
        assert invoice.status == "paid"
        assert invoice.amount_paid == 3300

        # The saved default never changed (the one-off never became default).
        customer_after = await stripe_client.client.v1.customers.retrieve_async(
            member.stripe_customer_id,
            options=connect_opts,
        )
        assert (
            customer_after.invoice_settings.default_payment_method
            == customer_before.invoice_settings.default_payment_method
        )

        # The one-off card was detached after paying (not left on the customer).
        pm = await stripe_client.client.v1.payment_methods.retrieve_async(
            one_off_pm,
            options=connect_opts,
        )
        assert pm.customer is None, "one-off card should be detached after charge"
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_charge_card_gym_mismatch_raises(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A gym_id that does not match the member's profile must raise."""
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        wrong_gym_id = uuid4()
        with pytest.raises(ValueError, match="not in gym"):
            await memberships_service.charge_card(
                MemberMembershipsChargeCardRequest(
                    member_id=member.member_id,
                    paid_by_member_id=member.member_id,
                    gym_id=wrong_gym_id,
                    amount_cents=1000,
                    reason="Should fail",
                    paid_cash=False,
                    idempotency_key=uuid4(),
                ),
            )

        after = await _list_invoices(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )
        new_invoices = [inv for inv in after if inv.id not in before.invoice_ids]
        assert new_invoices == [], "No invoice should have been created"
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Router contract (unit — no DB, no Stripe, no network) ────────────────


def _charge_request() -> MemberMembershipsChargeCardRequest:
    """A real charge-card body (the 207 echoes its ids, so no MagicMock)."""
    return MemberMembershipsChargeCardRequest(
        member_id=uuid4(),
        paid_by_member_id=uuid4(),
        gym_id=uuid4(),
        amount_cents=2500,
        reason="Pro-shop gloves",
        idempotency_key=uuid4(),
    )


def _charge_router_doubles(*, side_effect=None):
    """``(auth, service)`` doubles for the charge-card handler."""
    auth = MagicMock()
    auth.get_current_user = MagicMock(return_value={})
    auth.verify_gym_employee_for_member = AsyncMock(return_value=None)

    service = MagicMock()
    service.charge_card = AsyncMock(side_effect=side_effect, return_value=None)
    return auth, service


async def test_endpoint_returns_not_collected_as_207_result() -> None:
    """A definitive NOT-COLLECTED is a 207 RESULT, not a 500.

    ``invoices.pay`` returned without raising, but the invoice never reached
    ``paid`` because the off-session PaymentIntent needs authentication (SCA /
    3-D Secure). Nobody refused and nothing malfunctioned — the money simply
    was not collected and staff must act. A 500 there reports an outage, buries
    real outages in monitoring, and tells the front desk nothing.

    ``PaymentsNotCollectedError`` subclasses ``PaymentsStripeError``, so before
    the dedicated arm this fell through to the base arm and answered 500.
    """
    from src.memberships.memberships_router import charge_member_card

    reason = (
        "The card on file could not be charged automatically — the payment "
        "needs extra authorization the member has to complete. Collect payment "
        "another way."
    )
    auth, service = _charge_router_doubles(
        side_effect=PaymentsNotCollectedError(reason),
    )
    request = _charge_request()

    result = await charge_member_card(
        request=request,
        credentials=MagicMock(),
        auth=auth,
        memberships_service=service,
    )

    assert result.status_code == 207
    body = json.loads(result.body)
    assert body["status"] == MemberMembershipsRetryCardStatus.not_collected
    # Distinguishable from a decline: its own status AND a reason that never
    # tells staff the card was refused (nobody refused).
    assert body["status"] != MemberMembershipsRetryCardStatus.declined
    assert body["decline_reason"] == reason
    assert "declin" not in body["decline_reason"].lower()
    # The identity echo staff need: whose charge, and whose card went uncharged.
    assert body["member_id"] == str(request.member_id)
    assert body["paid_by_member_id"] == str(request.paid_by_member_id)


async def test_endpoint_returns_card_decline_as_207_result() -> None:
    """A bank DECLINE is a 207 RESULT carrying the bank's own reason.

    ``stripe.CardError`` subclasses neither ``ValueError`` nor
    ``PaymentsStripeError``, so without its own arm it fell past every typed
    arm onto the blanket ``except Exception`` — a 500 whose ``detail`` was the
    generic "Failed to charge member card", with the bank's reason discarded.
    Expired card / insufficient funds at the front desk is far more common here
    than the SCA case.
    """
    from src.memberships.memberships_router import charge_member_card

    auth, service = _charge_router_doubles(
        side_effect=stripe.CardError(
            "Your card has expired.",
            param=None,
            code="expired_card",
        ),
    )
    request = _charge_request()

    result = await charge_member_card(
        request=request,
        credentials=MagicMock(),
        auth=auth,
        memberships_service=service,
    )

    assert result.status_code == 207
    body = json.loads(result.body)
    assert body["status"] == MemberMembershipsRetryCardStatus.declined
    # Stripe's end-user wording, not a swallowed generic — this is what tells
    # staff to ask for another card.
    assert body["decline_reason"] == "Your card has expired."
    assert body["member_id"] == str(request.member_id)
    assert body["paid_by_member_id"] == str(request.paid_by_member_id)


async def test_endpoint_success_is_still_204_with_no_body() -> None:
    """The SUCCESS contract is untouched — a collected charge is a bare 204.

    Adding the 207 must not make success start carrying a body: every existing
    caller reads this endpoint as "204 means charged".
    """
    from src.memberships.memberships_router import charge_member_card

    auth, service = _charge_router_doubles()

    result = await charge_member_card(
        request=_charge_request(),
        credentials=MagicMock(),
        auth=auth,
        memberships_service=service,
    )

    assert result.status_code == 204
    assert result.body == b""


async def test_endpoint_unrecognised_stripe_failure_is_still_500() -> None:
    """An UNRECOGNISED Stripe failure is STILL a 500 — the ordering guard.

    Only a DEFINITIVE answer about the money is a result; a malfunction must
    never read as one. Because ``PaymentsNotCollectedError`` subclasses
    ``PaymentsStripeError``, this test is what fails if the two arms are ever
    swapped — the base arm would then swallow the non-collection and 500 it.
    """
    from fastapi import HTTPException

    from src.memberships.memberships_router import charge_member_card

    auth, service = _charge_router_doubles(
        side_effect=PaymentsStripeError("Stripe is having a bad day"),
    )

    with pytest.raises(HTTPException) as caught:
        await charge_member_card(
            request=_charge_request(),
            credentials=MagicMock(),
            auth=auth,
            memberships_service=service,
        )

    assert caught.value.status_code == 500
    assert caught.value.detail == "Stripe is having a bad day"
