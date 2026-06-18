"""Integration tests for PaymentsStripePaymentService."""

from uuid import uuid4

from schema.membership_plan import DurationUnit, PlanType

from src.payments.schema.metadata.stripe_customer_metadata import (
    StripeCustomerMetadata,
)
from src.payments.schema.metadata.stripe_membership_one_time_metadata import (
    StripeMembershipOneTimeMetadata,
)
from src.payments.schema.metadata.stripe_product_metadata import (
    StripeProductMetadata,
)
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerCreateRequest,
)
from src.payments.schema.payments_membership_schema import (
    PaymentsMembershipCreateRequest,
    PaymentsMembershipPriceItem,
)
from src.payments.schema.payments_payment_schema import (
    PaymentsInvoiceItemSpec,
    PaymentsInvoicePaymentCreateRequest,
    PaymentsInvoicePaymentPreviewRequest,
    PaymentsRefundRequest,
)
from tests.helpers.data_factory import create_payment_method

# ── Helpers ─────────────────────────────────────────────────────


async def _customer_with_card(
    members_service, stripe_client, stripe_account_id, connect_opts, created
):
    """Create a Stripe customer with a Visa card attached."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    resp = await members_service.create_customer(
        PaymentsCustomerCreateRequest(
            name="Payment Test",
            payment_method_id=pm_id,
            metadata=StripeCustomerMetadata(
                member_id=uuid4(),
                gym_id=uuid4(),
            ),
        ),
        stripe_account_id,
    )
    created.track_customer(resp.stripe_customer_id)
    return resp.stripe_customer_id


async def _one_time_price(membership_service, stripe_account_id, created, unit_amount: int = 2000):
    """Create a Stripe product with a one-time price."""
    resp = await membership_service.create_membership(
        PaymentsMembershipCreateRequest(
            plan_name="One-Time Payment Test",
            prices=[
                PaymentsMembershipPriceItem(
                    unit_amount=unit_amount,
                    plan_type=PlanType.one_time,
                    recurring_interval=DurationUnit.month,
                    recurring_interval_count=1,
                    is_default=True,
                ),
            ],
            metadata=StripeProductMetadata(
                plan_id=uuid4(),
                gym_id=uuid4(),
            ),
        ),
        stripe_account_id,
    )
    created.track_product(resp.stripe_product_id)
    for p in resp.prices:
        created.track_price(p.stripe_price_id)
    return resp.prices[0].stripe_price_id


# ── Tests ───────────────────────────────────────────────────────


async def _paid_invoice_charge_id(
    payment_service,
    customer_id,
    price_id,
    stripe_client,
    stripe_account_id,
    connect_opts,
):
    """Pay an invoice and return its Stripe charge id (``ch_…``)."""
    resp = await payment_service.create_invoice_payment(
        PaymentsInvoicePaymentCreateRequest(
            stripe_customer_id=customer_id,
            items=[PaymentsInvoiceItemSpec(stripe_price_id=price_id)],
            idempotency_key=str(uuid4()),
            metadata=StripeMembershipOneTimeMetadata(
                member_id=uuid4(),
                gym_id=uuid4(),
                plan_id=uuid4(),
            ),
        ),
        stripe_account_id,
    )
    invoice = await stripe_client.client.v1.invoices.retrieve_async(
        resp.stripe_invoice_id,
        params={"expand": ["payments"]},
        options=connect_opts,
    )
    payments = invoice.payments.data if invoice.payments else []
    assert payments, f"Invoice {invoice.id} has no payments"
    pi_id = payments[0].payment.payment_intent
    pi = await stripe_client.client.v1.payment_intents.retrieve_async(
        pi_id,
        options=connect_opts,
    )
    return pi.latest_charge


async def test_create_invoice_payment(
    payment_service,
    members_service,
    membership_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    customer_id = await _customer_with_card(
        members_service,
        stripe_client,
        stripe_account_id,
        connect_opts,
        created,
    )
    price_id = await _one_time_price(membership_service, stripe_account_id, created)

    resp = await payment_service.create_invoice_payment(
        PaymentsInvoicePaymentCreateRequest(
            stripe_customer_id=customer_id,
            items=[PaymentsInvoiceItemSpec(stripe_price_id=price_id)],
            idempotency_key=str(uuid4()),
            metadata=StripeMembershipOneTimeMetadata(
                member_id=uuid4(),
                gym_id=uuid4(),
                plan_id=uuid4(),
            ),
        ),
        stripe_account_id,
    )

    assert resp.stripe_invoice_id.startswith("in_")
    assert resp.amount_paid == 2000
    assert resp.status == "paid"

    inv = await stripe_client.client.v1.invoices.retrieve_async(
        resp.stripe_invoice_id,
        options=connect_opts,
    )
    assert inv.status == "paid"
    assert inv.amount_paid == 2000


async def test_create_invoice_payment_zero_amount(
    payment_service,
    members_service,
    membership_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    """$0 invoices must not re-invoke pay_async after finalize."""
    customer_id = await _customer_with_card(
        members_service,
        stripe_client,
        stripe_account_id,
        connect_opts,
        created,
    )
    price_id = await _one_time_price(
        membership_service,
        stripe_account_id,
        created,
        unit_amount=0,
    )

    resp = await payment_service.create_invoice_payment(
        PaymentsInvoicePaymentCreateRequest(
            stripe_customer_id=customer_id,
            items=[PaymentsInvoiceItemSpec(stripe_price_id=price_id)],
            idempotency_key=str(uuid4()),
            metadata=StripeMembershipOneTimeMetadata(
                member_id=uuid4(),
                gym_id=uuid4(),
                plan_id=uuid4(),
            ),
        ),
        stripe_account_id,
    )

    assert resp.stripe_invoice_id.startswith("in_")
    assert resp.amount_paid == 0
    assert resp.status == "paid"

    inv = await stripe_client.client.v1.invoices.retrieve_async(
        resp.stripe_invoice_id,
        options=connect_opts,
    )
    assert inv.status == "paid"
    assert inv.amount_paid == 0
    assert inv.amount_due == 0


async def test_preview_invoice_payment(
    payment_service,
    members_service,
    membership_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    customer_id = await _customer_with_card(
        members_service,
        stripe_client,
        stripe_account_id,
        connect_opts,
        created,
    )
    price_id = await _one_time_price(membership_service, stripe_account_id, created)

    resp = await payment_service.preview_invoice_payment(
        PaymentsInvoicePaymentPreviewRequest(
            stripe_customer_id=customer_id,
            items=[PaymentsInvoiceItemSpec(stripe_price_id=price_id)],
        ),
        stripe_account_id,
    )

    assert resp.amount_due == 2000
    assert len(resp.lines) >= 1


async def test_refund_full_payment(
    payment_service,
    members_service,
    membership_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    customer_id = await _customer_with_card(
        members_service,
        stripe_client,
        stripe_account_id,
        connect_opts,
        created,
    )
    price_id = await _one_time_price(
        membership_service,
        stripe_account_id,
        created,
        unit_amount=3000,
    )
    charge_id = await _paid_invoice_charge_id(
        payment_service,
        customer_id,
        price_id,
        stripe_client,
        stripe_account_id,
        connect_opts,
    )

    resp = await payment_service.refund_payment(
        PaymentsRefundRequest(
            stripe_charge_id=charge_id,
            idempotency_key=str(uuid4()),
        ),
        stripe_account_id,
    )

    assert resp.stripe_refund_id.startswith("re_")
    assert resp.stripe_charge_id == charge_id
    assert resp.amount == 3000
    assert resp.status == "succeeded"

    refund = await stripe_client.client.v1.refunds.retrieve_async(
        resp.stripe_refund_id,
        options=connect_opts,
    )
    assert refund.status == "succeeded"
    assert refund.amount == 3000
    assert refund.charge == charge_id


async def test_refund_partial_payment(
    payment_service,
    members_service,
    membership_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    customer_id = await _customer_with_card(
        members_service,
        stripe_client,
        stripe_account_id,
        connect_opts,
        created,
    )
    price_id = await _one_time_price(
        membership_service,
        stripe_account_id,
        created,
        unit_amount=5000,
    )
    charge_id = await _paid_invoice_charge_id(
        payment_service,
        customer_id,
        price_id,
        stripe_client,
        stripe_account_id,
        connect_opts,
    )

    resp = await payment_service.refund_payment(
        PaymentsRefundRequest(
            stripe_charge_id=charge_id,
            amount=2000,
            idempotency_key=str(uuid4()),
        ),
        stripe_account_id,
    )

    assert resp.amount == 2000
    assert resp.status == "succeeded"

    refund = await stripe_client.client.v1.refunds.retrieve_async(
        resp.stripe_refund_id,
        options=connect_opts,
    )
    assert refund.amount == 2000
    assert refund.status == "succeeded"
