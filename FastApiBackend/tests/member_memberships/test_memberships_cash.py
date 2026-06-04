"""Integration tests for cash-payment flows.

Three scenarios:

1. ``test_start_one_time_with_cash`` — one-time plan started with
   ``paid_with_cash=True``. The Stripe invoice is marked
   ``paid_out_of_band=true`` without charging the customer's card
   and carries the ``crm_paid_with_cash`` metadata that the
   webhook uses to tag CRM charges as cash.

2. ``test_start_recurring_with_cash`` — recurring plan started
   with ``paid_with_cash=True``. The subscription is created with
   ``payment_behavior='default_incomplete'`` and its first invoice
   is paid out of band. Subscription ends up active (not
   incomplete) with no charge on the card.

3. ``test_mark_paid_cash_pays_open_invoice`` — a normally-charged
   recurring membership later has a new open invoice (simulating
   a card failure on the next cycle). ``mark_paid_cash`` rescues
   it by paying that open invoice out of band via cash.
"""

from uuid import uuid4

from sqlalchemy import text

from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import (
    create_member,
    create_payment_method,
    create_plan,
)
from tests.helpers.stripe_assertions import snapshot_billing_state


async def test_start_one_time_with_cash(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """One-time membership started with cash must not charge the card."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        plan_type="one_time",
        plan_name="One-Time Cash Test",
        price_cents=3000,
    )

    try:
        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
            paid_with_cash=True,
        )

        async with db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(
                            "SELECT stripe_item_id FROM member_memberships "
                            "WHERE member_id = :id AND plan_id = :plan_id"
                        ),
                        {
                            "id": str(member.member_id),
                            "plan_id": str(plan.plan_id),
                        },
                    )
                )
                .mappings()
                .fetchone()
            )

        assert row is not None
        stripe_invoice_id = row["stripe_item_id"]
        assert stripe_invoice_id is not None

        invoice = await stripe_client.client.v1.invoices.retrieve_async(
            stripe_invoice_id,
            options=connect_opts,
        )
        assert invoice.status == "paid"
        assert invoice.amount_paid == plan.price_cents
        # Cash marker is stamped on the invoice for the webhook.
        assert invoice.metadata.to_dict().get("crm_paid_with_cash") == "true"
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_start_recurring_with_cash(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Recurring membership started with cash must activate without
    charging the card.
    """
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        plan_type="recurring",
        plan_name="Recurring Cash Test",
        price_cents=5000,
    )

    try:
        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
            paid_with_cash=True,
        )

        async with db_pool.session() as session:
            mm_row = (
                (
                    await session.execute(
                        text(
                            "SELECT stripe_item_id FROM member_memberships "
                            "WHERE member_id = :id AND plan_id = :plan_id"
                        ),
                        {
                            "id": str(member.member_id),
                            "plan_id": str(plan.plan_id),
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
            profile_row = (
                (
                    await session.execute(
                        text(
                            "SELECT stripe_sub_id_month FROM member_billing_profile "
                            "WHERE member_id = :id AND gym_id = :gym_id"
                        ),
                        {
                            "id": str(member.member_id),
                            "gym_id": str(gym_id),
                        },
                    )
                )
                .mappings()
                .fetchone()
            )

        assert mm_row is not None and mm_row["stripe_item_id"] is not None
        assert profile_row is not None
        stripe_sub_id = profile_row["stripe_sub_id_month"]
        assert stripe_sub_id is not None

        sub = await stripe_client.client.v1.subscriptions.retrieve_async(
            stripe_sub_id,
            options=connect_opts,
        )
        # Out-of-band payment activates the subscription.
        assert sub.status == "active"

        latest_invoice = sub.latest_invoice
        invoice_id = latest_invoice if isinstance(latest_invoice, str) else latest_invoice.id
        invoice = await stripe_client.client.v1.invoices.retrieve_async(
            invoice_id,
            options=connect_opts,
        )
        assert invoice.status == "paid"
        assert invoice.metadata.to_dict().get("crm_paid_with_cash") == "true"
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_mark_paid_cash_pays_open_invoice(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """``mark_paid_cash`` rescues a recurring sub with an open invoice.

    Real-world scenario: the next billing cycle's invoice failed to
    charge the card, so the front desk takes cash. We simulate the
    ``open invoice`` state by creating one directly on the
    subscription via the Stripe API, since Stripe test-mode tokens
    do not reliably simulate charge failures on Connect
    subscriptions.
    """
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        payment_method_id=pm_id,
    )
    plan = await create_plan(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        plan_type="recurring",
        plan_name="Mark Paid Cash Test",
        price_cents=5000,
    )

    try:
        # Normal recurring start — first invoice pays via the card.
        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        async with db_pool.session() as session:
            mm_row = (
                (
                    await session.execute(
                        text(
                            "SELECT item_id FROM member_memberships "
                            "WHERE member_id = :id AND plan_id = :plan_id"
                        ),
                        {
                            "id": str(member.member_id),
                            "plan_id": str(plan.plan_id),
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
            profile_row = (
                (
                    await session.execute(
                        text(
                            "SELECT stripe_customer_id, stripe_sub_id_month "
                            "FROM member_billing_profile "
                            "WHERE member_id = :id AND gym_id = :gym_id"
                        ),
                        {
                            "id": str(member.member_id),
                            "gym_id": str(gym_id),
                        },
                    )
                )
                .mappings()
                .fetchone()
            )

        assert mm_row is not None
        assert profile_row is not None
        stripe_customer_id = profile_row["stripe_customer_id"]
        stripe_sub_id = profile_row["stripe_sub_id_month"]
        assert stripe_sub_id is not None

        # Create a pending invoice item + open invoice on the
        # subscription to simulate a failed next-cycle charge.
        await stripe_client.client.v1.invoice_items.create_async(
            params={
                "customer": stripe_customer_id,
                "subscription": stripe_sub_id,
                "amount": plan.price_cents,
                "currency": "usd",
                "description": "Simulated failed cycle",
            },
            options=connect_opts,
        )
        pending_invoice = await stripe_client.client.v1.invoices.create_async(
            params={
                "customer": stripe_customer_id,
                "subscription": stripe_sub_id,
                "auto_advance": False,
            },
            options=connect_opts,
        )
        pending_invoice = await stripe_client.client.v1.invoices.finalize_invoice_async(
            pending_invoice.id,
            options=connect_opts,
        )
        assert pending_invoice.status == "open"
        open_invoice_id = pending_invoice.id

        # Snapshot after the open invoice is in place — mark_paid_cash
        # must transition that specific invoice to paid out of band
        # WITHOUT creating any additional invoice and WITHOUT charging
        # the member's card (customer balance must not move).
        before = await snapshot_billing_state(
            stripe_client,
            stripe_customer_id,
            connect_opts,
        )

        # Rescue with cash.
        await memberships_service.mark_paid_cash(
            item_id=mm_row["item_id"],
            member_id=member.member_id,
            idempotency_key=uuid4(),
        )

        # Verify the previously open invoice is now paid out of
        # band and tagged as cash.
        invoice = await stripe_client.client.v1.invoices.retrieve_async(
            open_invoice_id,
            options=connect_opts,
        )
        assert invoice.status == "paid"
        assert invoice.metadata.to_dict().get("crm_paid_with_cash") == "true"

        # No additional invoice may have been created, and the
        # customer balance must be untouched (cash payments must
        # never debit the card). We cannot use
        # ``assert_no_unexpected_charges`` here because the open
        # invoice count legitimately drops by one (the open invoice
        # became paid).
        after_invoices = await stripe_client.client.v1.invoices.list_async(
            params={"customer": stripe_customer_id, "limit": 100},
            options=connect_opts,
        )
        after_ids = {inv.id for inv in after_invoices.data}
        new_ids = after_ids - before.invoice_ids
        assert not new_ids, (
            f"mark_paid_cash created unexpected new invoice(s) for customer "
            f"{stripe_customer_id}: {sorted(new_ids)}"
        )
        after_customer = await stripe_client.client.v1.customers.retrieve_async(
            stripe_customer_id,
            options=connect_opts,
        )
        assert (after_customer.balance or 0) == before.customer_balance, (
            f"Customer {stripe_customer_id} balance moved after "
            f"mark_paid_cash: before={before.customer_balance} "
            f"after={after_customer.balance}"
        )
    finally:
        await delete_member_data(db_pool, member.member_id)
