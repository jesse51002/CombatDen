"""Integration: the family-sweep path of PaymentSyncOneTime.charge_one_time.

The batch's core path: a payer plus a linked child, each carrying a pending
one-time membership, are swept onto ONE consolidated invoice in ONE engine call.
Each membership is its own invoice LINE with its OWN exact discount — no
averaging across members. This verifies:

  * both rows end ``applied`` and share the SAME stripe_one_time_invoice_id,
  * their stripe_item_ids are DIFFERENT invoice LINE ids (``il_…``),
  * each total_price reflects ITS OWN discount (10% vs $5 off — not averaged),
  * the Stripe invoice carries exactly 2 lines.

Two ``start`` calls cannot be used (each charges immediately), so the two
pending rows + their applied-discount rows are inserted at the level ``start``
uses, then the engine is called once directly.
"""

from uuid import UUID, uuid4

import pytest
from schema.member_membership import StripeSyncStatus
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
from src.memberships.service.memberships_discounts import (
    MemberMembershipsDiscounts,
)
from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
)
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)
from src.payments.service.payments_stripe_payment_service import (
    PaymentsStripePaymentService,
)
from src.shared.gym_stripe_service import GymStripeService
from src.shared.gym_timezone import gym_today
from src.shared.payer_resolver import PayerResolver
from src.shared.sql_loader import load_sql
from src.sync.service.sync_discounts import PaymentSyncDiscounts
from src.sync.service.sync_one_time import PaymentSyncOneTime
from tests.helpers.db_reads import get_applied_discounts

_SEEDED_GYM_TZ = "America/Chicago"


def _build_one_time_engine(db_pool, stripe_client) -> PaymentSyncOneTime:
    """Construct the one-time engine exactly as the DI factory does."""
    members_svc = PaymentsStripeMembersService(stripe_client)
    discount_svc = PaymentsStripeDiscountService(stripe_client)
    payment_svc = PaymentsStripePaymentService(stripe_client, members_svc)
    parent_resolver = PayerResolver(db_pool, GymStripeService(db_pool))
    return PaymentSyncOneTime(
        db_pool,
        discounts=PaymentSyncDiscounts(discount_svc),
        payment_service=payment_svc,
        parent_resolver=parent_resolver,
    )


def _build_discounts_sub_service(db_pool) -> MemberMembershipsDiscounts:
    """The apply sub-service needs only db_pool for the insert path used here.

    ``add_applied_discounts`` touches only the DB (no sync / gym-stripe), so the
    payment-sync + gym-stripe deps it inherits from the base are unused by it.
    """
    return MemberMembershipsDiscounts(db_pool, None, None)


async def _insert_pending_one_time(
    db_pool,
    *,
    member_id: UUID,
    gym_id: UUID,
    plan_id: UUID,
    price_id: UUID,
    start_date,
    total_price: int,
) -> UUID:
    """Insert a pending (``not_added``) one-time membership row like ``start``.

    The insert SQL is the multi-row (array-bound) form; this helper passes
    one-element arrays.
    """
    sql = load_sql(SQL_DIR / "member_memberships_insert.sql")
    params = {
        "member_ids": [str(member_id)],
        "gym_ids": [str(gym_id)],
        "plan_ids": [str(plan_id)],
        "price_ids": [str(price_id)],
        "start_dates": [start_date],
        "end_dates": [None],
        "last_paid_dates": [start_date],
        "next_due_dates": [None],
        "stripe_item_ids": [None],
        "prorates": [True],
        "total_prices": [total_price],
        "sync_statuses": [StripeSyncStatus.not_added.value],
    }
    async with db_pool.session() as session:
        result = await session.execute(text(sql), params)
        row = result.mappings().one()
        await session.commit()
    return UUID(str(row["item_id"]))


async def _read_one_time_row(db_pool, item_id) -> dict:
    sql = """
        SELECT item_id,
               stripe_item_id,
               stripe_one_time_invoice_id,
               stripe_sync_status::text AS status,
               total_price
        FROM member_memberships_unfiltered
        WHERE item_id = :item_id
    """
    async with db_pool.session() as session:
        result = await session.execute(text(sql), {"item_id": str(item_id)})
        return dict(result.mappings().one())


