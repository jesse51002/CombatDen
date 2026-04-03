import random
from datetime import date, timedelta
from uuid import UUID

from constants import DEFAULT_LINKED_MEMBER_DISCOUNT
from schema.gym_discount import GymDiscountCreate
from schema.member_membership import MemberMembershipCreate
from schema.membership_plan import MembershipPlanCreate
from schema.user_gym_profile import UserGymProfileCreate
from utils import random_past_date, today_offset

UNIT_DAYS = {"week": 7, "month": 30, "year": 365}
FREEZE_DURATION_DAYS = (7, 60)
MAX_LINKED_MEMBERS = 5


def _build_membership(
    profile: UserGymProfileCreate,
    plan: MembershipPlanCreate,
    discounts: list[GymDiscountCreate],
    is_linked: bool = False,
    expired_trial: bool = False,
    start_after: date | None = None,
) -> MemberMembershipCreate:
    if start_after is not None:
        start = start_after + timedelta(days=random.randint(0, 7))
    else:
        start = random_past_date(180)

    intent = random.choices(
        ["active", "frozen", "cancelled", "ended"], weights=[60, 15, 15, 10]
    )[0]

    interval = UNIT_DAYS.get(plan.duration_unit, 30) * plan.duration_amount

    end_date = None
    cancel_date = None
    last_paid = None
    next_due = None
    freeze_start_date = None
    freeze_end_date = None

    if plan.plan_type == "trial":
        if expired_trial:
            end_date = today_offset(-random.randint(14, 120))
        else:
            end_date = today_offset(random.randint(-7, 7))
        start = end_date - timedelta(days=interval)
    elif intent == "cancelled":
        cancel_date = start + timedelta(days=random.randint(14, 150))
        end_date = cancel_date + timedelta(days=random.randint(0, 30))
        last_paid = start + timedelta(days=random.randint(0, interval * 3))
    elif intent == "ended":
        end_date = start + timedelta(days=random.randint(14, 150))
        last_paid = start + timedelta(days=random.randint(0, interval * 3))
    elif intent == "frozen":
        last_paid = start + timedelta(days=random.randint(0, interval * 3))
        freeze_start_date = today_offset(-random.randint(1, 30))
        freeze_duration = random.randint(*FREEZE_DURATION_DAYS)
        freeze_end_date = freeze_start_date + timedelta(days=freeze_duration)
        next_due = freeze_end_date + timedelta(days=random.randint(1, interval))
    else:
        last_paid = start + timedelta(days=random.randint(0, interval * 3))
        next_due = last_paid + timedelta(days=interval)

    total_price = plan.base_cost
    discount_ids = None

    if is_linked:
        discount_pct = plan.additional_member_discount or DEFAULT_LINKED_MEMBER_DISCOUNT
        total_price = round(total_price * (1 - discount_pct / 100), 2)
    elif discounts and random.random() < 0.3:
        discount_ids = [random.choice(discounts).discount_id]
        total_price = round(total_price * 0.9, 2)

    return MemberMembershipCreate(
        crm_user_id=profile.crm_user_id,
        gym_id=profile.gym_id,
        plan_id=plan.plan_id,
        start_date=start,
        end_date=end_date,
        cancel_date=cancel_date,
        freeze_start_date=freeze_start_date,
        freeze_end_date=freeze_end_date,
        last_paid_date=last_paid,
        next_due_date=next_due,
        total_price=total_price,
        discount_ids=discount_ids,
    )


def generate(
    profiles: list[UserGymProfileCreate],
    plans: list[MembershipPlanCreate],
    discounts: list[GymDiscountCreate],
) -> tuple[list[MemberMembershipCreate], list[tuple[UUID, UUID]]]:
    memberships: list[MemberMembershipCreate] = []
    link_pairs: list[tuple[UUID, UUID]] = []

    # Phase A: Partition into singles (~50%) and linked groups (~50%)
    shuffled = list(profiles)
    random.shuffle(shuffled)
    split = len(shuffled) // 2
    singles = shuffled[:split]
    linkable = shuffled[split:]

    # Build linked groups from the linkable pool
    linked_set: set[UUID] = set()
    while linkable:
        root = linkable.pop()
        num_linked = min(random.randint(1, MAX_LINKED_MEMBERS), len(linkable))
        for _ in range(num_linked):
            linked = linkable.pop()
            link_pairs.append((linked.crm_user_id, root.crm_user_id))
            linked_set.add(linked.crm_user_id)

    # Phase B: Assign memberships based on member journey
    # 35% trial → converted to paid, 35% trial only, 25% direct purchase, 5% no membership
    trial_plans = [p for p in plans if p.plan_type == "trial"]
    paid_plans = [p for p in plans if p.plan_type in ("recurring", "one_time")]

    for profile in profiles:
        is_linked = profile.crm_user_id in linked_set
        roll = random.random()

        if roll < 0.05:
            # 5%: no membership
            continue

        elif roll < 0.40 and trial_plans:
            # 35%: trial first, then converted to a paid membership
            trial = _build_membership(
                profile, random.choice(trial_plans), discounts, is_linked,
                expired_trial=True,
            )
            memberships.append(trial)
            if paid_plans:
                paid = _build_membership(
                    profile, random.choice(paid_plans), discounts, is_linked,
                    start_after=trial.end_date,
                )
                memberships.append(paid)

        elif roll < 0.75 and trial_plans:
            # 35%: trial only (mix of active and expired, never converted)
            trial = _build_membership(
                profile, random.choice(trial_plans), discounts, is_linked,
            )
            memberships.append(trial)

        else:
            # 25%: direct purchase (or fallback when no trial plan)
            if paid_plans:
                memberships.append(
                    _build_membership(profile, random.choice(paid_plans), discounts, is_linked)
                )

    return memberships, link_pairs
