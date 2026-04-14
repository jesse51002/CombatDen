"""In-memory profile & membership plan builder.

`build_plans()` produces a `ProfilePlan` per member describing everything
downstream steps need to create:
  - demographics for the members API POST
  - optional link-to-primary relationship (applied post-creation via DB update)
  - optional account-level freeze window (applied post-creation via DB update)
  - a `CurrentMembership` plan (if any) — this gets created through the backend
    API in `api_creation/memberships.py` so real Stripe subscriptions exist
  - `HistoricalMembership` rows for any past lifecycle — these get written
    directly to the DB in `generators/memberships.py` with fake Stripe IDs

Nothing in this module touches the DB. It's pure planning.
"""

from __future__ import annotations

import random
import uuid
from dataclasses import dataclass, field
from datetime import date, timedelta
from pathlib import Path
from typing import Optional

import yaml
from faker import Faker

from api_creation.discounts import DiscountRecord
from api_creation.plans import PlanRecord
from constants import LINKED_MEMBERS_PER_GYM, MEMBERS_PER_GYM
from utils import today_offset

_images_path = Path(__file__).parent / "sample_images.yaml"
with open(_images_path) as f:
    _sample_images: list[str] = yaml.safe_load(f)

fake = Faker()

MAX_LINKED_MEMBERS = 5
UNIT_DAYS = {"week": 7, "month": 30, "year": 365}


@dataclass
class Demographics:
    first_name: str
    last_name: str
    email: str
    phone: str
    address: str
    photo_url: str
    points_balance: int
    emergency_contact_name: str
    emergency_contact_phone: str
    emergency_contact_email: str
    # When this profile is a linked auth account, the Supabase user ID.
    auth_user_id: Optional[uuid.UUID] = None


@dataclass
class CurrentMembership:
    """The active / about-to-be-frozen / about-to-be-cancelled membership."""

    plan: PlanRecord
    discount_ids: list[uuid.UUID] = field(default_factory=list)
    include_linked_discount: bool = False
    prorate: bool = True
    # Post-creation modifiers
    freeze_months: Optional[int] = None
    cancel_after_start: bool = False


@dataclass
class HistoricalMembership:
    """A closed-in-the-past membership row, faked directly into the DB."""

    plan: PlanRecord
    start_date: date
    end_date: Optional[date]
    cancel_date: Optional[date]
    last_paid_date: Optional[date]
    total_price: int
    discount_ids: list[uuid.UUID] = field(default_factory=list)


@dataclass
class ProfilePlan:
    local_handle: str  # e.g. "gym0/profile3"
    demographics: Demographics
    # Post-create DB tweaks (account_linked_to_id, freeze window)
    linked_primary_handle: Optional[str] = None
    linked_discount_id: Optional[uuid.UUID] = None
    account_freeze_start: Optional[date] = None
    account_freeze_end: Optional[date] = None
    current: Optional[CurrentMembership] = None
    history: list[HistoricalMembership] = field(default_factory=list)
    # Populated after the members API call returns
    crm_user_id: Optional[uuid.UUID] = None


def _random_phone() -> str:
    """A phone number Stripe will accept (max 20 chars, no extensions)."""
    # +1 followed by 10 digits = 12 chars total, well under Stripe's 20-char cap.
    return f"+1{random.randint(2000000000, 9999999999)}"


def _random_demographics(auth_user_id: uuid.UUID | None) -> Demographics:
    return Demographics(
        first_name=fake.first_name(),
        last_name=fake.last_name(),
        email=fake.unique.email(),
        phone=_random_phone(),
        address=fake.address().replace("\n", ", "),
        photo_url=random.choice(_sample_images),
        points_balance=random.randint(0, 500),
        emergency_contact_name=fake.name(),
        emergency_contact_phone=_random_phone(),
        emergency_contact_email=fake.email(),
        auth_user_id=auth_user_id,
    )


def _interval_days(plan: PlanRecord) -> int:
    if plan.duration_amount is not None and plan.duration_unit is not None:
        return UNIT_DAYS.get(plan.duration_unit, 30) * plan.duration_amount
    return 30


