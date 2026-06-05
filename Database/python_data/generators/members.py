"""In-memory member builder.

Each member is a unified identity + billing/contact row (the merged `members`
table). The seed creates the identity shell via the backend, then sets billing
columns. This generator assigns every member:

  - demographics (name, email, phone, address, emergency contacts, points)
  - a current_rank_id picked from the gym's cloned ladder
  - a billing lifecycle: a current membership and/or closed history, derived
    so the CRM status views populate with a realistic spread (active, trial,
    cancelled, ended, frozen) — overdue members are seeded separately via the
    Stripe test-clock path.
  - optional linked-account family membership (a paying parent + children,
    each child on its own membership covered by the parent; children are
    linked to the parent first, then their membership is started so it rides
    the parent's subscription).

Member status is NOT stored on members — it derives from
member_memberships_status (billing) and the freeze window on the account.
"""

from __future__ import annotations

import random
import uuid
from dataclasses import dataclass, field
from datetime import date, timedelta

from api_creation.plans import PlanRecord
from constants import (
    LINKED_FAMILY_FRACTION,
    MAX_LINKED_CHILDREN_PER_PARENT,
    MEMBERS_PER_GYM,
    UNIT_DAYS,
)
from faker import Faker
from schema.gym_rank import GymRankCreate
from schema.member import MemberCreate
from utils import today_offset

fake = Faker()


@dataclass
class CurrentMembership:
    """A live membership to start via the backend (real Stripe subscription).

    Discounts are no longer applied at membership creation: applying a discount
    is an explicit add (a snapshot row on member_membership_applied_discounts)
    via a dedicated backend path (FastApiBackend Phase 2). The seed creates
    memberships discount-free; seeding applied-discount snapshots is a Phase 2
    follow-up once that apply endpoint lands.
    """

    plan: PlanRecord
    prorate: bool = True
    cancel_after_start: bool = False


@dataclass
class HistoricalMembership:
    """A closed (cancelled / ended) membership inserted direct-DB as history."""

    plan: PlanRecord
    start_date: date
    end_date: date | None
    cancel_date: date | None
    last_paid_date: date | None
    total_price: int


@dataclass
class MemberPlan:
    local_handle: str
    first_name: str
    last_name: str
    email: str
    phone: str
    address: str
    emergency_contact_name: str
    emergency_contact_phone: str
    emergency_contact_email: str
    points_balance: int
    current_rank_id: uuid.UUID | None
    photo_url: str | None = None
    auth_user_id: uuid.UUID | None = None
    # Linked-account family: a child references its parent's handle; the
    # parent's real member_id is resolved after creation by the backend link
    # endpoint, then the child's own membership is started under the parent.
    linked_primary_handle: str | None = None
    # Account-level freeze window (parents/singles only — never children).
    account_freeze_start: date | None = None
    account_freeze_end: date | None = None
    # Billing lifecycle.
    current: CurrentMembership | None = None
    history: list[HistoricalMembership] = field(default_factory=list)
    # Populated after the backend POST /members assigns the id.
    member_id: uuid.UUID | None = None

    @property
    def is_linked_child(self) -> bool:
        return self.linked_primary_handle is not None


# --------------------------------------------------------------------------
# Demographics + rank
# --------------------------------------------------------------------------


def _random_phone() -> str:
    # Stripe-friendly E.164-ish format.
    return f"+1{random.randint(2000000000, 9999999999)}"


def _demographics(handle: str, current_rank_id: uuid.UUID | None) -> MemberPlan:
    return MemberPlan(
        local_handle=handle,
        first_name=fake.first_name(),
        last_name=fake.last_name(),
        email=fake.unique.email(),
        phone=_random_phone(),
        address=fake.address().replace("\n", ", "),
        emergency_contact_name=fake.name(),
        emergency_contact_phone=_random_phone(),
        emergency_contact_email=fake.email(),
        points_balance=random.randint(0, 500),
        current_rank_id=current_rank_id,
    )


