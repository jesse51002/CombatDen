"""Live integration tests for the refund endpoint's service path.

Exercises MemberMembershipsRefund against the REAL shared DB (the new
member_charge_by_id.sql lookup + member_refund_insert.sql insert, including the
migration that lets a cash refund carry no stripe_refund_id) and, for the card
path, a REAL Stripe refund on the test Connect account. Mirrors the in-process
wiring the router uses; the HTTP/auth layer is covered separately by the unit
suite and the live OpenAPI check.
"""

from uuid import UUID, uuid4

from schema.membership_plan import DurationUnit, PlanType
from sqlalchemy import text

from src.memberships.memberships_schema import MemberMembershipsRefundRequest
from src.memberships.service.memberships_refund import MemberMembershipsRefund
from src.payments.schema.metadata.stripe_membership_one_time_metadata import (
    StripeMembershipOneTimeMetadata,
)
from src.payments.schema.metadata.stripe_product_metadata import (
    StripeProductMetadata,
)
from src.payments.schema.payments_membership_schema import (
    PaymentsMembershipCreateRequest,
    PaymentsMembershipPriceItem,
)
from src.payments.schema.payments_payment_schema import (
    PaymentsInvoiceItemSpec,
    PaymentsInvoicePaymentCreateRequest,
)
from src.shared.gym_stripe_service import GymStripeService
from tests.helpers.service_factory import build_payment_services
from tests.seed_constants import SEEDED_GYM_ID

GYM = UUID(SEEDED_GYM_ID)


def _refund_service(db_pool, stripe_client) -> MemberMembershipsRefund:
    services = build_payment_services(stripe_client)
    return MemberMembershipsRefund(
        db_pool=db_pool,
        payment_service=services.payment,
        gym_stripe_service=GymStripeService(db_pool),
    )


async def _seed_payment_charge(
    db_pool,
    member_id: UUID,
    *,
    amount: int,
    payment_method_type: str,
    stripe_charge_id: str | None,
) -> UUID:
    """Insert a paid invoice + its succeeded payment charge; return charge PK."""
    invoice_id = uuid4()
    charge_id = uuid4()
    async with db_pool.session() as session:
        await session.execute(
            text(
                "INSERT INTO member_invoices "
                "(invoice_id, gym_id, paid_by_member_id, status, "
                " total_amount, currency)"
                " VALUES (:i, :g, :m, 'paid', :a, 'usd')"
            ),
            {"i": str(invoice_id), "g": str(GYM), "m": str(member_id), "a": amount},
        )
        await session.execute(
            text(
                "INSERT INTO member_charges "
                "(charge_id, invoice_id, gym_id, paid_by_member_id, kind, "
                " status, amount, currency, payment_method_type, "
                " card_last_four, stripe_charge_id) VALUES "
                "(:c, :i, :g, :m, 'payment', 'succeeded', :a, 'usd', :pmt, "
                " :l4, :ch)"
            ),
            {
                "c": str(charge_id),
                "i": str(invoice_id),
                "g": str(GYM),
                "m": str(member_id),
                "a": amount,
                "pmt": payment_method_type,
                "l4": "4242" if stripe_charge_id else None,
                "ch": stripe_charge_id,
            },
        )
        await session.commit()
    return charge_id


async def _refund_rows(db_pool, parent_charge_id: UUID) -> list[dict]:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT kind, status, amount, stripe_refund_id, "
                "payment_method_type, refunds_charge_id FROM member_charges "
                "WHERE refunds_charge_id = :p"
            ),
            {"p": str(parent_charge_id)},
        )
        return [dict(r) for r in result.mappings().all()]


