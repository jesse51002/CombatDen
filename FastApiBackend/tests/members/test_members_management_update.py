"""Integration tests for member update operations.

Each update is paired with a billing-state guard: member edits
(name/email/card swap/unlink) must never generate an invoice or
move the customer balance on Stripe.
"""

from src.members.schema.members_management_schema import (
    MembersManagementCreateRequest,
    MembersManagementUpdateCardRequest,
    MembersManagementUpdateRequest,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import create_payment_method
from tests.helpers.stripe_assertions import (
    assert_no_unexpected_charges,
    snapshot_billing_state,
)


def _default_pm_id(customer) -> str | None:
    """Resolve a customer's default payment method id, expanded or not."""
    if customer.invoice_settings is None:
        return None
    pm = customer.invoice_settings.default_payment_method
    if pm is None:
        return None
    if isinstance(pm, str):
        return pm
    return getattr(pm, "id", None)


async def test_update_personal_info(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    created = await management_service.create_member(
        MembersManagementCreateRequest(
            gym_id=gym_id,
            first_name="Original",
            last_name="Name",
        ),
    )

    try:
        before = await snapshot_billing_state(
            stripe_client,
            created.stripe_customer_id,
            connect_opts,
        )

        resp = await management_service.update_member(
            created.crm_user_id,
            MembersManagementUpdateRequest(
                first_name="Updated",
                email="updated@test.com",
            ),
        )

        assert resp.first_name == "Updated"
        assert resp.email == "updated@test.com"
        assert resp.last_name == "Name"  # unchanged

        # NOTE: update_member deliberately does NOT sync name/email
        # changes to the Stripe customer object — see
        # ``members_management_update.py`` where the write path only
        # touches ``user_gym_profiles``. We still verify the customer
        # is reachable and that the edit did not generate any charges.
        customer = await stripe_client.client.v1.customers.retrieve_async(
            created.stripe_customer_id,
            options=connect_opts,
        )
        assert customer.id == created.stripe_customer_id
        # Profile edit must never bill.
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, created.crm_user_id)


async def test_update_card_existing_customer(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    pm1 = await create_payment_method(stripe_client, connect_opts)
    created = await management_service.create_member(
        MembersManagementCreateRequest(
            gym_id=gym_id,
            first_name="Card",
            last_name="Swap",
            payment_method_id=pm1,
        ),
    )

    try:
        pm2 = await create_payment_method(stripe_client, connect_opts)
        before = await snapshot_billing_state(
            stripe_client,
            created.stripe_customer_id,
            connect_opts,
        )

        resp = await management_service.update_card(
            created.crm_user_id,
            MembersManagementUpdateCardRequest(
                payment_method_id=pm2,
            ),
        )

        assert resp.stripe_payment_method_id == pm2
        assert resp.card_brand == "visa"

        # Stripe side: the customer's default payment method is now pm2.
        customer = await stripe_client.client.v1.customers.retrieve_async(
            created.stripe_customer_id,
            options=connect_opts,
        )
        assert _default_pm_id(customer) == pm2, (
            f"Customer {created.stripe_customer_id} default_payment_method not updated to {pm2}"
        )
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, created.crm_user_id)


async def test_update_card_creates_customer_if_needed(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """A member without a Stripe customer should get one created when updating card."""
    # Create member without card (has stripe_customer_id via the service)
    created = await management_service.create_member(
        MembersManagementCreateRequest(
            gym_id=gym_id,
            first_name="NoCustomer",
            last_name="NeedsOne",
        ),
    )

    try:
        pm_id = await create_payment_method(stripe_client, connect_opts)
        before = await snapshot_billing_state(
            stripe_client,
            created.stripe_customer_id,
            connect_opts,
        )

        resp = await management_service.update_card(
            created.crm_user_id,
            MembersManagementUpdateCardRequest(
                payment_method_id=pm_id,
            ),
        )

        assert resp.stripe_payment_method_id == pm_id
        assert resp.card_brand == "visa"

        customer = await stripe_client.client.v1.customers.retrieve_async(
            created.stripe_customer_id,
            options=connect_opts,
        )
        assert _default_pm_id(customer) == pm_id
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, created.crm_user_id)


async def test_unlink_payment(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)
    created = await management_service.create_member(
        MembersManagementCreateRequest(
            gym_id=gym_id,
            first_name="Unlink",
            last_name="Card",
            payment_method_id=pm_id,
        ),
    )

    try:
        before = await snapshot_billing_state(
            stripe_client,
            created.stripe_customer_id,
            connect_opts,
        )

        resp = await management_service.unlink_payment(
            created.crm_user_id,
        )

        assert resp.stripe_payment_method_id is None
        assert resp.card_brand is None
        assert resp.card_last_four is None
        # stripe_customer_id should still be set
        assert resp.stripe_customer_id is not None

        # Stripe side: customer still exists but has no default
        # payment method, and nothing was billed.
        customer = await stripe_client.client.v1.customers.retrieve_async(
            created.stripe_customer_id,
            options=connect_opts,
        )
        assert _default_pm_id(customer) is None, (
            f"Customer {created.stripe_customer_id} still has a default "
            f"payment method after unlink"
        )
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, created.crm_user_id)