def _pick_rank_id(ranks: list[GymRankCreate]) -> uuid.UUID | None:
    if not ranks:
        return None
    sorted_ranks = sorted(ranks, key=lambda r: (r.main_rank_num_order, r.sub_rank_num_order))
    idx = int(random.triangular(0, len(sorted_ranks) - 1, 0))
    return sorted_ranks[idx].rank_id


# --------------------------------------------------------------------------
# Plan/discount helpers
# --------------------------------------------------------------------------


def _interval_days(plan: PlanRecord) -> int:
    if plan.duration_amount and plan.duration_unit:
        return UNIT_DAYS.get(plan.duration_unit, 30) * plan.duration_amount
    return 30


def _plans_of_type(plans: list[PlanRecord], plan_type: str) -> list[PlanRecord]:
    return [p for p in plans if p.plan_type == plan_type]


# --------------------------------------------------------------------------
# Lifecycle builders (non-family members)
# --------------------------------------------------------------------------


def _historical_closed(
    plan: PlanRecord,
    start: date,
    cancel: date,
    natural_end: bool,
) -> HistoricalMembership:
    interval = _interval_days(plan)
    if natural_end:
        end_date = cancel
        cancel_date = None
    elif plan.plan_type == "one_time":
        end_date = cancel + timedelta(days=random.randint(0, 14))
        cancel_date = cancel
    else:  # recurring — cancelled, no end_date
        end_date = None
        cancel_date = cancel
    return HistoricalMembership(
        plan=plan,
        start_date=start,
        end_date=end_date,
        cancel_date=cancel_date,
        last_paid_date=start + timedelta(days=random.randint(0, max(1, interval))),
        total_price=plan.base_cost,
    )


def _assign_lifecycle(
    member: MemberPlan,
    plans: list[PlanRecord],
) -> None:
    """Pick a billing journey for a non-family member.

    Cohorts (roughly): never-started, former (history only), trial-only,
    trial->paid, active-direct, re-signup. Covers the active/trial/cancelled/
    ended/no-membership CRM states; frozen is layered on afterward.
    """
    recurring = _plans_of_type(plans, "recurring")
    trials = _plans_of_type(plans, "trial")
    if not recurring:
        return  # nothing to do without at least one recurring plan

    roll = random.random()

    if roll < 0.08:
        # Never started — no membership, no history.
        return

    if roll < 0.18:
        # Former member — one closed recurring membership, no current.
        start = today_offset(-random.randint(120, 300))
        cancel = start + timedelta(days=random.randint(30, 120))
        member.history.append(
            _historical_closed(random.choice(recurring), start, cancel, natural_end=False)
        )
        return

    if roll < 0.43 and trials:
        # Trial only — current trial membership.
        member.current = CurrentMembership(plan=random.choice(trials))
        return

    if roll < 0.63 and trials:
        # Trial -> paid: an ended trial in history, recurring current.
        trial = random.choice(trials)
        trial_end = today_offset(-random.randint(14, 90))
        trial_start = trial_end - timedelta(days=_interval_days(trial))
        member.history.append(
            _historical_closed(trial, trial_start, trial_end, natural_end=True)
        )
        member.current = CurrentMembership(plan=random.choice(recurring))
        return

    if roll < 0.85:
        # Active direct — recurring current, no history.
        member.current = CurrentMembership(
            plan=random.choice(recurring),
            cancel_after_start=random.random() < 0.1,
        )
        return

    # Re-signup — one cancelled recurring in history, recurring current.
    first = random.choice(recurring)
    first_start = today_offset(-random.randint(150, 320))
    first_cancel = first_start + timedelta(days=random.randint(30, 120))
    member.history.append(
        _historical_closed(first, first_start, first_cancel, natural_end=False)
    )
    member.current = CurrentMembership(plan=random.choice(recurring))


def _apply_freezes(members: list[MemberPlan]) -> None:
    """~15% of non-child members with a current membership get a frozen window."""
    for m in members:
        if m.is_linked_child or m.current is None:
            continue
        if random.random() < 0.15:
            m.account_freeze_start = today_offset(-random.randint(1, 20))
            m.account_freeze_end = m.account_freeze_start + timedelta(
                days=random.randint(7, 60)
            )


