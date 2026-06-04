"""Synthetic invoice + line-item + charge history.

Generated direct-DB (service-role) from the membership rows (closed history +
the live memberships' pseudo rows). Stripe IDs here are synthesized (in_*,
ch_*, ...) — these rows are the CRM's billing past, not real Stripe invoices.

Applied-discount history is no longer emitted here: memberships are seeded
discount-free (discounts are explicit snapshot adds via FastApiBackend Phase 2),
so there are no per-invoice discount snapshots to backfill yet.
"""

from __future__ import annotations

import random
import uuid
from datetime import UTC, date, datetime, time, timedelta

from api_creation.plans import PlanRecord
from constants import UNIT_DAYS
from schema.member_charge import ChargeKind, ChargeStatus, MemberChargeCreate
from schema.member_invoice import InvoiceStatus, MemberInvoiceCreate
from schema.member_invoice_line_item import LineItemType, MemberInvoiceLineItemCreate
from schema.member_membership import MemberMembershipCreate

InvoiceBundle = tuple[
    list[MemberInvoiceCreate],
    list[MemberInvoiceLineItemCreate],
    list[MemberChargeCreate],
]


def _interval_days(plan: PlanRecord) -> int:
    if plan.duration_amount and plan.duration_unit:
        return UNIT_DAYS.get(plan.duration_unit, 30) * plan.duration_amount
    return 30


def _billing_dates(m: MemberMembershipCreate, plan: PlanRecord) -> list[datetime]:
    """Invoice datetimes (UTC noon) across the membership's billed life."""
    start = datetime.combine(m.start_date, time(12, 0, tzinfo=UTC))
    if plan.plan_type in ("trial", "one_time"):
        return [start]

    interval = _interval_days(plan)
    today = date.today()
    terminal = min(d for d in (m.cancel_date, m.end_date, today) if d is not None)
    dates: list[datetime] = []
    cursor = m.start_date
    while cursor <= terminal:
        dates.append(datetime.combine(cursor, time(12, 0, tzinfo=UTC)))
        cursor = cursor + timedelta(days=interval)
    return dates or [start]


def generate(
    gym_id: uuid.UUID,
    memberships: list[MemberMembershipCreate],
    plans: list[PlanRecord],
) -> InvoiceBundle:
    plan_by_id = {p.plan_id: p for p in plans}

    invoices: list[MemberInvoiceCreate] = []
    line_items: list[MemberInvoiceLineItemCreate] = []
    charges: list[MemberChargeCreate] = []

    for m in memberships:
        plan = plan_by_id.get(m.plan_id)
        if plan is None:
            continue

        for billed_at in _billing_dates(m, plan):
            invoice_id = uuid.uuid4()
            invoices.append(
                MemberInvoiceCreate(
                    invoice_id=invoice_id,
                    gym_id=gym_id,
                    member_id=m.member_id,
                    status=InvoiceStatus.paid,
                    total_amount=m.total_price,
                    currency="usd",
                    stripe_invoice_id=f"in_{uuid.uuid4().hex[:24]}",
                    stripe_payment_intent_id=f"pi_{uuid.uuid4().hex[:24]}",
                    invoice_time=billed_at,
                )
            )
            line_items.append(
                MemberInvoiceLineItemCreate(
                    line_item_id=f"il_{uuid.uuid4().hex[:24]}",
                    invoice_id=invoice_id,
                    gym_id=gym_id,
                    item_type=LineItemType.membership,
                    name=plan.plan_name,
                    amount=m.total_price,
                    stripe_product_id=plan.stripe_product_id,
                    item_id=m.item_id,
                )
            )
            # ~5% of invoices have a failed attempt before the success.
            if random.random() < 0.05:
                charges.append(
                    MemberChargeCreate(
                        charge_id=uuid.uuid4(),
                        invoice_id=invoice_id,
                        gym_id=gym_id,
                        member_id=m.member_id,
                        kind=ChargeKind.payment,
                        status=ChargeStatus.failed,
                        amount=m.total_price,
                        currency="usd",
                        stripe_charge_id=f"ch_{uuid.uuid4().hex[:24]}",
                        charge_time=billed_at,
                    )
                )

            success_charge_id = uuid.uuid4()
            charges.append(
                MemberChargeCreate(
                    charge_id=success_charge_id,
                    invoice_id=invoice_id,
                    gym_id=gym_id,
                    member_id=m.member_id,
                    kind=ChargeKind.payment,
                    status=ChargeStatus.succeeded,
                    amount=m.total_price,
                    currency="usd",
                    payment_method_type=random.choice(["card", "us_bank_account"]),
                    stripe_charge_id=f"ch_{uuid.uuid4().hex[:24]}",
                    charge_time=billed_at + timedelta(minutes=1),
                )
            )

            # ~3% of successful charges get a full refund later.
            if random.random() < 0.03:
                charges.append(
                    MemberChargeCreate(
                        charge_id=uuid.uuid4(),
                        invoice_id=invoice_id,
                        gym_id=gym_id,
                        member_id=m.member_id,
                        kind=ChargeKind.refund,
                        status=ChargeStatus.succeeded,
                        amount=-m.total_price,
                        currency="usd",
                        stripe_refund_id=f"re_{uuid.uuid4().hex[:24]}",
                        refunds_charge_id=success_charge_id,
                        charge_time=billed_at + timedelta(days=random.randint(1, 14)),
                    )
                )

    return invoices, line_items, charges