def _build_historical(
    plan: PlanRecord,
    start: date,
    cancel: date,
    is_linked: bool,
    discounts: list[DiscountRecord],
    linked_discounts: list[DiscountRecord],
) -> HistoricalMembership:
    """Build a historical (already-cancelled) membership row."""
    is_recurring = plan.plan_type == "recurring"
    interval = _interval_days(plan)

    end_date = None if is_recurring else cancel + timedelta(days=random.randint(0, 14))
    last_paid = start + timedelta(days=random.randint(0, interval * 2))

    total_price = plan.base_cost
    discount_ids: list[uuid.UUID] = []

    if is_linked and linked_discounts:
        plan_linked = [
            d for d in linked_discounts if d.membership_plan_id == plan.plan_id
        ]
        if plan_linked:
            disc = plan_linked[0]
            total_price = max(0, total_price - (disc.dollar_off or 0))
            discount_ids.append(disc.discount_id)
    elif discounts and random.random() < 0.3:
        disc = random.choice(discounts)
        discount_ids.append(disc.discount_id)
        total_price = round(total_price * 0.9)

    return HistoricalMembership(
        plan=plan,
        start_date=start,
        end_date=end_date,
        cancel_date=cancel,
        last_paid_date=last_paid,
        total_price=total_price,
        discount_ids=discount_ids,
    )


def _pick_current_discounts(
    plan: PlanRecord,
    is_linked: bool,
    discounts: list[DiscountRecord],
    linked_discounts: list[DiscountRecord],
) -> tuple[list[uuid.UUID], bool]:
    """Pick discount_ids + include_linked_discount flag for a live membership."""
    if is_linked and linked_discounts:
        plan_linked = [
            d for d in linked_discounts if d.membership_plan_id == plan.plan_id
        ]
        if plan_linked and random.choice([True, False]):
            return [], True  # backend auto-applies the linked tier
    if discounts and random.random() < 0.3:
        return [random.choice(discounts).discount_id], False
    return [], False