async def test_cash_refund_records_negative_cash_row(db_pool, stripe_client, created):
    """A cash charge refunds to a negative cash row — no stripe_refund_id
    (the migration-relaxed CHECK), no Stripe call."""
    service = _refund_service(db_pool, stripe_client)
    member = await created.member(GYM)
    charge_id = await _seed_payment_charge(
        db_pool,
        member.member_id,
        amount=4000,
        payment_method_type="cash",
        stripe_charge_id=None,
    )

    resp = await service.refund_charge(
        MemberMembershipsRefundRequest(
            member_id=member.member_id,
            charge_id=charge_id,
            idempotency_key=str(uuid4()),
        )
    )

    assert resp.payment_method == "cash"
    assert resp.refunded_amount == 4000
    rows = await _refund_rows(db_pool, charge_id)
    assert len(rows) == 1
    row = rows[0]
    assert row["kind"] == "refund"
    assert row["amount"] == -4000
    assert row["stripe_refund_id"] is None
    assert row["payment_method_type"] == "cash"
    assert row["refunds_charge_id"] == charge_id


async def test_card_refund_hits_stripe_and_records_row(
    db_pool, stripe_client, stripe_account_id, connect_opts, created
):
    """A card charge refunds via a REAL Stripe refund and records the row."""
    service = _refund_service(db_pool, stripe_client)
    gym_account = await GymStripeService(db_pool).get_stripe_account_id(GYM)
    # The endpoint refunds on the seeded gym's account; the charge must live
    # there too. The shared test account is that account.
    assert gym_account == stripe_account_id

    pm = await created.payment_method()
    member = await created.member(GYM, payment_method_id=pm)

    services = build_payment_services(stripe_client)
    product = await services.membership.create_membership(
        PaymentsMembershipCreateRequest(
            plan_name="Refund Endpoint Test",
            prices=[
                PaymentsMembershipPriceItem(
                    unit_amount=3000,
                    plan_type=PlanType.one_time,
                    recurring_interval=DurationUnit.month,
                    recurring_interval_count=1,
                    is_default=True,
                )
            ],
            metadata=StripeProductMetadata(plan_id=uuid4(), gym_id=GYM),
        ),
        stripe_account_id,
    )
    created.track_product(product.stripe_product_id)
    for p in product.prices:
        created.track_price(p.stripe_price_id)
    price_id = product.prices[0].stripe_price_id

    paid = await services.payment.create_invoice_payment(
        PaymentsInvoicePaymentCreateRequest(
            stripe_customer_id=member.stripe_customer_id,
            items=[PaymentsInvoiceItemSpec(stripe_price_id=price_id)],
            idempotency_key=str(uuid4()),
            metadata=StripeMembershipOneTimeMetadata(
                paid_by_member_id=member.member_id,
                paid_for=[member.member_id],
                gym_id=GYM,
                plan_id=uuid4(),
            ),
        ),
        stripe_account_id,
    )
    invoice = await stripe_client.client.v1.invoices.retrieve_async(
        paid.stripe_invoice_id,
        params={"expand": ["payments"]},
        options=connect_opts,
    )
    pi_id = invoice.payments.data[0].payment.payment_intent
    pi = await stripe_client.client.v1.payment_intents.retrieve_async(
        pi_id, options=connect_opts
    )
    charge_id = await _seed_payment_charge(
        db_pool,
        member.member_id,
        amount=3000,
        payment_method_type="card",
        stripe_charge_id=pi.latest_charge,
    )

    resp = await service.refund_charge(
        MemberMembershipsRefundRequest(
            member_id=member.member_id,
            charge_id=charge_id,
            amount=1000,
            idempotency_key=str(uuid4()),
        )
    )

    assert resp.payment_method == "card"
    assert resp.status == "succeeded"
    assert resp.refunded_amount == 1000
    rows = await _refund_rows(db_pool, charge_id)
    assert len(rows) == 1
    row = rows[0]
    assert row["amount"] == -1000
    assert row["stripe_refund_id"].startswith("re_")
    # The refund really exists on Stripe.
    refund = await stripe_client.client.v1.refunds.retrieve_async(
        row["stripe_refund_id"], options=connect_opts
    )
    assert refund.amount == 1000
    assert refund.charge == pi.latest_charge
