"""Integration tests for member creation (MembersManagementService.create_member).

Each success path also retrieves the Stripe customer to confirm the
CRM's ``stripe_customer_id`` actually points at a real customer and
that no invoices were generated on member creation.
"""

import pytest
from sqlalchemy import text

from src.members.schema.members_schema import MemberCreateRequest
from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import create_payment_method
from tests.helpers.stripe_assertions import (
    assert_no_unexpected_charges,
    snapshot_billing_state,
)


async def test_create_member_without_card(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    resp = await management_service.create_member(
        MemberCreateRequest(
            gym_id=gym_id,
            first_name="Alice",
            last_name="NoCard",
        ),
    )

    try:
        assert resp.member_id is not None
        assert resp.gym_id == gym_id
        assert resp.first_name == "Alice"
        assert resp.stripe_customer_id is not None
        assert resp.stripe_payment_method_id is None
        assert resp.card_brand is None

        # Verify row is visible through the filtered view (has stripe_customer_id)
        async with db_pool.session() as session:
            result = await session.execute(
                text("SELECT member_id FROM member_billing_profile WHERE member_id = :id"),
                {"id": str(resp.member_id)},
            )
            row = result.mappings().fetchone()
        assert row is not None

        # Stripe side: the customer must exist and carry no charges.
        customer = await stripe_client.client.v1.customers.retrieve_async(
            resp.stripe_customer_id,
            options=connect_opts,
        )
        assert customer.id == resp.stripe_customer_id
        assert getattr(customer, "deleted", False) is False
        # Member create must not produce any invoices.
        snapshot = await snapshot_billing_state(
            stripe_client,
            resp.stripe_customer_id,
            connect_opts,
        )
        assert not snapshot.invoice_ids, (
            f"create_member generated unexpected invoices for customer "
            f"{resp.stripe_customer_id}: {sorted(snapshot.invoice_ids)}"
        )
        assert snapshot.customer_balance == 0
    finally:
        await delete_member_data(db_pool, resp.member_id)


async def test_create_member_with_card(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    pm_id = await create_payment_method(stripe_client, connect_opts)

    resp = await management_service.create_member(
        MemberCreateRequest(
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

        # Stripe side: customer must have the payment method attached
        # as its default, and no invoices may have been generated.
        customer = await stripe_client.client.v1.customers.retrieve_async(
            resp.stripe_customer_id,
            options=connect_opts,
        )
        default_pm = (
            customer.invoice_settings.default_payment_method
            if customer.invoice_settings is not None
            else None
        )
        # default_payment_method can come back either as a raw id or
        # as an expanded PaymentMethod — handle both.
        default_pm_id = (
            default_pm if isinstance(default_pm, str) else getattr(default_pm, "id", None)
        )
        assert default_pm_id == pm_id, (
            f"Customer {resp.stripe_customer_id} default_payment_method "
            f"expected {pm_id}, got {default_pm_id}"
        )
        snapshot = await snapshot_billing_state(
            stripe_client,
            resp.stripe_customer_id,
            connect_opts,
        )
        assert not snapshot.invoice_ids, (
            f"create_member generated unexpected invoices for customer "
            f"{resp.stripe_customer_id}: {sorted(snapshot.invoice_ids)}"
        )
        assert snapshot.customer_balance == 0
        # Sanity: calling the no-op guard against itself must be clean.
        await assert_no_unexpected_charges(
            stripe_client,
            snapshot,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, resp.member_id)


async def test_create_member_stripe_failure_cleans_pending(
    management_service,
    db_pool,
    gym_id,
):
    """An invalid payment_method_id should cause Stripe to fail.

    The pending DB row (with NULL stripe_customer_id) should be
    cleaned up automatically.
    """
    with pytest.raises((ValueError, Exception)):
        await management_service.create_member(
            MemberCreateRequest(
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
                "SELECT member_id FROM members "
                "WHERE gym_id = :gym_id AND first_name = 'Fail' "
                "AND stripe_customer_id IS NULL"
            ),
            {"gym_id": str(gym_id)},
        )
        row = result.mappings().fetchone()
    assert row is None
