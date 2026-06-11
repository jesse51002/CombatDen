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
from src.discounts.schema.discounts_schema import DiscountValue
from src.shared.gym_timezone import gym_today
from tests.helpers.db_reads import get_applied_discounts

# The single seeded gym is America/Chicago (tests/seed_constants.py); the once
# consumption stamp is the gym-today date, so assert against that timezone.
_SEEDED_GYM_TZ = "America/Chicago"


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

    # The applied-discount row has its resolved coupon written back, and the
    # once-mode row is stamped consumed (end_date == the gym-today date) at the
    # charge — the single invoice is the only charge.
    snaps = await get_applied_discounts(db_pool, row["item_id"])
    assert len(snaps) == 1
    assert snaps[0]["stripe_coupon_id"] is not None
    assert snaps[0]["end_date"] == gym_today(_SEEDED_GYM_TZ)


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


async def _discount_id_for_value(db_pool, value_id) -> UUID:
    """Resolve the owning ``discount_id`` for an applied row's ``value_id``."""
    sql = (
        "SELECT discount_id FROM gym_discount_values_unfiltered "
        "WHERE value_id = :value_id"
    )
    async with db_pool.session() as session:
        result = await session.execute(text(sql), {"value_id": str(value_id)})
        return UUID(str(result.mappings().one()["discount_id"]))


@pytest.mark.timeout(180)
async def test_one_time_start_with_inline_custom_discount(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """An inline custom (minted at start) discounts the single one-time invoice.

    The custom is minted by ``mint_custom_discounts`` and applied before the
    one charge, so the invoice is cut at the discounted amount. The once row is
    stamped consumed at the charge. The minted custom is registered for cleanup
    so it does not leak under the seeded gym.
    """
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
        custom_discounts=[
            DiscountValue(percentage_off=20.0, discount_mode="once"),
        ],
    )

    # 5000 - 20% = 4000 on the single invoice.
    row = await _read_one_time_row(db_pool, member.member_id, gym_id)
    assert row["status"] == "applied"
    assert row["total_price"] == 4000
    invoice = await stripe_client.client.v1.invoices.retrieve_async(
        row["stripe_one_time_invoice_id"], options=connect_opts
    )
    assert invoice.status == "paid"
    assert invoice.amount_paid == 4000

    snaps = await get_applied_discounts(db_pool, row["item_id"])
    assert len(snaps) == 1
    assert snaps[0]["stripe_coupon_id"] is not None
    assert snaps[0]["end_date"] == gym_today(_SEEDED_GYM_TZ)

    # Register the minted custom for teardown (it created a gym_discounts +
    # gym_discount_values pair the member cleanup does not touch).
    minted_id = await _discount_id_for_value(db_pool, snaps[0]["value_id"])
    created.track_discount(minted_id)


@pytest.mark.timeout(180)
async def test_one_time_start_with_dollar_off_discount(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A preset dollar-off discount subtracts a flat amount from the invoice."""
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
        name="$5 off once",
        percentage_off=None,
        dollar_off=500,
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

    # 5000 - 500 = 4500 on the single invoice.
    row = await _read_one_time_row(db_pool, member.member_id, gym_id)
    assert row["status"] == "applied"
    assert row["total_price"] == 4500
    invoice = await stripe_client.client.v1.invoices.retrieve_async(
        row["stripe_one_time_invoice_id"], options=connect_opts
    )
    assert invoice.status == "paid"
    assert invoice.amount_paid == 4500

    snaps = await get_applied_discounts(db_pool, row["item_id"])
    assert len(snaps) == 1
    coupon_id = snaps[0]["stripe_coupon_id"]
    assert coupon_id == "amt_500_once"
    # The deterministic coupon is find-or-created on the Connect account; clean
    # it up so it does not accumulate across runs.
    created.track_coupon(coupon_id)


@pytest.mark.timeout(180)
async def test_one_time_start_with_compound_discounts(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Two presets on one membership discount sequentially within the line.

    10% once + 20% once on the same one-time membership → the percents compound
    sequentially (not additive): 5000 × 0.90 × 0.80 = 3600.
    """
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        price_cents=5000,
        duration_amount=1,
        duration_unit="month",
    )
    preset_10 = await created.discount(
        gym_id,
        name="10% once compound",
        percentage_off=10.0,
        discount_mode="once",
    )
    preset_20 = await created.discount(
        gym_id,
        name="20% once compound",
        percentage_off=20.0,
        discount_mode="once",
    )

    await memberships_service.start(
        member_id=member.member_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
        idempotency_key=uuid4(),
        discount_ids=[preset_10.discount_id, preset_20.discount_id],
    )

    # 5000 × 0.90 × 0.80 = 3600 (compounded, not 5000 - 30% = 3500).
    row = await _read_one_time_row(db_pool, member.member_id, gym_id)
    assert row["status"] == "applied"
    assert row["total_price"] == 3600
    invoice = await stripe_client.client.v1.invoices.retrieve_async(
        row["stripe_one_time_invoice_id"], options=connect_opts
    )
    assert invoice.status == "paid"
    assert invoice.amount_paid == 3600

    # Both applied rows got their coupons written back.
    snaps = await get_applied_discounts(db_pool, row["item_id"])
    assert len(snaps) == 2
    assert all(s["stripe_coupon_id"] is not None for s in snaps)
    for s in snaps:
        created.track_coupon(s["stripe_coupon_id"])


# ── Webhook line attribution (test 6) — SKIPPED, infrastructure finding ──
#
# The task's test 6 ("after a charged one-time start, check what the
# invoice.paid webhook wrote to member_invoices / member_invoice_line_items /
# member_invoice_applied_discounts") cannot be written here. There is NO live
# webhook listener in this test environment: the only tests that populate those
# webhook-owned tables (tests/stripe_webhooks/) do so by CRAFTING a synthetic
# event with event_builders.make_invoice_paid_event(...) and calling
# StripeWebhooksService.handle_event(event) DIRECTLY. No membership / sync /
# payment test dispatches an event after a real start, and no harness forwards
# Stripe's real webhooks into the local DB. So after the one-time charges above,
# member_invoices stays empty for that invoice — not a bug, just absent infra.
# Writing a test that asserts on those tables here would hang/fail on missing
# rows. Per the task, the finding is reported instead of a flaky test.
