"""Integration tests for the charge-card flow.

Four scenarios:

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
"""

from uuid import uuid4

import pytest

from src.member_memberships.schema.member_memberships_schema import (
    MemberMembershipsChargeCardRequest,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import create_member, create_payment_method
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
):
    """Card charge creates and pays exactly one invoice."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.charge_card(
            MemberMembershipsChargeCardRequest(
                member_id=member.member_id,
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
        assert invoice.metadata.to_dict().get("crm_paid_with_cash") != "true"
        assert invoice.metadata.to_dict().get("crm_one_time_payment") == "true"
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_charge_card_with_cash_marks_invoice_paid_out_of_band(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """``paid_cash=True`` pays the invoice out of band (no card charge)."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.charge_card(
            MemberMembershipsChargeCardRequest(
                member_id=member.member_id,
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
):
    """Two calls with the same idempotency_key produce one invoice."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        shared_key = uuid4()
        request_fn = lambda: MemberMembershipsChargeCardRequest(  # noqa: E731
            member_id=member.member_id,
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


async def test_charge_card_gym_mismatch_raises(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """A gym_id that does not match the member's profile must raise."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )

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
