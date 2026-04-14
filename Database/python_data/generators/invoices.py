"""Invoice / line item / charge / applied-discount seed generator.

For each member's membership history this produces a coherent billing history:
- one invoice per payment the member would have made
- one membership line item per invoice, tied to the membership item_id
- one succeeded payment charge per invoice
- optionally an applied_discount row if the membership carried a discount

Failed / refunded charges are sprinkled in at a low rate so the CRM has a
realistic sample.
"""

import random
import uuid
from datetime import datetime, time, timedelta, timezone

from api_creation.discounts import DiscountRecord
from api_creation.plans import PlanRecord
from schema.member_membership import MemberMembershipCreate
from schema.user_gym_charge import (
    ChargeKind,
    ChargeStatus,
    UserGymChargeCreate,
)
from schema.user_gym_invoice import InvoiceStatus, UserGymInvoiceCreate
from schema.user_gym_invoice_applied_discount import (
    UserGymInvoiceAppliedDiscountCreate,
)
from schema.user_gym_invoice_line_item import (
    LineItemType,
    UserGymInvoiceLineItemCreate,
)

UNIT_DAYS = {"week": 7, "month": 30, "year": 365}

InvoiceBundle = tuple[
    list[UserGymInvoiceCreate],
    list[UserGymInvoiceLineItemCreate],
    list[UserGymChargeCreate],
    list[UserGymInvoiceAppliedDiscountCreate],
]


def _interval_days(plan: PlanRecord) -> int:
    if plan.duration_amount is not None and plan.duration_unit is not None:
        return UNIT_DAYS.get(plan.duration_unit, 30) * plan.duration_amount
    return 30


def _stripe_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:24]}"


def _as_dt(d) -> datetime:
    return datetime.combine(d, time(12, 0), tzinfo=timezone.utc)


def _billing_dates(
    membership: MemberMembershipCreate,
    plan: PlanRecord,
) -> list[datetime]:
    """Payment dates for a membership, capped at today."""
    today = datetime.now(timezone.utc).date()
    interval = _interval_days(plan)

    if plan.plan_type == "trial":
        # Trials bill once up front (even if the amount is zero-ish).
        return [_as_dt(membership.start_date)]

    if plan.plan_type == "one_time":
        return [_as_dt(membership.start_date)]

    # Recurring: one invoice at start, then every `interval` days until
    # cancel_date / end_date / today, whichever comes first.
    terminal = membership.cancel_date or membership.end_date or today
    terminal = min(terminal, today)

    dates: list[datetime] = []
    cursor = membership.start_date
    while cursor <= terminal:
        dates.append(_as_dt(cursor))
        cursor = cursor + timedelta(days=interval)
    # Always at least one invoice (the signup) even if terminal < start.
    if not dates:
        dates.append(_as_dt(membership.start_date))
    return dates


def _find_plan(plans: list[PlanRecord], plan_id: uuid.UUID) -> PlanRecord | None:
    for p in plans:
        if p.plan_id == plan_id:
            return p
    return None


def _discount_for_membership(
    membership: MemberMembershipCreate,
    discounts: list[DiscountRecord],
    linked_discounts: list[DiscountRecord],
) -> DiscountRecord | None:
    if not membership.discount_ids:
        return None
    first_id = membership.discount_ids[0]
    for d in discounts + linked_discounts:
        if d.discount_id == first_id:
            return d
    return None


