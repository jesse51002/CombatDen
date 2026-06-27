"""Direct-DB historical memberships + synthetic rows for invoice generation.

`create_history` inserts each member's closed (cancelled / ended) memberships
into member_memberships_unfiltered. They carry fake `si_*` stripe_item_ids
(no real Stripe subscription — they're history). Inserting them BEFORE the
live memberships are started keeps the recurring chronological/no-active/
no-overlap triggers happy (history is all in the past and cancelled).

`pseudo_rows_for_current` builds synthetic rows for the live memberships (using
their real item_id / stripe_item_id) so the invoice generator can give each a
plausible billing past. These rows are NOT inserted.
"""

from __future__ import annotations

import uuid
from datetime import date, timedelta

from api_creation.memberships import CurrentMembershipRecord
from constants import UNIT_DAYS
from generators.members import MemberPlan
from schema.member_membership import (
    MemberMembershipCreate,
    StripeSyncStatus,
)
from supabase import Client
from utils import random_past_date


def _interval_days(duration_amount: int | None, duration_unit: str | None) -> int:
    if duration_amount and duration_unit:
        return UNIT_DAYS.get(duration_unit, 30) * duration_amount
    return 30


def _payer_id(
    member: MemberPlan, handle_to_id: dict[str, uuid.UUID]
) -> uuid.UUID:
    """The member's payer: a self-paying child (or any non-linked member) pays
    themselves; a parent-paid linked child is paid by their linked parent."""
    if not member.self_pays and member.linked_primary_handle is not None:
        return handle_to_id[member.linked_primary_handle]
    assert member.member_id is not None
    return member.member_id


def _handle_to_id(members: list[MemberPlan]) -> dict[str, uuid.UUID]:
    return {
        m.local_handle: m.member_id for m in members if m.member_id is not None
    }


def create_history(
    client: Client,
    gym_id: uuid.UUID,
    members: list[MemberPlan],
) -> list[MemberMembershipCreate]:
    """Insert every member's closed history rows; return them for invoicing."""
    handle_to_id = _handle_to_id(members)
    rows: list[MemberMembershipCreate] = []
    for member in members:
        assert member.member_id is not None
        for h in member.history:
            rows.append(
                MemberMembershipCreate(
                    item_id=uuid.uuid4(),
                    member_id=member.member_id,
                    paid_by_member_id=_payer_id(member, handle_to_id),
                    gym_id=gym_id,
                    plan_id=h.plan.plan_id,
                    price_id=h.plan.price_id,
                    start_date=h.start_date,
                    end_date=h.end_date,
                    cancel_date=h.cancel_date,
                    last_paid_date=h.last_paid_date,
                    next_due_date=None,
                    total_price=h.total_price,
                    stripe_item_id=f"si_{uuid.uuid4().hex[:24]}",
                    # Direct-inserted (not via the API), so stamp the Stripe-sync
                    # status ourselves — the 'not_added' default is hidden by the
                    # client-facing member_memberships view. A cancelled
                    # membership was removed from Stripe → 'deleted' (matches the
                    # real cancel flow's writeback); a non-recurring one that
                    # ended by date was never removed, so it stays 'applied'.
                    stripe_sync_status=(
                        StripeSyncStatus.deleted
                        if h.cancel_date is not None
                        else StripeSyncStatus.applied
                    ),
                )
            )

    if not rows:
        return rows

    # Chronological order keeps the recurring start-date trigger happy.
    rows.sort(key=lambda r: r.start_date)
    client.table("member_memberships_unfiltered").insert(
        [r.to_insert_dict() for r in rows]
    ).execute()
    return rows


def pseudo_rows_for_current(
    gym_id: uuid.UUID,
    current_records: list[CurrentMembershipRecord],
    members: list[MemberPlan],
) -> list[MemberMembershipCreate]:
    """Synthetic (non-inserted) rows for live memberships, for invoicing."""
    handle_to_id = _handle_to_id(members)
    today = date.today()
    rows: list[MemberMembershipCreate] = []
    for rec in current_records:
        current = rec.member.current
        if current is None:
            continue
        plan = current.plan
        if plan.plan_type == "recurring":
            interval = _interval_days(plan.duration_amount, plan.duration_unit)
            start = random_past_date(180)
            cycles = max(0, (today - start).days // max(1, interval))
            last_paid = start + timedelta(days=interval * cycles)
            next_due = last_paid + timedelta(days=interval)
        else:
            start = random_past_date(30)
            last_paid = start
            next_due = None
        rows.append(
            MemberMembershipCreate(
                item_id=rec.item_id,
                member_id=rec.member.member_id,
                paid_by_member_id=_payer_id(rec.member, handle_to_id),
                gym_id=gym_id,
                plan_id=rec.plan_id,
                price_id=rec.price_id,
                start_date=start,
                end_date=None,
                cancel_date=None,
                last_paid_date=last_paid,
                next_due_date=next_due,
                total_price=rec.total_price,
                stripe_item_id=rec.stripe_item_id,
            )
        )
    return rows