def _form_linked_families(
    members: list[MemberPlan],
    recurring: list[PlanRecord],
) -> set[int]:
    """Partition ~LINKED_FAMILY_FRACTION of the gym into linked-account families.

    Mirrors the original CRM seed: shuffle the members, take a fraction of them
    as "linkable", then repeatedly pull one off as a paying parent (root) and
    give it 1-MAX_LINKED_CHILDREN_PER_PARENT children. Roots get a forced
    recurring membership — the backend link endpoint requires the parent to have
    an active recurring subscription. Each child also gets its own recurring
    membership (on any plan, not necessarily the parent's); the child references
    the root via linked_primary_handle and is linked (cardless) after creation,
    and its membership is started afterward so the item rides the parent's
    subscription. (Linked-discount presets are gone — a family discount is now
    an explicit snapshot applied via the Phase 2 apply path, not auto-assigned
    here.)

    Operates on member *indices* (never reorders `members`, since create_all
    keys the first AUTH_MEMBERS_PER_GYM members to real auth logins by position).
    Returns the set of indices that belong to a family (roots + children) so the
    caller skips them in the normal lifecycle pass.
    """
    family_idx: set[int] = set()
    linkable = list(range(len(members)))
    random.shuffle(linkable)
    linkable = linkable[int(len(linkable) * (1 - LINKED_FAMILY_FRACTION)) :]

    while len(linkable) >= 2:  # need a root plus at least one child
        root = linkable.pop()
        members[root].current = CurrentMembership(plan=random.choice(recurring))
        family_idx.add(root)
        num_children = min(
            random.randint(1, MAX_LINKED_CHILDREN_PER_PARENT), len(linkable)
        )
        for _ in range(num_children):
            child = linkable.pop()
            members[child].linked_primary_handle = members[root].local_handle
            # Each child carries its own membership (any recurring plan — not
            # necessarily the parent's). Started AFTER the child is linked so
            # the item rides the parent's subscription.
            members[child].current = CurrentMembership(plan=random.choice(recurring))
            family_idx.add(child)

    return family_idx


# --------------------------------------------------------------------------
# Public builder
# --------------------------------------------------------------------------


def build_plans(
    gym_handle: str,
    ranks: list[GymRankCreate],
    plans: list[PlanRecord],
) -> list[MemberPlan]:
    """Build MEMBERS_PER_GYM member plans for one gym.

    Memberships are seeded discount-free: applying a discount is now an explicit
    snapshot add (FastApiBackend Phase 2). Family linking itself (the paying
    parent + cardless children under it) is unchanged.
    """
    members: list[MemberPlan] = [
        _demographics(f"{gym_handle}/member{i}", _pick_rank_id(ranks))
        for i in range(MEMBERS_PER_GYM)
    ]

    # Linked-account families (mirrors the original CRM seed). Form them when a
    # recurring plan exists — the backend link endpoint requires the parent to
    # have an active recurring subscription.
    recurring = _plans_of_type(plans, "recurring")
    family_member_idx: set[int] = set()
    if recurring:
        family_member_idx = _form_linked_families(members, recurring)

    # Everyone outside a family gets a cohort lifecycle.
    for i, member in enumerate(members):
        if i in family_member_idx:
            continue
        _assign_lifecycle(member, plans)

    _apply_freezes(members)
    return members


def to_member_create(gym_id: uuid.UUID, plan: MemberPlan) -> MemberCreate:
    """Identity view used by the engagement bootstrap (classes, attendance,
    redemptions, activities). Requires plan.member_id to be set (post-create).
    """
    assert plan.member_id is not None, "to_member_create called before member was created"
    return MemberCreate(
        member_id=plan.member_id,
        gym_id=gym_id,
        first_name=plan.first_name,
        last_name=plan.last_name,
        email=plan.email,
        points_balance=plan.points_balance,
        current_rank_id=plan.current_rank_id,
    )
