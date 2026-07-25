"""In-memory member builder.

Each member is a unified identity + billing/contact row (the merged `members`
table). The seed creates the identity shell via the backend, then sets billing
columns. This generator assigns every member:

  - demographics (name, email, phone, address, date of birth, emergency
    contacts). Points are NOT set here: a member's balance is earned from
    their attendance later in the engagement phase (generators/classes.
    award_attendance_points), so it starts at 0.
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
from typing import TYPE_CHECKING

from api_creation.plans import PlanRecord
from constants import (
    CHILD_SELF_PAY_FRACTION,
    CUSTOM_DISCOUNT_PROBABILITY,
    DISCOUNTS_PER_MEMBERSHIP_MAX,
    LINKED_CHILD_MAX_AGE_YEARS,
    LINKED_CHILD_MIN_AGE_YEARS,
    LINKED_FAMILY_FRACTION,
    MAX_LINKED_CHILDREN_PER_PARENT,
    MEMBER_MAX_AGE_YEARS,
    MEMBER_MIN_AGE_YEARS,
    MEMBERS_PER_GYM,
    TEST_MEMBER_EMAIL,
    UNIT_DAYS,
)
from faker import Faker
from schema.gym_rank import GymRankCreate
from schema.member import MemberCreate
from utils import today_offset

if TYPE_CHECKING:
    from api_creation.discounts import DiscountRecord

fake = Faker()


@dataclass
class CurrentMembership:
    """A live membership to start via the backend (real Stripe subscription).

    ``discount_ids`` is a pre-drawn set (0-DISCOUNTS_PER_MEMBERSHIP_MAX distinct
    regular discounts) sent as this membership's item in the family's single
    start request (POST /member_memberships/), so the discounts land before the
    first charge — no separate add call. The draw happens in the sequential build
    phase (``_assign_discounts``) so the random choices stay deterministic and
    the concurrent creation pipeline only does I/O.

    ``custom_discount`` is an optional inline one-shot DiscountValue dict minted
    at start time (the backend creates a ``custom`` discount entry and applies it
    before the first charge). A membership may carry both preset discount_ids and
    one custom discount. The draw happens alongside the preset draw in
    ``_assign_custom_discounts``.

    ``count`` is how many units to buy. One-time / trial packs may STACK, so a
    class-pack holder is seeded with ``count`` in 1-3, sent as the start item's
    ``quantity`` — ONE membership billing that many units (a single Stripe line),
    not N rows. Always 1 for recurring (recurring stays one-active-per-plan).
    """

    plan: PlanRecord
    cancel_after_start: bool = False
    count: int = 1
    discount_ids: list[uuid.UUID] = field(default_factory=list)
    custom_discount: dict | None = None


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
    # Always populated (nullable in the DB, but blank reads as broken on the
    # CRM member page). Adult band, except a linked child, which
    # _form_linked_families re-draws into the minor band.
    date_of_birth: date
    emergency_contact_name: str
    emergency_contact_phone: str
    emergency_contact_email: str
    # Starts at 0 and is EARNED, never drawn: award_attendance_points sets it
    # from the member's seeded attendance, and redemptions debit it.
    points_balance: int
    current_rank_id: uuid.UUID | None
    # Leaf position within current_rank_id's main rank: an index in
    # [0, sub_rank_count-1] when that rank has sub-ranks, else None.
    current_sub_index: int | None = None
    photo_url: str | None = None
    # Set once a real Supabase auth login is created for this member (idx <
    # AUTH_MEMBERS_PER_GYM). Its email is already this MemberPlan's `email` —
    # that IS the access link now (no user_id FK) — so this field is only an
    # in-memory "already has a login" / idempotency marker, never written to
    # the member row.
    auth_user_id: uuid.UUID | None = None
    # Linked-account family: a child references its parent's handle; the
    # parent's real member_id is resolved after creation by the backend link
    # endpoint, then the child's own membership is started under the parent.
    linked_primary_handle: str | None = None
    # A linked child who pays for their OWN membership (own card + own
    # subscription). Still linked to the parent (authorization), but
    # paid_by_member_id = themselves. False for roots/solos and parent-paid
    # children.
    self_pays: bool = False
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


def _random_birth_date(min_age: int, max_age: int) -> date:
    """A plausible birth date inside the given age band (adult or minor).

    Faker draws from the same PRNG `Faker.seed(SEED)` fixes, so a re-run
    reproduces the same dates and the idempotency layer's email-keyed lookups
    still match.
    """
    return fake.date_of_birth(minimum_age=min_age, maximum_age=max_age)


def _demographics(
    handle: str,
    current_rank_id: uuid.UUID | None,
    current_sub_index: int | None,
) -> MemberPlan:
    return MemberPlan(
        local_handle=handle,
        first_name=fake.first_name(),
        last_name=fake.last_name(),
        email=fake.unique.email(),
        phone=_random_phone(),
        address=fake.address().replace("\n", ", "),
        date_of_birth=_random_birth_date(MEMBER_MIN_AGE_YEARS, MEMBER_MAX_AGE_YEARS),
        emergency_contact_name=fake.name(),
        emergency_contact_phone=_random_phone(),
        emergency_contact_email=fake.email(),
        points_balance=0,
        current_rank_id=current_rank_id,
        current_sub_index=current_sub_index,
    )


def _pick_leaf(ranks: list[GymRankCreate]) -> tuple[uuid.UUID | None, int | None]:
    """Pick a valid leaf: a main rank (triangular skew toward the lowest rank),
    then a sub-index within it (None when that rank has no sub-ranks, else a
    random index in [0, sub_rank_count-1]). Rank-less gym -> (None, None)."""
    if not ranks:
        return None, None
    sorted_ranks = sorted(ranks, key=lambda r: r.main_rank_num_order)
    idx = int(random.triangular(0, len(sorted_ranks) - 1, 0))
    chosen = sorted_ranks[idx]
    sub_index = (
        random.randint(0, chosen.sub_rank_count - 1)
        if chosen.sub_rank_count > 0
        else None
    )
    return chosen.rank_id, sub_index


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
    one_times = _plans_of_type(plans, "one_time")
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

    if roll < 0.80:
        # Active direct — recurring current, no history.
        member.current = CurrentMembership(
            plan=random.choice(recurring),
            cancel_after_start=random.random() < 0.1,
        )
        return

    if roll < 0.90 and one_times:
        # Active class-pack holder — 1-3 stacked one-time memberships on the
        # same plan (exercises holding several one-time packs at once). Falls
        # through to re-signup when the gym has no one-time plan.
        member.current = CurrentMembership(
            plan=random.choice(one_times),
            count=random.randint(1, 3),
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


def _assign_discounts(
    members: list[MemberPlan],
    discounts: list[DiscountRecord],
) -> None:
    """Pre-draw 0-DISCOUNTS_PER_MEMBERSHIP_MAX distinct discounts per membership.

    Drawn here in the sequential build phase (not in the concurrent creation
    pipeline) so the choices stay deterministic under the seed PRNG and the
    worker threads only do I/O. A membership that is cancelled right after start
    gets none (pointless). Stores discount ids on each member's CurrentMembership;
    the creation pipeline applies them after the membership is started.
    """
    if not discounts:
        return
    cap = min(DISCOUNTS_PER_MEMBERSHIP_MAX, len(discounts))
    for m in members:
        if m.current is None or m.current.cancel_after_start:
            continue
        k = random.randint(0, cap)
        if k == 0:
            continue
        chosen = random.sample(discounts, k)
        m.current.discount_ids = [d.discount_id for d in chosen]


def _random_custom_discount() -> dict:
    """Return one DiscountValue dict chosen from four representative shapes.

    Shapes are sampled uniformly to spread variety across seeded memberships:
      0 — percent (10-25 %), 1 cycle (the single-invoice case that replaced once)
      1 — dollar amount ($5-$15, expressed in cents), 1 cycle
      2 — percent with a 2-3 month duration
      3 — percent, forever (no duration, no end_date)

    Dollar amounts are deliberately small so they're safe vs. the cheapest
    plan price even if Stripe floors at zero.
    """
    shape = random.randint(0, 3)
    if shape == 0:
        return {
            "percentage_off": round(random.uniform(10.0, 25.0), 1),
            "duration_amount": 1,
            "duration_unit": "cycle",
        }
    if shape == 1:
        return {
            "dollar_off": random.randint(500, 1500),
            "duration_amount": 1,
            "duration_unit": "cycle",
        }
    if shape == 2:
        return {
            "percentage_off": round(random.uniform(5.0, 20.0), 1),
            "duration_amount": random.randint(2, 3),
            "duration_unit": "month",
        }
    # shape == 3: percent, forever
    return {
        "percentage_off": round(random.uniform(5.0, 15.0), 1),
    }


def _assign_custom_discounts(members: list[MemberPlan]) -> None:
    """Randomly attach one inline custom discount to ~CUSTOM_DISCOUNT_PROBABILITY
    of live, non-cancel-at-start memberships.

    Drawn here in the sequential build phase (alongside ``_assign_discounts``)
    so the PRNG advances deterministically. A membership may carry both preset
    ``discount_ids`` and a ``custom_discount`` — these are not mutually
    exclusive. At most one custom discount per membership.
    """
    for m in members:
        if m.current is None or m.current.cancel_after_start:
            continue
        if random.random() < CUSTOM_DISCOUNT_PROBABILITY:
            m.current.custom_discount = _random_custom_discount()


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
    recurring membership. Each child also gets its own recurring membership (on
    any plan, not necessarily the parent's) and references the root via
    linked_primary_handle. ~CHILD_SELF_PAY_FRACTION of children SELF-PAY their
    membership (``self_pays`` — own card, billed to their own subscription); the
    rest are paid by the parent (the item rides the parent's subscription).
    Either way the child is linked to the parent (the link is the authorization
    layer, not the billing key). Regular discounts are drawn per membership in
    ``_assign_discounts`` (family members included, like any other membership).

    Who is a child is only decided HERE — the partition needs the built
    MemberPlan list — so each child's adult date of birth is re-drawn into the
    minor band as it is picked.

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
            # A linked child is a minor: re-draw into the child band.
            members[child].date_of_birth = _random_birth_date(
                LINKED_CHILD_MIN_AGE_YEARS, LINKED_CHILD_MAX_AGE_YEARS
            )
            # Each child carries its own membership (any recurring plan — not
            # necessarily the parent's). ~CHILD_SELF_PAY_FRACTION self-pay it on
            # their own card + own subscription; the rest ride the parent's.
            members[child].current = CurrentMembership(plan=random.choice(recurring))
            members[child].self_pays = random.random() < CHILD_SELF_PAY_FRACTION
            family_idx.add(child)

    return family_idx


# --------------------------------------------------------------------------
# Public builder
# --------------------------------------------------------------------------


def build_plans(
    gym_handle: str,
    ranks: list[GymRankCreate],
    plans: list[PlanRecord],
    discounts: list[DiscountRecord],
) -> list[MemberPlan]:
    """Build MEMBERS_PER_GYM member plans for one gym.

    Each live membership is given a random 0-DISCOUNTS_PER_MEMBERSHIP_MAX set of
    distinct regular discounts (pre-drawn here; applied after the membership is
    started). Additionally, ~CUSTOM_DISCOUNT_PROBABILITY of live memberships also
    receive one inline custom discount (a one-shot DiscountValue minted at start).
    Family linking puts a paying parent over 1-MAX_LINKED_CHILDREN_PER_PARENT
    children, each on their own membership: ~CHILD_SELF_PAY_FRACTION of them
    carry their own card and subscription, the rest ride the parent's. Linked/
    family discounts are not seeded.
    """
    members: list[MemberPlan] = [
        _demographics(f"{gym_handle}/member{i}", *_pick_leaf(ranks))
        for i in range(MEMBERS_PER_GYM)
    ]

    # Linked-account families (mirrors the original CRM seed). Form them when a
    # recurring plan exists — the backend link endpoint requires the parent to
    # have an active recurring subscription.
    recurring = _plans_of_type(plans, "recurring")
    family_member_idx: set[int] = set()
    if recurring:
        family_member_idx = _form_linked_families(members, recurring)

    _assign_test_member_emails(members, family_member_idx)

    # Everyone outside a family gets a cohort lifecycle.
    for i, member in enumerate(members):
        if i in family_member_idx:
            continue
        _assign_lifecycle(member, plans)

    _apply_freezes(members)
    _assign_discounts(members, discounts)
    _assign_custom_discounts(members)
    return members


def _assign_test_member_emails(
    members: list[MemberPlan],
    family_member_idx: set[int],
) -> None:
    """Give THREE members the known test email (TEST_MEMBER_EMAIL).

    The member app's identity model is a verified-email match, and
    ``members.email`` is deliberately non-unique (families share an inbox), so
    the known login must resolve to several rows to exercise the app's
    multi-profile picker. Deterministic picks (lowest index each): a family
    ROOT, that root's first linked CHILD, and an INDEPENDENT (non-family)
    member. Runs AFTER family formation (it needs the links) and consumes no
    randomness, so the seeded Faker/random sequences are untouched. With no
    families formed (no recurring plan), falls back to the first three members.
    """
    picks: list[MemberPlan] = []
    root = next(
        (
            members[i]
            for i in sorted(family_member_idx)
            if members[i].linked_primary_handle is None
        ),
        None,
    )
    if root is not None:
        picks.append(root)
        child = next(
            (
                m
                for m in members
                if m.linked_primary_handle == root.local_handle
            ),
            None,
        )
        if child is not None:
            picks.append(child)
    independent = next(
        (
            members[i]
            for i in range(len(members))
            if i not in family_member_idx
        ),
        None,
    )
    if independent is not None:
        picks.append(independent)
    # Degenerate seeds (tiny MEMBERS_PER_GYM, no families): top up from the
    # front of the list so three rows always carry the email when possible.
    for member in members:
        if len(picks) >= 3:
            break
        if member not in picks:
            picks.append(member)
    for member in picks:
        member.email = TEST_MEMBER_EMAIL


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
        current_sub_index=plan.current_sub_index,
    )
