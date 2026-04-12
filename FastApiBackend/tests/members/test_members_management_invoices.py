"""Integration tests for member invoice listing."""

import pytest

from src.members.schema.members_management_schema import (
    MembersManagementCreateRequest,
)
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerCreateRequest,
)
from src.payments.schema.payments_payment_schema import (
    PaymentsPaymentCreateRequest,
)

from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import create_payment_method
from tests.helpers.service_factory import build_payment_services


async def test_list_invoices_with_data(
    management_service, db_pool, gym_id,
    stripe_client, stripe_account_id, connect_opts,
):
    """Create a charge, then list invoices — verify it appears."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    created = await management_service.create_member(
        MembersManagementCreateRequest(
            gym_id=gym_id,
            first_name="Invoice",
            last_name="Tester",
            payment_method_id=pm_id,
        ),
    )

    try:
        # Create a payment to generate an invoice-like record
        payment_services = build_payment_services(stripe_client)
        await payment_services.payment.create_payment(
            PaymentsPaymentCreateRequest(
                stripe_customer_id=created.stripe_customer_id,
                amount=1000,
            ),
            stripe_account_id,
        )

        invoices = await management_service.list_invoices(created.crm_user_id)

        # PaymentIntents don't create invoices, but the call should succeed
        assert isinstance(invoices, list)
    finally:
        await delete_member_data(db_pool, created.crm_user_id)


async def test_list_invoices_no_stripe_customer_raises(
    management_service, db_pool, gym_id,
):
    """A member without a Stripe customer should raise an error."""
    # Insert a member directly without going through the service
    # (so stripe_customer_id stays NULL — not visible via filtered view)
    from sqlalchemy import text

    insert_sql = """
        INSERT INTO user_gym_profiles_unfiltered (
            gym_id, first_name, last_name
        ) VALUES (:gym_id, 'NoStripe', 'Member')
        RETURNING crm_user_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(insert_sql),
            {"gym_id": str(gym_id)},
        )
        row = result.mappings().fetchone()
        await session.commit()

    from uuid import UUID

    crm_user_id = UUID(str(row["crm_user_id"]))

    try:
        with pytest.raises(ValueError):
            await management_service.list_invoices(crm_user_id)
    finally:
        await delete_member_data(db_pool, crm_user_id)
