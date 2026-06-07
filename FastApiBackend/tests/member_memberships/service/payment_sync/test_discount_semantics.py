"""Regression guard for Stripe upcoming-invoice line semantics.

Empirically verified against real Stripe: on an upcoming-invoice
preview for a subscription with a percent-off coupon attached at
the subscription-item level,

* ``line.amount`` is **pre-discount** (== ``line.subtotal``)
* ``line.discount_amounts[].amount`` carries the per-line coupon
  contribution
* The correct post-discount value is
  ``line.amount - sum(line.discount_amounts)``, which matches
  ``invoice.amount_due`` and ``invoice.subtotal``.

This test locks that behavior in so the writeback doesn't silently
go back to trusting ``line.amount`` if someone else refactors the
mapper later.
"""

from uuid import UUID, uuid4

from sqlalchemy import text
from stripe.params._invoice_create_preview_params import (
    InvoiceCreatePreviewParams,
)

from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import (
    create_discount,
    create_member,
    create_payment_method,
    create_plan,
)
from tests.helpers.db_reads import (
    get_active_membership_item_id,
    get_profile_stripe_ids,
)


async def _fetch_total_price(db_pool, member_id: UUID, plan_id: UUID) -> int:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT total_price FROM member_memberships "
                "WHERE member_id = :member_id "
                "  AND plan_id = :plan_id "
                "  AND cancel_date IS NULL"
            ),
            {"member_id": str(member_id), "plan_id": str(plan_id)},
        )
        row = result.mappings().fetchone()
    assert row is not None
    return int(row["total_price"])


async def test_line_amount_vs_subtotal_with_discount(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Apply a 10% off discount and verify which line field is net.

    Plan price = 5000 cents, 10% off → expected post-discount = 4500.
    After start, we fetch the raw Stripe upcoming invoice and compare:
      - line.amount
      - line.subtotal
      - line.discount_amounts (per-discount breakdown)
      - invoice.subtotal, invoice.total, invoice.amount_due
    """
    pm_id = await create_payment_method(stripe_client, connect_opts)
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="DiscSem",
        last_name="Member",
        payment_method_id=pm_id,
    )
    plan = await create_plan(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        plan_name="Disc Sem Plan",
        price_cents=5000,
    )
    discount = await create_discount(
        db_pool,
        gym_id,
        name="Sem 10% Off",
        percentage_off=10.0,
        discount_mode="ongoing",
    )

    try:
        await memberships_service.start(
            member_id=member.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )
        item_id = await get_active_membership_item_id(db_pool, member.member_id, gym_id)
        await memberships_service.add_discounts(
            item_id=item_id,
            member_id=member.member_id,
            preset_ids=[discount.discount_id],
            idempotency_key=uuid4(),
        )

        profile = await get_profile_stripe_ids(
            db_pool,
            member.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        # ── Raw Stripe upcoming invoice inspection ─────────
        invoice = await stripe_client.client.v1.invoices.create_preview_async(
            params=InvoiceCreatePreviewParams(
                subscription=profile.stripe_sub_id_month,
            ),
            options=connect_opts,
        )

        # ── Raw field assertions ───────────────────────────
        assert invoice.amount_due == 4500, (
            f"Discount didn't land on the upcoming preview — "
            f"amount_due {invoice.amount_due}, expected 4500"
        )
        assert len(invoice.lines.data) == 1
        line = invoice.lines.data[0]

        # line.amount and line.subtotal are PRE-discount.
        assert line.amount == 5000, (
            f"Expected line.amount to be pre-discount 5000, got {line.amount}"
        )
        assert line.subtotal == 5000, (
            f"Expected line.subtotal to be pre-discount 5000, got {line.subtotal}"
        )

        # The 500-cent discount lives in discount_amounts.
        das = getattr(line, "discount_amounts", None) or []
        assert len(das) == 1, f"Expected one discount_amounts entry, got {len(das)}"
        assert das[0].amount == 500

        # The correct post-discount value is amount - sum(discount_amounts).
        post_discount = line.amount - sum(d.amount for d in das)
        assert post_discount == 4500

        # And our mapper must return that value, not line.amount.
        total_price = await _fetch_total_price(
            db_pool,
            member.member_id,
            plan.plan_id,
        )
        assert total_price == 4500, (
            f"Writeback stored {total_price} for total_price — "
            f"should be post-discount 4500 (line.amount is pre-discount!)"
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_line_amount_is_total_for_quantity_not_per_unit(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Verify ``line.amount`` on an upcoming invoice reflects the
    quantity-multiplied total, not a per-unit price.

    Parent + linked child on the same plan consolidate into a single
    Stripe subscription item with qty=2. The upcoming invoice should
    show one line with ``quantity=2`` and ``amount = 2 * unit_price``.
    If Stripe were reporting per-unit instead, we'd see 5000 for a
    5000-cent plan; the assertion below forces 10000.
    """
    pm_id = await create_payment_method(stripe_client, connect_opts)
    parent = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="QtySem",
        last_name="Parent",
        payment_method_id=pm_id,
    )
    child = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="QtySem",
        last_name="Child",
    )
    plan = await create_plan(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        plan_name="Qty Sem Plan",
        price_cents=5000,
    )

    try:
        await memberships_service.link_account(
            child.member_id,
            parent.member_id,
        )
        await memberships_service.start(
            member_id=parent.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )
        await memberships_service.start(
            member_id=child.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        profile = await get_profile_stripe_ids(
            db_pool,
            parent.member_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        # Filter out any proration lines from the mid-cycle add so
        # this assertion is specifically about the recurring line.
        invoice = await stripe_client.client.v1.invoices.create_preview_async(
            params=InvoiceCreatePreviewParams(
                subscription=profile.stripe_sub_id_month,
            ),
            options=connect_opts,
        )

        recurring = []
        for ln in invoice.lines.data:
            parent_obj = getattr(ln, "parent", None)
            proration = False
            if parent_obj:
                sid = getattr(parent_obj, "subscription_item_details", None)
                if sid and getattr(sid, "proration", False):
                    proration = True
            if not proration:
                recurring.append(ln)

        assert len(recurring) == 1, (
            f"Expected one recurring line after consolidation, got {len(recurring)}"
        )
        line = recurring[0]

        assert line.quantity == 2, (
            f"Expected consolidated subscription item quantity=2, got {line.quantity}"
        )
        # This is the claim: line.amount already includes quantity.
        assert line.amount == 10000, (
            f"Expected line.amount to be qty*price 10000, got {line.amount} "
            f"(if Stripe were per-unit this would be 5000)"
        )
        assert line.subtotal == 10000, (
            f"Expected line.subtotal to be qty*price 10000, got {line.subtotal}"
        )
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)
