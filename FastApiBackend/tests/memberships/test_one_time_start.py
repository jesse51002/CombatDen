"""Integration: one-time membership start routes through PaymentSyncOneTime.

Verifies the single one-time ``start`` now goes through the engine — one
consolidated invoice is cut + paid, and the membership row is stamped with the
invoice LINE id (``stripe_item_id``), the consolidated invoice id
(``stripe_one_time_invoice_id`` — the old path never set this), the post-discount
``total_price``, and ``stripe_sync_status = 'applied'``.
"""

from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from tests.helpers.db_reads import get_applied_discounts


async def _read_one_time_row(db_pool, member_id, gym_id) -> dict:
    """Read the member's one-time membership row (unfiltered base)."""
    sql = """
        SELECT item_id,
               stripe_item_id,
               stripe_one_time_invoice_id,
               stripe_sync_status::text AS status,
               total_price
        FROM member_memberships_unfiltered
        WHERE member_id = :member_id AND gym_id = :gym_id
        ORDER BY created_at DESC
        LIMIT 1
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(sql),
            {"member_id": str(member_id), "gym_id": str(gym_id)},
        )
        return dict(result.mappings().one())


@pytest.mark.timeout(180)
async def test_one_time_start_charges_through_engine(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        price_cents=5000,
        duration_amount=1,
        duration_unit="month",
    )

    await memberships_service.start(
        member_id=member.member_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
        idempotency_key=uuid4(),
    )

    # Through the engine: the row is stamped with BOTH ids + price + applied.
    row = await _read_one_time_row(db_pool, member.member_id, gym_id)
    assert row["status"] == "applied"
    assert row["stripe_item_id"] is not None
    assert row["stripe_one_time_invoice_id"] is not None
    # The two ids are distinct: line id vs consolidated invoice id.
    assert row["stripe_item_id"] != row["stripe_one_time_invoice_id"]
    assert row["stripe_one_time_invoice_id"].startswith("in_")
    assert row["total_price"] == 5000

    # Stripe: the consolidated invoice was actually paid.
    invoice = await stripe_client.client.v1.invoices.retrieve_async(
        row["stripe_one_time_invoice_id"],
        options=connect_opts,
    )
    assert invoice.status == "paid"
    assert invoice.amount_paid == 5000


@pytest.mark.timeout(180)
async def test_one_time_start_with_preset_discount(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A preset discount passed at start discounts the single invoice."""
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        price_cents=5000,
        duration_amount=1,
        duration_unit="month",
    )
    preset = await created.discount(
        gym_id,
        name="10% once",
        percentage_off=10.0,
        discount_mode="once",
    )

    await memberships_service.start(
        member_id=member.member_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
        idempotency_key=uuid4(),
        discount_ids=[preset.discount_id],
    )

    # The single invoice is discounted at creation (5000 - 10% = 4500).
    row = await _read_one_time_row(db_pool, member.member_id, gym_id)
    assert row["status"] == "applied"
    assert row["total_price"] == 4500
    invoice = await stripe_client.client.v1.invoices.retrieve_async(
        row["stripe_one_time_invoice_id"], options=connect_opts
    )
    assert invoice.status == "paid"
    assert invoice.amount_paid == 4500

    # The applied-discount row has its resolved coupon written back.
    snaps = await get_applied_discounts(db_pool, row["item_id"])
    assert len(snaps) == 1
    assert snaps[0]["stripe_coupon_id"] is not None


@pytest.mark.timeout(180)
async def test_add_discounts_rejected_on_one_time_membership(
    memberships_service,
    db_pool,
    gym_id,
    created,
):
    """add_discounts on a one-time membership must be rejected with a clear error.

    A one-time membership's single invoice is charged at creation; there is no
    future invoice to discount, so calling add_discounts post-charge must raise
    ValueError with the non-recurring message.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        price_cents=3000,
        duration_amount=1,
        duration_unit="month",
    )

    await memberships_service.start(
        member_id=member.member_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
        idempotency_key=uuid4(),
    )

    row = await _read_one_time_row(db_pool, member.member_id, gym_id)
    item_id = UUID(str(row["item_id"]))

    preset = await created.discount(
        gym_id,
        name="10% add-test",
        percentage_off=10.0,
        discount_mode="once",
    )

    with pytest.raises(ValueError, match="non-recurring"):
        await memberships_service.add_discounts(
            item_id=item_id,
            member_id=member.member_id,
            discount_ids=[preset.discount_id],
            idempotency_key=uuid4(),
        )
