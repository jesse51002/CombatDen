"""Integration tests for member invoice listing."""

from uuid import uuid4

import pytest
from sqlalchemy import text

from src.members.members_exceptions import (
    MemberStripeCustomerMissingError,
)
from src.members.schema.members_schema import MemberCreateRequest
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from tests.helpers.cleanup import delete_member_data


async def test_list_invoices_returns_real_invoice(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Regression guard: ``list_invoices`` returns real Stripe invoices with
    the correct totals.

    Stripe moved the subscription id off the top-level ``Invoice.subscription``
    to ``parent.subscription_details.subscription``; the service reads it via
    ``_extract_subscription_id``, and this locks that in.
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
    """A member without a Stripe customer raises.

    On the TYPE: the route reads its 400 off the exception's ``status_code``,
    and a bare ``pytest.raises(ValueError)`` would also pass for the 404-shaped
    ``MemberNotFoundError`` — it could not tell the two statuses apart.
    """
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
        with pytest.raises(MemberStripeCustomerMissingError):
            await management_service.list_invoices(member_id)
    finally:
        await delete_member_data(db_pool, member_id)


async def test_list_invoices_drops_canceled_sub_open_invoice(
    management_service,
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """An OPEN invoice on a dead (canceled) subscription must not surface.

    Cancel-sync nulls the payer's ``stripe_sub_id_month``; the dead sub's
    lingering open invoice is uncollectible and must never read as overdue.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="recurring",
        plan_name="Canceled Sub Invoice Test",
        price_cents=5000,
    )

    try:
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )

        async with db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(
                            "SELECT stripe_sub_id_month FROM "
                            "member_billing_profile "
                            "WHERE member_id = :id AND gym_id = :gym_id"
                        ),
                        {"id": str(member.member_id), "gym_id": str(gym_id)},
                    )
                )
                .mappings()
                .fetchone()
            )
        stripe_sub_id = row["stripe_sub_id_month"]
        assert stripe_sub_id is not None

        # An OPEN invoice scoped to that subscription (a failed renewal).
        await stripe_client.client.v1.invoice_items.create_async(
            params={
                "customer": member.stripe_customer_id,
                "subscription": stripe_sub_id,
                "amount": 5000,
                "currency": "usd",
                "description": "stale renewal on dead sub",
            },
            options=connect_opts,
        )
        pending = await stripe_client.client.v1.invoices.create_async(
            params={
                "customer": member.stripe_customer_id,
                "subscription": stripe_sub_id,
                "auto_advance": False,
            },
            options=connect_opts,
        )
        open_invoice = (
            await stripe_client.client.v1.invoices.finalize_invoice_async(
                pending.id,
                options=connect_opts,
            )
        )
        assert open_invoice.status == "open"

        # While the sub is live, the open invoice surfaces.
        before = await management_service.list_invoices(member.member_id)
        assert any(i.stripe_invoice_id == open_invoice.id for i in before), (
            "an open invoice on the live sub should surface"
        )

        # Simulate the cancel-sync clearing the dead sub's id.
        async with db_pool.session() as session:
            await session.execute(
                text(
                    "UPDATE members SET stripe_sub_id_month = NULL "
                    "WHERE member_id = :id"
                ),
                {"id": str(member.member_id)},
            )
            await session.commit()

        # Now the dead sub's open invoice must NOT surface.
        after = await management_service.list_invoices(member.member_id)
        assert not any(
            i.stripe_invoice_id == open_invoice.id for i in after
        ), "an open invoice on a canceled sub must not surface as overdue"
    finally:
        await delete_member_data(db_pool, member.member_id)
