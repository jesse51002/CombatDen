"""Integration: one-time membership start routes through PaymentSyncOneTime.

Verifies the single one-time ``start`` now goes through the engine — one
consolidated invoice is cut + paid, and the membership row is stamped with the
invoice LINE id (``stripe_item_id``), the consolidated invoice id
(``stripe_one_time_invoice_id`` — the old path never set this), the post-discount
``total_price``, and ``stripe_sync_status = 'applied'``.
"""

from uuid import uuid4

import pytest
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401


async def _read_one_time_row(db_pool, member_id, gym_id) -> dict:
    """Read the member's one-time membership row (unfiltered base)."""
    sql = """
        SELECT stripe_item_id,
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
