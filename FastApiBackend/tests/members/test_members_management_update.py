"""Integration tests for member update operations."""

from src.members.schema.members_management_schema import (
    MembersManagementCreateRequest,
    MembersManagementUpdateCardRequest,
    MembersManagementUpdateRequest,
)

from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import create_payment_method


async def test_update_personal_info(
    management_service, db_pool, gym_id,
):
    created = await management_service.create_member(
        MembersManagementCreateRequest(
            gym_id=gym_id,
            first_name="Original",
            last_name="Name",
        ),
    )

    try:
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
    finally:
        await delete_member_data(db_pool, created.crm_user_id)


async def test_update_card_existing_customer(
    management_service, db_pool, gym_id,
    stripe_client, connect_opts,
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
        resp = await management_service.update_card(
            created.crm_user_id,
            MembersManagementUpdateCardRequest(payment_method_id=pm2),
        )

        assert resp.stripe_payment_method_id == pm2
        assert resp.card_brand == "visa"
    finally:
        await delete_member_data(db_pool, created.crm_user_id)


async def test_update_card_creates_customer_if_needed(
    management_service, db_pool, gym_id,
    stripe_client, connect_opts,
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
        resp = await management_service.update_card(
            created.crm_user_id,
            MembersManagementUpdateCardRequest(payment_method_id=pm_id),
        )

        assert resp.stripe_payment_method_id == pm_id
        assert resp.card_brand == "visa"
    finally:
        await delete_member_data(db_pool, created.crm_user_id)


async def test_unlink_payment(
    management_service, db_pool, gym_id,
    stripe_client, connect_opts,
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
        resp = await management_service.unlink_payment(created.crm_user_id)

        assert resp.stripe_payment_method_id is None
        assert resp.card_brand is None
        assert resp.card_last_four is None
        # stripe_customer_id should still be set
        assert resp.stripe_customer_id is not None
    finally:
        await delete_member_data(db_pool, created.crm_user_id)