def build_plans(
    gym_handle: str,
    linked_auth_user_ids: list[uuid.UUID],
    plans: list[PlanRecord],
    discounts: list[DiscountRecord],
    linked_discounts: list[DiscountRecord],
) -> list[ProfilePlan]:
    """Build the full list of ProfilePlans for one gym.

    linked_auth_user_ids: the N Supabase auth user IDs reserved as "linked"
    members for this gym (see bootstrap/gyms.py). The first N profiles get
    those auth IDs so members can log in as themselves.
    """
    profiles: list[ProfilePlan] = []
    for i in range(MEMBERS_PER_GYM):
        auth_id = linked_auth_user_ids[i] if i < LINKED_MEMBERS_PER_GYM else None
        profiles.append(
            ProfilePlan(
                local_handle=f"{gym_handle}/profile{i}",
                demographics=_random_demographics(auth_id),
            )
        )

    # Partition into linked family groups. ~50% live alone, ~50% are in a
    # primary/linked-child group.
    shuffled = list(profiles)
    random.shuffle(shuffled)
    split = len(shuffled) // 2
    linkable = shuffled[split:]

    linked_set: set[str] = set()
    while linkable:
        root = linkable.pop()
        num_linked = min(random.randint(1, MAX_LINKED_MEMBERS), len(linkable))
        for _ in range(num_linked):
            child = linkable.pop()
            child.linked_primary_handle = root.local_handle
            linked_set.add(child.local_handle)

    # Account-level freezes (~15% of parents/singles)
    for p in profiles:
        if p.linked_primary_handle is not None:
            continue
        if random.random() < 0.15:
            freeze_start = today_offset(-random.randint(1, 30))
            freeze_duration = random.randint(7, 60)
            p.account_freeze_start = freeze_start
            p.account_freeze_end = freeze_start + timedelta(days=freeze_duration)

    # Membership journeys
    trial_plans = [p for p in plans if p.plan_type == "trial"]
    paid_plans = [p for p in plans if p.plan_type in ("recurring", "one_time")]

    for profile in profiles:
        is_linked = profile.local_handle in linked_set
        roll = random.random()

        if roll < 0.05:
            # 5%: no membership at all
            continue

        elif roll < 0.30 and trial_plans and paid_plans:
            # 25%: finished trial, now on a paid plan (current is paid)
            trial_plan = random.choice(trial_plans)
            trial_cancel = today_offset(-random.randint(14, 120))
            trial_start = trial_cancel - timedelta(days=_interval_days(trial_plan))
            profile.history.append(
                _build_historical(
                    trial_plan,
                    start=trial_start,
                    cancel=trial_cancel,
                    is_linked=is_linked,
                    discounts=discounts,
                    linked_discounts=linked_discounts,
                )
            )
            paid_plan = random.choice(paid_plans)
            d_ids, use_linked = _pick_current_discounts(
                paid_plan, is_linked, discounts, linked_discounts
            )
            profile.current = CurrentMembership(
                plan=paid_plan,
                discount_ids=d_ids,
                include_linked_discount=use_linked,
            )

        elif roll < 0.55 and trial_plans:
            # 25%: trial only — current is the trial (active or expiring)
            trial_plan = random.choice(trial_plans)
            profile.current = CurrentMembership(
                plan=trial_plan,
                prorate=False,
            )

        elif roll < 0.75 and paid_plans:
            # 20%: direct purchase, currently active
            paid_plan = random.choice(paid_plans)
            d_ids, use_linked = _pick_current_discounts(
                paid_plan, is_linked, discounts, linked_discounts
            )
            profile.current = CurrentMembership(
                plan=paid_plan,
                discount_ids=d_ids,
                include_linked_discount=use_linked,
            )

        elif roll < 0.90 and paid_plans:
            # 15%: cancelled in the past, re-signed recently
            first_plan = random.choice(paid_plans)
            first_start = date.today() - timedelta(days=random.randint(121, 300))
            cancel_date = first_start + timedelta(days=random.randint(30, 120))
            profile.history.append(
                _build_historical(
                    first_plan,
                    start=first_start,
                    cancel=cancel_date,
                    is_linked=is_linked,
                    discounts=discounts,
                    linked_discounts=linked_discounts,
                )
            )
            second_plan = random.choice(paid_plans)
            d_ids, use_linked = _pick_current_discounts(
                second_plan, is_linked, discounts, linked_discounts
            )
            profile.current = CurrentMembership(
                plan=second_plan,
                discount_ids=d_ids,
                include_linked_discount=use_linked,
            )

        elif trial_plans and paid_plans:
            # 10%: trial → cancelled paid → re-signed (two historical + one current)
            trial_plan = random.choice(trial_plans)
            trial_cancel = date.today() - timedelta(days=random.randint(180, 260))
            trial_start = trial_cancel - timedelta(days=_interval_days(trial_plan))
            profile.history.append(
                _build_historical(
                    trial_plan,
                    start=trial_start,
                    cancel=trial_cancel,
                    is_linked=is_linked,
                    discounts=discounts,
                    linked_discounts=linked_discounts,
                )
            )
            first_plan = random.choice(paid_plans)
            first_start = trial_cancel + timedelta(days=random.randint(0, 7))
            cancel_days = random.randint(30, 120)
            if first_start + timedelta(days=cancel_days) >= date.today():
                first_start = date.today() - timedelta(
                    days=cancel_days + random.randint(1, 30)
                )
            cancel_date = first_start + timedelta(days=cancel_days)
            profile.history.append(
                _build_historical(
                    first_plan,
                    start=first_start,
                    cancel=cancel_date,
                    is_linked=is_linked,
                    discounts=discounts,
                    linked_discounts=linked_discounts,
                )
            )
            second_plan = random.choice(paid_plans)
            d_ids, use_linked = _pick_current_discounts(
                second_plan, is_linked, discounts, linked_discounts
            )
            profile.current = CurrentMembership(
                plan=second_plan,
                discount_ids=d_ids,
                include_linked_discount=use_linked,
            )

    return profiles