def generate(
    gym_id: uuid.UUID,
    memberships: list[MemberMembershipCreate],
    plans: list[PlanRecord],
    discounts: list[DiscountRecord],
    linked_discounts: list[DiscountRecord],
) -> InvoiceBundle:
    invoices: list[UserGymInvoiceCreate] = []
    line_items: list[UserGymInvoiceLineItemCreate] = []
    charges: list[UserGymChargeCreate] = []
    applied_discounts: list[UserGymInvoiceAppliedDiscountCreate] = []

    for membership in memberships:
        plan = _find_plan(plans, membership.plan_id)
        if plan is None:
            continue

        discount = _discount_for_membership(membership, discounts, linked_discounts)
        line_name = plan.plan_name

        for billing_time in _billing_dates(membership, plan):
            invoice_id = uuid.uuid4()
            total = membership.total_price
            stripe_invoice_id = _stripe_id("in")
            stripe_pi_id = _stripe_id("pi")

            invoices.append(
                UserGymInvoiceCreate(
                    invoice_id=invoice_id,
                    gym_id=gym_id,
                    crm_user_id=membership.crm_user_id,
                    status=InvoiceStatus.paid,
                    total_amount=total,
                    currency="usd",
                    stripe_invoice_id=stripe_invoice_id,
                    stripe_payment_intent_id=stripe_pi_id,
                    invoice_time=billing_time,
                )
            )

            line_items.append(
                UserGymInvoiceLineItemCreate(
                    line_item_id=_stripe_id("il"),
                    invoice_id=invoice_id,
                    gym_id=gym_id,
                    item_type=LineItemType.membership,
                    name=line_name,
                    amount=total,
                    stripe_product_id=_stripe_id("prod"),
                    item_id=membership.item_id,
                )
            )

            if discount is not None:
                # Snapshot of the applied dollar value. For percentage
                # discounts this is a best-effort reconstruction from the
                # membership's total_price; for dollar discounts it's the
                # discount's own dollar_off.
                if discount.dollar_off is not None:
                    amount_off = discount.dollar_off
                elif discount.percentage_off is not None:
                    amount_off = round(total * discount.percentage_off / 100)
                else:
                    amount_off = 0

                applied_discounts.append(
                    UserGymInvoiceAppliedDiscountCreate(
                        applied_discount_id=uuid.uuid4(),
                        invoice_id=invoice_id,
                        gym_id=gym_id,
                        discount_id=discount.discount_id,
                        amount_off=amount_off,
                        stripe_coupon_id=_stripe_id("coup"),
                    )
                )

            # 5% of invoices simulate one failed attempt before succeeding.
            if random.random() < 0.05:
                charges.append(
                    UserGymChargeCreate(
                        charge_id=uuid.uuid4(),
                        invoice_id=invoice_id,
                        gym_id=gym_id,
                        crm_user_id=membership.crm_user_id,
                        kind=ChargeKind.payment,
                        status=ChargeStatus.failed,
                        amount=total,
                        currency="usd",
                        payment_method_type="card",
                        stripe_charge_id=_stripe_id("ch"),
                        charge_time=billing_time,
                    )
                )

            success_charge_id = uuid.uuid4()
            charges.append(
                UserGymChargeCreate(
                    charge_id=success_charge_id,
                    invoice_id=invoice_id,
                    gym_id=gym_id,
                    crm_user_id=membership.crm_user_id,
                    kind=ChargeKind.payment,
                    status=ChargeStatus.succeeded,
                    amount=total,
                    currency="usd",
                    payment_method_type=random.choice(["card", "us_bank_account"]),
                    stripe_charge_id=_stripe_id("ch"),
                    charge_time=billing_time + timedelta(minutes=1),
                )
            )

            # 3% of successful payments get refunded (full refund).
            if random.random() < 0.03:
                charges.append(
                    UserGymChargeCreate(
                        charge_id=uuid.uuid4(),
                        invoice_id=invoice_id,
                        gym_id=gym_id,
                        crm_user_id=membership.crm_user_id,
                        kind=ChargeKind.refund,
                        status=ChargeStatus.succeeded,
                        amount=-total,
                        currency="usd",
                        payment_method_type="card",
                        stripe_refund_id=_stripe_id("re"),
                        refunds_charge_id=success_charge_id,
                        charge_time=billing_time
                        + timedelta(days=random.randint(1, 14)),
                    )
                )

    return invoices, line_items, charges, applied_discounts
