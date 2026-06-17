"""Integration tests for cash-payment flows.

Three existing scenarios:

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

Additional mark_paid_cash boundary tests (scenarios 4–9):

4. ``test_mark_paid_cash_no_open_invoice`` — subscription is
   active with NO open invoice; ``mark_paid_cash`` must raise
   ``ValueError`` and not create any charge.

5. ``test_mark_paid_cash_non_recurring_rejected`` — one_time
   membership; ``mark_paid_cash`` must raise ``ValueError``
   (recurring-only guard).

6. ``test_mark_paid_cash_family_payer_resolution`` — child
   membership with ``paid_by_member_id`` pointing to the parent;
   injecting an open invoice on the PARENT's subscription and
   calling ``mark_paid_cash`` with the CHILD's item must pay the
   parent's invoice.

7. ``test_mark_paid_cash_consolidated_multi_membership_invoice``
   — payer with two recurring memberships on one subscription;
   a single open invoice on that sub must be paid in full.

8. ``test_mark_paid_cash_idempotency`` — two calls with the same
   ``idempotency_key`` against the same open invoice must pay it
   exactly once and must not duplicate the payment.

9. ``test_mark_paid_cash_out_of_band_confirmed`` — after
   ``mark_paid_cash`` the resolved invoice must carry
   ``out_of_band=true`` payment (confirming the cash path, not a
   card charge).
"""

from uuid import uuid4

import pytest
from sqlalchemy import text

from src.memberships import SQL_DIR
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from src.shared.sql_loader import load_sql
from tests.helpers.cleanup import delete_member_data
from tests.helpers.stripe_assertions import snapshot_billing_state


async def test_start_one_time_with_cash(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """One-time membership started with cash must not charge the card."""
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        plan_name="One-Time Cash Test",
        price_cents=3000,
    )

    try:
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                paid_with_cash=True,
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
                            "SELECT stripe_one_time_invoice_id FROM member_memberships "
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
        stripe_invoice_id = row["stripe_one_time_invoice_id"]
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
    created,
):
    """Recurring membership started with cash must activate without
    charging the card.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="recurring",
        plan_name="Recurring Cash Test",
        price_cents=5000,
    )

    try:
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                paid_with_cash=True,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
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
    created,
):
    """``mark_paid_cash`` rescues a recurring sub with an open invoice.

    Real-world scenario: the next billing cycle's invoice failed to
    charge the card, so the front desk takes cash. We simulate the
    ``open invoice`` state by creating one directly on the
    subscription via the Stripe API, since Stripe test-mode tokens
    do not reliably simulate charge failures on Connect
    subscriptions.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="recurring",
        plan_name="Mark Paid Cash Test",
        price_cents=5000,
    )

    try:
        # Normal recurring start — first invoice pays via the card.
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


# ── Helpers shared by the new tests ─────────────────────────────


async def _inject_open_invoice(
    stripe_client,
    stripe_customer_id: str,
    stripe_sub_id: str,
    amount_cents: int,
    connect_opts,
):
    """Create + finalize an open invoice on a subscription.

    Simulates a failed billing cycle by adding a pending invoice item,
    creating a draft, and finalizing it (status → open).
    Returns the finalized open invoice.
    """
    await stripe_client.client.v1.invoice_items.create_async(
        params={
            "customer": stripe_customer_id,
            "subscription": stripe_sub_id,
            "amount": amount_cents,
            "currency": "usd",
            "description": "Simulated failed cycle",
        },
        options=connect_opts,
    )
    draft = await stripe_client.client.v1.invoices.create_async(
        params={
            "customer": stripe_customer_id,
            "subscription": stripe_sub_id,
            "auto_advance": False,
        },
        options=connect_opts,
    )
    open_invoice = await stripe_client.client.v1.invoices.finalize_invoice_async(
        draft.id,
        options=connect_opts,
    )
    assert open_invoice.status == "open", (
        f"Expected finalized invoice to be open, got {open_invoice.status}"
    )
    return open_invoice


async def _link_child(db_pool, child_id, parent_id) -> None:
    """Link a child to the parent via the production link SQL."""
    link_sql = load_sql(SQL_DIR / "member_memberships_link.sql")
    async with db_pool.session() as session:
        await session.execute(
            text(link_sql),
            {
                "member_id": str(child_id),
                "parent_member_id": str(parent_id),
            },
        )
        await session.commit()


