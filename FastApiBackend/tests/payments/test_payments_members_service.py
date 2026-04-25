"""Integration tests for PaymentsStripeMembersService."""

from uuid import uuid4

import pytest

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.metadata.stripe_customer_metadata import (
    StripeCustomerMetadata,
)
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerCreateRequest,
    PaymentsCustomerUpdateRequest,
)
from tests.helpers.data_factory import create_payment_method


def _customer_metadata() -> StripeCustomerMetadata:
    return StripeCustomerMetadata(
        crm_user_id=uuid4(),
        gym_id=uuid4(),
    )


async def test_create_customer_without_payment(
    members_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
):
    resp = await members_service.create_customer(
        PaymentsCustomerCreateRequest(
            name="Jane Doe",
            email="jane@test.com",
            metadata=_customer_metadata(),
        ),
        stripe_account_id,
    )

    assert resp.stripe_customer_id.startswith("cus_")
    assert resp.name == "Jane Doe"
    assert resp.email == "jane@test.com"
    assert resp.stripe_payment_method_id is None
    assert resp.card_brand is None

    customer = await stripe_client.client.v1.customers.retrieve_async(
        resp.stripe_customer_id,
        options=connect_opts,
    )
    assert customer.name == "Jane Doe"
    assert customer.email == "jane@test.com"
    assert getattr(customer, "deleted", False) is False


async def test_create_customer_with_payment_method(
    members_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)

    resp = await members_service.create_customer(
        PaymentsCustomerCreateRequest(
            name="John Doe",
            email="john@test.com",
            payment_method_id=pm_id,
            metadata=_customer_metadata(),
        ),
        stripe_account_id,
    )

    assert resp.stripe_customer_id.startswith("cus_")
    assert resp.stripe_payment_method_id == pm_id
    assert resp.card_brand == "visa"
    assert resp.card_last_four == "4242"
    assert resp.card_exp_month is not None
    assert resp.card_exp_year is not None

    # Independent: the customer must actually have pm_id as its default.
    customer = await stripe_client.client.v1.customers.retrieve_async(
        resp.stripe_customer_id,
        options=connect_opts,
    )
    default_pm = (
        customer.invoice_settings.default_payment_method
        if customer.invoice_settings is not None
        else None
    )
    default_pm_id = default_pm if isinstance(default_pm, str) else getattr(default_pm, "id", None)
    assert default_pm_id == pm_id


async def test_update_customer_swap_payment_method(
    members_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
):
    pm1 = await create_payment_method(stripe_client, connect_opts)
    created = await members_service.create_customer(
        PaymentsCustomerCreateRequest(
            name="Swap Card",
            payment_method_id=pm1,
            metadata=_customer_metadata(),
        ),
        stripe_account_id,
    )

    pm2 = await create_payment_method(stripe_client, connect_opts)
    resp = await members_service.update_customer(
        PaymentsCustomerUpdateRequest(
            stripe_customer_id=created.stripe_customer_id,
            name="Swap Card",
            payment_method_id=pm2,
            metadata=_customer_metadata(),
        ),
        stripe_account_id,
    )

    assert resp.stripe_payment_method_id == pm2

    customer = await stripe_client.client.v1.customers.retrieve_async(
        created.stripe_customer_id,
        options=connect_opts,
    )
    default_pm = customer.invoice_settings.default_payment_method
    default_pm_id = default_pm if isinstance(default_pm, str) else getattr(default_pm, "id", None)
    assert default_pm_id == pm2


async def test_unlink_customer_card(
    members_service,
    stripe_client,
    stripe_account_id,
    connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    created = await members_service.create_customer(
        PaymentsCustomerCreateRequest(
            name="Unlink Card",
            payment_method_id=pm_id,
            metadata=_customer_metadata(),
        ),
        stripe_account_id,
    )

    await members_service.unlink_customer_card(
        created.stripe_customer_id,
        stripe_account_id,
    )

    # Verify customer has no default PM
    opts = members_service._client.connect_opts(stripe_account_id)
    customer = await members_service.retrieve_customer(
        created.stripe_customer_id,
        opts,
    )
    default_pm = None
    if customer.invoice_settings:
        default_pm = customer.invoice_settings.default_payment_method
    assert default_pm is None or default_pm == ""


async def test_list_invoices_empty(members_service, stripe_account_id, connect_opts):
    created = await members_service.create_customer(
        PaymentsCustomerCreateRequest(
            name="No Invoices",
            metadata=_customer_metadata(),
        ),
        stripe_account_id,
    )

    invoices = await members_service.list_invoices(
        created.stripe_customer_id,
        stripe_account_id,
    )

    assert invoices == []


async def test_retrieve_nonexistent_customer_raises(
    members_service,
    stripe_account_id,
):
    opts = members_service._client.connect_opts(stripe_account_id)
    with pytest.raises(PaymentsResourceNotFoundError):
        await members_service.retrieve_customer("cus_nonexistent_000", opts)
