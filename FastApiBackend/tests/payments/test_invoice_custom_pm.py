"""Integration tests for paying an invoice with a one-off card.

``create_invoice_payment(payment_method_id=...)`` charges a SPECIFIC card
instead of the customer's saved default: attach -> pay -> (optionally) detach,
never touching ``invoice_settings.default_payment_method``. These tests assert
that contract against the real Stripe test Connect account.
"""

from uuid import uuid4

import pytest
from pydantic import ValidationError
from schema.membership_plan import DurationUnit, PlanType

from src.payments.schema.metadata.stripe_ad_hoc_invoice_metadata import (
    StripeAdHocInvoiceMetadata,
)
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
)
from tests.helpers.data_factory import create_payment_method

# ── Helpers ─────────────────────────────────────────────────────


async def _customer_with_pm(
    members_service, stripe_client, stripe_account_id, connect_opts, created
):
    """Create a Stripe customer with a default card; return (customer, pm)."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    resp = await members_service.create_customer(
        PaymentsCustomerCreateRequest(
            name="Custom PM Test",
            payment_method_id=pm_id,
            metadata=StripeCustomerMetadata(
                member_id=uuid4(),
                gym_id=uuid4(),
            ),
        ),
        stripe_account_id,
    )
    created.track_customer(resp.stripe_customer_id)
    return resp.stripe_customer_id, pm_id


async def _one_time_price(membership_service, stripe_account_id, created):
    """Create a Stripe product with a $20 one-time price."""
    resp = await membership_service.create_membership(
        PaymentsMembershipCreateRequest(
            plan_name="Custom PM One-Time",
            prices=[
                PaymentsMembershipPriceItem(
                    unit_amount=2000,
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


def _custom_pm_request(customer_id, price_id, pm_id):
    return PaymentsInvoicePaymentCreateRequest(
        stripe_customer_id=customer_id,
        items=[PaymentsInvoiceItemSpec(stripe_price_id=price_id)],
        idempotency_key=str(uuid4()),
        metadata=StripeMembershipOneTimeMetadata(
            member_id=uuid4(),
            gym_id=uuid4(),
            plan_id=uuid4(),
        ),
        payment_method_id=pm_id,
    )


# ── Tests ───────────────────────────────────────────────────────


async def test_custom_pm_charges_and_leaves_default(
    payment_service,
    members_service,
    membership_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
    created,
):
    """A one-off card pays the invoice; the saved default is untouched and
    the one-off card is always detached after a successful pay."""
    customer_id, default_pm = await _customer_with_pm(
        members_service, stripe_client, stripe_account_id, connect_opts, created
    )
    price_id = await _one_time_price(
        membership_service, stripe_account_id, created
    )
    one_off_pm = await create_payment_method(stripe_client, connect_opts)

    resp = await payment_service.create_invoice_payment(
        _custom_pm_request(customer_id, price_id, one_off_pm),
        stripe_account_id,
    )
    assert resp.status == "paid"
    assert resp.amount_paid == 2000

    customer = await stripe_client.client.v1.customers.retrieve_async(
        customer_id, options=connect_opts
    )
    assert (
        customer.invoice_settings.default_payment_method == default_pm
    ), "the saved default must not change"

    one_off = await stripe_client.client.v1.payment_methods.retrieve_async(
        one_off_pm, options=connect_opts
    )
    assert one_off.customer is None, "the one-off card must be detached"


def test_custom_pm_and_cash_are_mutually_exclusive():
    """Schema rejects a one-off card combined with an out-of-band settle."""
    with pytest.raises(ValidationError):
        PaymentsInvoicePaymentCreateRequest(
            stripe_customer_id="cus_x",
            items=[PaymentsInvoiceItemSpec(amount=1000, description="x")],
            idempotency_key=str(uuid4()),
            metadata=StripeAdHocInvoiceMetadata(
                member_id=uuid4(),
                gym_id=uuid4(),
            ),
            payment_method_id="pm_x",
            paid_out_of_band=True,
        )