async def _start_recurring(
    memberships_service,
    gym_id,
    member_id,
    price_id,
    payer_member_id=None,
) -> None:
    """Start a recurring membership via the service."""
    await memberships_service.start(
        MemberMembershipsStartRequest(
            payer_member_id=payer_member_id or member_id,
            gym_id=gym_id,
            idempotency_key=uuid4(),
            memberships=[
                MemberMembershipsStartItem(
                    member_id=member_id,
                    price_id=price_id,
                ),
            ],
        )
    )


async def _get_membership_row(db_pool, member_id, plan_id) -> dict:
    """Return the member_memberships row for a given member + plan."""
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT item_id, stripe_item_id, paid_by_member_id "
                "FROM member_memberships "
                "WHERE member_id = :member_id AND plan_id = :plan_id"
            ),
            {"member_id": str(member_id), "plan_id": str(plan_id)},
        )
        row = result.mappings().fetchone()
    assert row is not None, (
        f"No membership row for member_id={member_id} plan_id={plan_id}"
    )
    return dict(row)


async def _get_profile_row(db_pool, member_id, gym_id) -> dict:
    """Return stripe_customer_id + stripe_sub_id_month for a member."""
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT stripe_customer_id, stripe_sub_id_month "
                "FROM member_billing_profile "
                "WHERE member_id = :member_id AND gym_id = :gym_id"
            ),
            {"member_id": str(member_id), "gym_id": str(gym_id)},
        )
        row = result.mappings().fetchone()
    assert row is not None, (
        f"No billing profile for member_id={member_id} gym_id={gym_id}"
    )
    return dict(row)


# ── Test 4 — no open invoice ─────────────────────────────────────


async def test_mark_paid_cash_no_open_invoice(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """No open invoice on the subscription — must raise ValueError.

    Scenario: a recurring membership is active (normal first payment went
    through), but no additional open invoice has been injected. Calling
    ``mark_paid_cash`` should fail with ``ValueError`` containing
    "No open invoice" and must not create any new charges or invoices.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="recurring",
        plan_name="No Open Invoice Test",
        price_cents=4000,
    )

    try:
        await _start_recurring(
            memberships_service, gym_id, member.member_id, plan.price_id
        )

        mm_row = await _get_membership_row(db_pool, member.member_id, plan.plan_id)
        profile = await _get_profile_row(db_pool, member.member_id, gym_id)
        stripe_customer_id = profile["stripe_customer_id"]

        before = await snapshot_billing_state(
            stripe_client, stripe_customer_id, connect_opts
        )

        # Active sub, no open invoice — must raise.
        with pytest.raises(ValueError, match="No open invoice"):
            await memberships_service.mark_paid_cash(
                item_id=mm_row["item_id"],
                member_id=member.member_id,
                idempotency_key=uuid4(),
            )

        # No new invoice or balance change.
        after_invoices = await stripe_client.client.v1.invoices.list_async(
            params={"customer": stripe_customer_id, "limit": 100},
            options=connect_opts,
        )
        after_ids = {inv.id for inv in after_invoices.data}
        new_ids = after_ids - before.invoice_ids
        assert not new_ids, (
            f"mark_paid_cash created unexpected invoice(s) on no-open-invoice "
            f"path: {sorted(new_ids)}"
        )
        after_customer = await stripe_client.client.v1.customers.retrieve_async(
            stripe_customer_id, options=connect_opts
        )
        assert (after_customer.balance or 0) == before.customer_balance
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Test 5 — non-recurring rejected ─────────────────────────────


async def test_mark_paid_cash_non_recurring_rejected(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """One-time membership: mark_paid_cash must raise ValueError.

    ``mark_paid_cash`` is recurring-only.  Passing the ``item_id`` of a
    one-time membership must be rejected immediately with
    ``ValueError`` matching "recurring".
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        plan_name="Non-Recurring Cash Test",
        price_cents=2000,
    )

    try:
        # Start a one-time membership via the cash path.
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                paid_with_cash=True,
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )

        mm_row = await _get_membership_row(db_pool, member.member_id, plan.plan_id)

        with pytest.raises(ValueError, match="recurring"):
            await memberships_service.mark_paid_cash(
                item_id=mm_row["item_id"],
                member_id=member.member_id,
                idempotency_key=uuid4(),
            )
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Test 6 — family payer resolution ────────────────────────────


