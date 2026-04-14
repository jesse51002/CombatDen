"""Integration tests for PaymentsStripePaymentService."""

from src.payments.schema.payments_membership_schema import (
    PaymentsMembershipCreateRequest,
    PaymentsMembershipPriceItem,
)
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerCreateRequest,
)
from src.payments.schema.payments_payment_schema import (
    PaymentsInvoicePaymentCreateRequest,
    PaymentsPaymentCreateRequest,
    PaymentsRefundRequest,
)

from schema.membership_plan import DurationUnit, PlanType

from tests.helpers.data_factory import create_payment_method


# ── Helpers ─────────────────────────────────────────────────────


async def _customer_with_card(members_service, stripe_client, stripe_account_id, connect_opts):
    """Create a Stripe customer with a Visa card attached."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    resp = await members_service.create_customer(
        PaymentsCustomerCreateRequest(
            name="Payment Test",
            payment_method_id=pm_id,
        ),
        stripe_account_id,
    )
    return resp.stripe_customer_id


async def _one_time_price(membership_service, stripe_account_id, unit_amount: int = 2000):
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
        ),
        stripe_account_id,
    )
    return resp.prices[0].stripe_price_id


# ── Tests ───────────────────────────────────────────────────────


async def test_create_payment_intent(
    payment_service, members_service, stripe_client,
    stripe_account_id, connect_opts,
):
    customer_id = await _customer_with_card(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )

    resp = await payment_service.create_payment(
        PaymentsPaymentCreateRequest(
            stripe_customer_id=customer_id,
            amount=1500,
            currency="usd",
        ),
        stripe_account_id,
    )

    assert resp.stripe_payment_intent_id.startswith("pi_")
    assert resp.amount == 1500
    assert resp.status == "succeeded"


async def test_create_invoice_payment(
    payment_service, members_service, membership_service,
    stripe_client, stripe_account_id, connect_opts,
):
    customer_id = await _customer_with_card(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    price_id = await _one_time_price(membership_service, stripe_account_id)

    resp = await payment_service.create_invoice_payment(
        PaymentsInvoicePaymentCreateRequest(
            stripe_customer_id=customer_id,
            stripe_price_id=price_id,
        ),
        stripe_account_id,
    )

    assert resp.stripe_invoice_id.startswith("in_")
    assert resp.amount_paid == 2000
    assert resp.status == "paid"


async def test_create_invoice_payment_zero_amount(
    payment_service, members_service, membership_service,
    stripe_client, stripe_account_id, connect_opts,
):
    """$0 invoices must not re-invoke pay_async after finalize."""
    customer_id = await _customer_with_card(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    price_id = await _one_time_price(
        membership_service, stripe_account_id, unit_amount=0,
    )

    resp = await payment_service.create_invoice_payment(
        PaymentsInvoicePaymentCreateRequest(
            stripe_customer_id=customer_id,
            stripe_price_id=price_id,
        ),
        stripe_account_id,
    )

    assert resp.stripe_invoice_id.startswith("in_")
    assert resp.amount_paid == 0
    assert resp.status == "paid"


async def test_preview_invoice_payment(
    payment_service, members_service, membership_service,
    stripe_client, stripe_account_id, connect_opts,
):
    customer_id = await _customer_with_card(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    price_id = await _one_time_price(membership_service, stripe_account_id)

    resp = await payment_service.preview_invoice_payment(
        PaymentsInvoicePaymentCreateRequest(
            stripe_customer_id=customer_id,
            stripe_price_id=price_id,
        ),
        stripe_account_id,
    )

    assert resp.amount_due == 2000
    assert len(resp.lines) >= 1


async def test_refund_full_payment(
    payment_service, members_service, stripe_client,
    stripe_account_id, connect_opts,
):
    customer_id = await _customer_with_card(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    payment = await payment_service.create_payment(
        PaymentsPaymentCreateRequest(
            stripe_customer_id=customer_id,
            amount=3000,
        ),
        stripe_account_id,
    )

    resp = await payment_service.refund_payment(
        PaymentsRefundRequest(
            stripe_payment_intent_id=payment.stripe_payment_intent_id,
        ),
        stripe_account_id,
    )

    assert resp.stripe_refund_id.startswith("re_")
    assert resp.amount == 3000
    assert resp.status == "succeeded"


async def test_refund_partial_payment(
    payment_service, members_service, stripe_client,
    stripe_account_id, connect_opts,
):
    customer_id = await _customer_with_card(
        members_service, stripe_client, stripe_account_id, connect_opts,
    )
    payment = await payment_service.create_payment(
        PaymentsPaymentCreateRequest(
            stripe_customer_id=customer_id,
            amount=5000,
        ),
        stripe_account_id,
    )

    resp = await payment_service.refund_payment(
        PaymentsRefundRequest(
            stripe_payment_intent_id=payment.stripe_payment_intent_id,
            amount=2000,
        ),
        stripe_account_id,
    )

    assert resp.amount == 2000
    assert resp.status == "succeeded"