@pytest.mark.timeout(180)
async def test_family_sweep_one_invoice_two_lines(
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Payer + linked child, each pending → ONE invoice, TWO lines, own discounts."""
    engine = _build_one_time_engine(db_pool, stripe_client)
    apply_svc = _build_discounts_sub_service(db_pool)

    pm_id = await created.payment_method()
    payer = await created.member(gym_id, payment_method_id=pm_id)
    child = await created.member(gym_id, first_name="Child", last_name="Sweep")

    # Link the child to the payer (NULLs the child's card; child rides the
    # payer's invoice). Allowed: the child has no active recurring memberships
    # (a pending one-time row is not recurring).
    link_sql = load_sql(SQL_DIR / "member_memberships_link.sql")
    async with db_pool.session() as session:
        await session.execute(
            text(link_sql),
            {
                "member_id": str(child.member_id),
                "parent_member_id": str(payer.member_id),
            },
        )
        await session.commit()

    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        price_cents=5000,
        duration_amount=1,
        duration_unit="month",
    )
    pct_preset = await created.discount(
        gym_id,
        name="10% once sweep",
        percentage_off=10.0,
        discount_mode="once",
    )
    amt_preset = await created.discount(
        gym_id,
        name="$5 off once sweep",
        percentage_off=None,
        dollar_off=500,
        discount_mode="once",
    )

    start_date = gym_today(_SEEDED_GYM_TZ)
    payer_item = await _insert_pending_one_time(
        db_pool,
        member_id=payer.member_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
        start_date=start_date,
        total_price=5000,
    )
    child_item = await _insert_pending_one_time(
        db_pool,
        member_id=child.member_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
        start_date=start_date,
        total_price=5000,
    )

    # Give the two memberships DIFFERENT discounts so the per-line totals must
    # diverge — 10% off on the payer's, $5 off on the child's.
    await apply_svc.add_applied_discounts(
        item_id=payer_item,
        member_id=payer.member_id,
        gym_id=gym_id,
        discount_ids=[pct_preset.discount_id],
        apply_date=start_date,
    )
    await apply_svc.add_applied_discounts(
        item_id=child_item,
        member_id=child.member_id,
        gym_id=gym_id,
        discount_ids=[amt_preset.discount_id],
        apply_date=start_date,
    )

    # ONE engine call sweeps the whole family onto ONE invoice.
    await engine.charge_one_time(payer.member_id, uuid4())

    payer_row = await _read_one_time_row(db_pool, payer_item)
    child_row = await _read_one_time_row(db_pool, child_item)

    # Both rows applied.
    assert payer_row["status"] == "applied"
    assert child_row["status"] == "applied"

    # Same consolidated invoice; different LINE ids.
    assert payer_row["stripe_one_time_invoice_id"] is not None
    assert (
        payer_row["stripe_one_time_invoice_id"]
        == child_row["stripe_one_time_invoice_id"]
    )
    assert payer_row["stripe_item_id"] != child_row["stripe_item_id"]
    assert payer_row["stripe_item_id"].startswith("il_")
    assert child_row["stripe_item_id"].startswith("il_")

    # Each line reflects ITS OWN discount exactly — no averaging.
    assert payer_row["total_price"] == 4500  # 5000 - 10%
    assert child_row["total_price"] == 4500  # 5000 - $5.00
    # Same number here only by coincidence of values; prove they came from
    # different coupons (percent vs dollar), not an averaged single discount.
    payer_snaps = await get_applied_discounts(db_pool, payer_item)
    child_snaps = await get_applied_discounts(db_pool, child_item)
    assert payer_snaps[0]["stripe_coupon_id"] == "pct_1000_once"
    assert child_snaps[0]["stripe_coupon_id"] == "amt_500_once"
    created.track_coupon("pct_1000_once")
    created.track_coupon("amt_500_once")

    # The Stripe invoice itself carries exactly 2 lines.
    invoice = await stripe_client.client.v1.invoices.retrieve_async(
        payer_row["stripe_one_time_invoice_id"], options=connect_opts
    )
    assert invoice.status == "paid"
    assert len(invoice.lines.data) == 2
    assert invoice.amount_paid == 9000  # 4500 + 4500
