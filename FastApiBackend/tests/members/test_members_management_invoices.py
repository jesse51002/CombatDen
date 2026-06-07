"""Integration tests for member invoice listing."""

import pytest

from src.members.schema.members_schema import MemberCreateRequest
from tests.helpers.cleanup import delete_member_data


async def test_list_invoices_returns_real_invoice(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Regression guard: ``list_invoices`` must return real Stripe
    invoices with the correct totals. Previously crashed with
    ``AttributeError: subscription`` because newer Stripe API
    versions dropped the top-level ``Invoice.subscription``
    attribute — the id now lives at
    ``parent.subscription_details.subscription``. The service now
    reads it via ``_extract_subscription_id`` and this test locks
    that behavior in.
    """
    pm_id = await created.payment_method()
    member = await management_service.create_member(
        MemberCreateRequest(
            gym_id=gym_id,
            first_name="RealInvoice",
            last_name="Tester",
            payment_method_id=pm_id,
        ),
    )
    created.track_customer(member.stripe_customer_id)

    try:
        invoice_amount = 4200
        await stripe_client.client.v1.invoice_items.create_async(
            params={
                "customer": member.stripe_customer_id,
                "amount": invoice_amount,
                "currency": "usd",
                "description": "list_invoices regression",
            },
            options=connect_opts,
        )
        pending = await stripe_client.client.v1.invoices.create_async(
            params={
                "customer": member.stripe_customer_id,
                "auto_advance": False,
                "pending_invoice_items_behavior": "include",
            },
            options=connect_opts,
        )
        finalized = await stripe_client.client.v1.invoices.finalize_invoice_async(
            pending.id,
            options=connect_opts,
        )

        invoices = await management_service.list_invoices(member.member_id)
        assert any(getattr(inv, "stripe_invoice_id", None) == finalized.id for inv in invoices), (
            f"Expected list_invoices to return {finalized.id}, got "
            f"{[getattr(i, 'stripe_invoice_id', None) for i in invoices]}"
        )
        matched = next(
            inv for inv in invoices if getattr(inv, "stripe_invoice_id", None) == finalized.id
        )
        assert getattr(matched, "amount_due", None) == invoice_amount
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_list_invoices_no_stripe_customer_raises(
    management_service,
    db_pool,
    gym_id,
):
    """A member without a Stripe customer should raise an error."""
    # Insert a member directly without going through the service
    # (so stripe_customer_id stays NULL — not visible via filtered view)
    from sqlalchemy import text

    insert_sql = """
        INSERT INTO members (
            gym_id, first_name, last_name
        ) VALUES (:gym_id, 'NoStripe', 'Member')
        RETURNING member_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(insert_sql),
            {"gym_id": str(gym_id)},
        )
        row = result.mappings().fetchone()
        await session.commit()

    from uuid import UUID

    member_id = UUID(str(row["member_id"]))

    try:
        with pytest.raises(ValueError):
            await management_service.list_invoices(member_id)
    finally:
        await delete_member_data(db_pool, member_id)
