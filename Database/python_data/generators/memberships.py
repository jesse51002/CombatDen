"""Historical (already-closed) membership rows — direct DB inserts with fake IDs.

Live memberships go through the backend API (see api_creation/memberships.py).
This module only produces closed/ended/cancelled rows that represent past
lifecycle for a member. Stripe IDs on these rows are synthesized because
the real Stripe subscriptions don't exist and we're not time-travelling.

This module also exposes `pseudo_rows_for_current()`, which builds
non-inserted MemberMembershipCreate objects for *current* (real) memberships
with simulated historical dates. Those pseudo rows are used by invoices.py
to generate a synthetic billing history behind each real subscription.
"""

from __future__ import annotations

import random
import uuid
from datetime import date, timedelta

from api_creation.memberships import CurrentMembershipRecord
from generators.profiles import HistoricalMembership, ProfilePlan
from schema.member_membership import MemberMembershipCreate
from supabase import Client
from utils import random_past_date

UNIT_DAYS = {"week": 7, "month": 30, "year": 365}


def _to_row(
    profile: ProfilePlan,
    gym_id: uuid.UUID,
    h: HistoricalMembership,
) -> MemberMembershipCreate:
    assert profile.crm_user_id is not None
    return MemberMembershipCreate(
        item_id=uuid.uuid4(),
        crm_user_id=profile.crm_user_id,
        gym_id=gym_id,
        plan_id=h.plan.plan_id,
        price_id=h.plan.price_id,
        start_date=h.start_date,
        end_date=h.end_date,
        cancel_date=h.cancel_date,
        last_paid_date=h.last_paid_date,
        next_due_date=None,
        prorate=True,
        total_price=h.total_price,
        stripe_item_id=f"si_{uuid.uuid4().hex[:24]}",
        discount_ids=list(h.discount_ids) if h.discount_ids else None,
    )


def create_history(
    client: Client,
    gym_id: uuid.UUID,
    profiles: list[ProfilePlan],
) -> list[MemberMembershipCreate]:
    """Insert historical membership rows for every profile that has history."""
    rows: list[MemberMembershipCreate] = []
    for profile in profiles:
        for h in profile.history:
            rows.append(_to_row(profile, gym_id, h))

    if rows:
        client.table("member_memberships").insert([r.to_insert_dict() for r in rows]).execute()
    return rows


def pseudo_rows_for_current(
    gym_id: uuid.UUID,
    current_records: list[CurrentMembershipRecord],
) -> list[MemberMembershipCreate]:
    """Build non-inserted MemberMembershipCreate rows for live memberships.

    Used only for invoice generation — we want fake past invoices behind each
    real subscription, spanning from a simulated signup date up through today.
    The real item_id and stripe_item_id come from the CurrentMembershipRecord
    (so line items can reference the real subscription); everything else is
    synthesized.
    """
    today = date.today()
    pseudo: list[MemberMembershipCreate] = []
    for rec in current_records:
        plan = rec.profile.current.plan if rec.profile.current else None
        if plan is None:
            continue
        if plan.plan_type == "recurring":
            # Simulate a signup 1-6 months in the past so we build a plausible
            # recurring-invoice history.
            start = random_past_date(180)
            last_paid = start + timedelta(
                days=random.randint(
                    0,
                    max(
                        1,
                        (_interval(plan) * ((today - start).days // _interval(plan)))
                        if (today - start).days >= _interval(plan)
                        else 1,
                    ),
                )
            )
            next_due = last_paid + timedelta(days=_interval(plan))
        else:
            # One-time / trial: started recently, one invoice.
            start = random_past_date(30)
            last_paid = start
            next_due = None

        pseudo.append(
            MemberMembershipCreate(
                item_id=rec.item_id,
                crm_user_id=rec.profile.crm_user_id,  # type: ignore[arg-type]
                gym_id=gym_id,
                plan_id=rec.plan_id,
                price_id=rec.price_id,
                start_date=start,
                end_date=None,
                cancel_date=None,
                last_paid_date=last_paid,
                next_due_date=next_due,
                prorate=True,
                total_price=rec.total_price,
                stripe_item_id=rec.stripe_item_id,
                discount_ids=(
                    list(rec.profile.current.discount_ids)
                    if rec.profile.current and rec.profile.current.discount_ids
                    else None
                ),
            )
        )
    return pseudo


def _interval(plan) -> int:
    if plan.duration_amount is not None and plan.duration_unit is not None:
        return UNIT_DAYS.get(plan.duration_unit, 30) * plan.duration_amount
    return 30