async def test_mark_paid_cash_family_payer_resolution(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Child membership with parent payer: open invoice on parent is paid.

    A child member has ``paid_by_member_id = parent.member_id``.  Calling
    ``mark_paid_cash`` with the CHILD's ``item_id`` must resolve to the
    PARENT's subscription, find its open invoice, and pay it out of band.
    """
    pm_id = await created.payment_method()
    parent = await created.member(
        gym_id, first_name="Parent", last_name="Payer", payment_method_id=pm_id
    )
    child = await created.member(gym_id, first_name="Child", last_name="Member")

    plan = await created.plan(
        gym_id,
        plan_type="recurring",
        plan_name="Family Payer Test",
        price_cents=3000,
    )

    try:
        # Link the child to the parent before starting the membership.
        await _link_child(db_pool, child.member_id, parent.member_id)

        # Start with payer_member_id = parent so paid_by_member_id = parent.
        await _start_recurring(
            memberships_service,
            gym_id,
            child.member_id,
            plan.price_id,
            payer_member_id=parent.member_id,
        )

        child_mm = await _get_membership_row(db_pool, child.member_id, plan.plan_id)
        parent_profile = await _get_profile_row(db_pool, parent.member_id, gym_id)

        assert parent_profile["stripe_sub_id_month"] is not None, (
            "Parent should carry the subscription"
        )

        # Inject an open invoice on the PARENT's subscription.
        open_invoice = await _inject_open_invoice(
            stripe_client,
            parent.stripe_customer_id,
            parent_profile["stripe_sub_id_month"],
            plan.price_cents,
            connect_opts,
        )

        # Call mark_paid_cash with the CHILD's item_id.
        await memberships_service.mark_paid_cash(
            item_id=child_mm["item_id"],
            member_id=child.member_id,
            idempotency_key=uuid4(),
        )

        invoice = await stripe_client.client.v1.invoices.retrieve_async(
            open_invoice.id,
            options=connect_opts,
        )
        assert invoice.status == "paid", (
            f"Parent's open invoice must be paid after mark_paid_cash on child's "
            f"item; got status={invoice.status}"
        )
        assert invoice.metadata.to_dict().get("crm_paid_with_cash") == "true"
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


# ── Test 7 — consolidated multi-membership invoice ───────────────


async def test_mark_paid_cash_consolidated_multi_membership_invoice(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Two recurring memberships on one sub — open invoice paid in full.

    When a payer holds two recurring memberships they land on the same
    Stripe subscription.  A single open invoice covers both items.
    ``mark_paid_cash`` on ONE item must pay the whole open invoice out
    of band (covering both memberships).
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan_a = await created.plan(
        gym_id,
        plan_type="recurring",
        plan_name="Consolidated Multi A",
        price_cents=2500,
    )
    plan_b = await created.plan(
        gym_id,
        plan_type="recurring",
        plan_name="Consolidated Multi B",
        price_cents=3500,
    )

    try:
        # Start both memberships in one request — they converge on one sub.
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=plan_a.price_id,
                    ),
                    MemberMembershipsStartItem(
                        member_id=member.member_id,
                        price_id=plan_b.price_id,
                    ),
                ],
            )
        )

        profile = await _get_profile_row(db_pool, member.member_id, gym_id)
        stripe_customer_id = profile["stripe_customer_id"]
        stripe_sub_id = profile["stripe_sub_id_month"]
        assert stripe_sub_id is not None

        # Inject ONE open invoice covering both items.
        open_invoice = await _inject_open_invoice(
            stripe_client,
            stripe_customer_id,
            stripe_sub_id,
            plan_a.price_cents + plan_b.price_cents,
            connect_opts,
        )

        mm_a = await _get_membership_row(db_pool, member.member_id, plan_a.plan_id)

        before = await snapshot_billing_state(
            stripe_client, stripe_customer_id, connect_opts
        )

        await memberships_service.mark_paid_cash(
            item_id=mm_a["item_id"],
            member_id=member.member_id,
            idempotency_key=uuid4(),
        )

        invoice = await stripe_client.client.v1.invoices.retrieve_async(
            open_invoice.id,
            options=connect_opts,
        )
        assert invoice.status == "paid", (
            f"Consolidated open invoice must be paid; got {invoice.status}"
        )
        assert invoice.metadata.to_dict().get("crm_paid_with_cash") == "true"

        # No new invoices created.
        after_invoices = await stripe_client.client.v1.invoices.list_async(
            params={"customer": stripe_customer_id, "limit": 100},
            options=connect_opts,
        )
        after_ids = {inv.id for inv in after_invoices.data}
        new_ids = after_ids - before.invoice_ids
        assert not new_ids, (
            f"mark_paid_cash created unexpected invoice(s): {sorted(new_ids)}"
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Test 8 — idempotency ─────────────────────────────────────────


async def test_mark_paid_cash_idempotency(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Two calls with the same idempotency_key pay the invoice exactly once.

    First call pays the open invoice.  Second call with the same key finds
    no open invoice (the first already paid it) and raises ``ValueError``.
    The paid invoice must remain paid and no duplicate payment/invoice must
    appear.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="recurring",
        plan_name="Idempotency Cash Test",
        price_cents=4500,
    )

    try:
        await _start_recurring(
            memberships_service, gym_id, member.member_id, plan.price_id
        )

        profile = await _get_profile_row(db_pool, member.member_id, gym_id)
        stripe_customer_id = profile["stripe_customer_id"]
        stripe_sub_id = profile["stripe_sub_id_month"]

        open_invoice = await _inject_open_invoice(
            stripe_client,
            stripe_customer_id,
            stripe_sub_id,
            plan.price_cents,
            connect_opts,
        )

        mm_row = await _get_membership_row(db_pool, member.member_id, plan.plan_id)
        idempotency_key = uuid4()

        # First call — pays the invoice.
        await memberships_service.mark_paid_cash(
            item_id=mm_row["item_id"],
            member_id=member.member_id,
            idempotency_key=idempotency_key,
        )

        before_second = await snapshot_billing_state(
            stripe_client, stripe_customer_id, connect_opts
        )

        # Second call — same key, no open invoice left; must raise.
        with pytest.raises(ValueError, match="No open invoice"):
            await memberships_service.mark_paid_cash(
                item_id=mm_row["item_id"],
                member_id=member.member_id,
                idempotency_key=idempotency_key,
            )

        # No new invoices from the second call.
        after_invoices = await stripe_client.client.v1.invoices.list_async(
            params={"customer": stripe_customer_id, "limit": 100},
            options=connect_opts,
        )
        after_ids = {inv.id for inv in after_invoices.data}
        new_ids = after_ids - before_second.invoice_ids
        assert not new_ids, (
            f"Second mark_paid_cash created unexpected invoice(s): {sorted(new_ids)}"
        )

        # Original invoice still paid.
        invoice = await stripe_client.client.v1.invoices.retrieve_async(
            open_invoice.id,
            options=connect_opts,
        )
        assert invoice.status == "paid"
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── Test 9 — out-of-band path confirmed ─────────────────────────


async def test_mark_paid_cash_out_of_band_confirmed(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """After mark_paid_cash the invoice has no PaymentIntent (cash, not card).

    An out-of-band invoice pay does NOT produce a PaymentIntent on Stripe —
    there is no card charge.  Asserting ``payment_intent is None`` on the
    paid invoice proves the cash path was taken.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="recurring",
        plan_name="OOB Confirmed Cash Test",
        price_cents=6000,
    )

    try:
        await _start_recurring(
            memberships_service, gym_id, member.member_id, plan.price_id
        )

        profile = await _get_profile_row(db_pool, member.member_id, gym_id)
        stripe_customer_id = profile["stripe_customer_id"]
        stripe_sub_id = profile["stripe_sub_id_month"]

        open_invoice = await _inject_open_invoice(
            stripe_client,
            stripe_customer_id,
            stripe_sub_id,
            plan.price_cents,
            connect_opts,
        )
        open_invoice_id = open_invoice.id

        mm_row = await _get_membership_row(db_pool, member.member_id, plan.plan_id)

        await memberships_service.mark_paid_cash(
            item_id=mm_row["item_id"],
            member_id=member.member_id,
            idempotency_key=uuid4(),
        )

        invoice = await stripe_client.client.v1.invoices.retrieve_async(
            open_invoice_id,
            options=connect_opts,
        )
        assert invoice.status == "paid"
        assert invoice.metadata.to_dict().get("crm_paid_with_cash") == "true"

        # Out-of-band pay produces no PaymentIntent — no card was charged.
        payment_intent = getattr(invoice, "payment_intent", None)
        assert payment_intent is None, (
            f"Invoice {open_invoice_id} has PaymentIntent {payment_intent!r} after "
            f"mark_paid_cash — a card was charged, not cash out-of-band."
        )
    finally:
        await delete_member_data(db_pool, member.member_id)
