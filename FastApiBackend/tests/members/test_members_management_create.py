"""Integration tests for member creation (MembersManagementService.create_member)."""

import pytest
from sqlalchemy import text

from src.members.schema.members_management_schema import (
    MembersManagementCreateRequest,
)

from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import create_payment_method


async def test_create_member_without_card(
    management_service, db_pool, gym_id,
):
    resp = await management_service.create_member(
        MembersManagementCreateRequest(
            gym_id=gym_id,
            first_name="Alice",
            last_name="NoCard",
        ),
    )

    try:
        assert resp.crm_user_id is not None
        assert resp.gym_id == gym_id
        assert resp.first_name == "Alice"
        assert resp.stripe_customer_id is not None
        assert resp.stripe_payment_method_id is None
        assert resp.card_brand is None

        # Verify row is visible through the filtered view (has stripe_customer_id)
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT crm_user_id FROM user_gym_profiles "
                    "WHERE crm_user_id = :id"
                ),
                {"id": str(resp.crm_user_id)},
            )
            row = result.mappings().fetchone()
        assert row is not None
    finally:
        await delete_member_data(db_pool, resp.crm_user_id)


async def test_create_member_with_card(
    management_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)

    resp = await management_service.create_member(
        MembersManagementCreateRequest(
            gym_id=gym_id,
            first_name="Bob",
            last_name="HasCard",
            payment_method_id=pm_id,
        ),
    )

    try:
        assert resp.stripe_customer_id is not None
        assert resp.stripe_payment_method_id == pm_id
        assert resp.card_brand == "visa"
        assert resp.card_last_four == "4242"
    finally:
        await delete_member_data(db_pool, resp.crm_user_id)


async def test_create_member_stripe_failure_cleans_pending(
    management_service, db_pool, gym_id,
):
    """An invalid payment_method_id should cause Stripe to fail.

    The pending DB row (with NULL stripe_customer_id) should be
    cleaned up automatically.
    """
    with pytest.raises(Exception):
        await management_service.create_member(
            MembersManagementCreateRequest(
                gym_id=gym_id,
                first_name="Fail",
                last_name="Cleanup",
                payment_method_id="pm_invalid_does_not_exist",
            ),
        )

    # Verify no orphaned pending rows for this name
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT crm_user_id FROM user_gym_profiles_unfiltered "
                "WHERE gym_id = :gym_id AND first_name = 'Fail' "
                "AND stripe_customer_id IS NULL"
            ),
            {"gym_id": str(gym_id)},
        )
        row = result.mappings().fetchone()
    assert row is None
