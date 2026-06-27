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
"""

import json
from uuid import uuid4

import pytest

from src.memberships.memberships_schema import (
    MemberMembershipsChargeCardRequest,
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
