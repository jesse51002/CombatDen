import random
from datetime import date, timedelta
from uuid import UUID, uuid4

from schema.gym_discount import GymDiscountCreate
from schema.member_membership import MemberMembershipCreate
from schema.membership_plan import MembershipPlanCreate
from schema.membership_plan_price import MembershipPlanPriceCreate
from schema.user_gym_profile import UserGymProfileCreate
from utils import random_past_date, today_offset

UNIT_DAYS = {"week": 7, "month": 30, "year": 365}
MAX_LINKED_MEMBERS = 5


def _build_membership(
    profile: UserGymProfileCreate,
    plan: MembershipPlanCreate,
    price: MembershipPlanPriceCreate,
    discounts: list[GymDiscountCreate],
    linked_discounts: list[GymDiscountCreate],
    is_linked: bool = False,
    expired_trial: bool = False,
    start_after: date | None = None,
) -> MemberMembershipCreate:
    if start_after is not None:
        start = start_after + timedelta(days=random.randint(0, 7))
    else:
        start = random_past_date(180)

    is_recurring = plan.plan_type == "recurring"

    if is_recurring:
        intent = random.choices(
            ["active", "cancelled"], weights=[80, 20]
        )[0]
    else:
        intent = random.choices(
            ["active", "cancelled", "ended"], weights=[75, 15, 10]
        )[0]

    if plan.duration_amount is not None and plan.duration_unit is not None:
        interval = UNIT_DAYS.get(plan.duration_unit, 30) * plan.duration_amount
    else:
        interval = 30

    end_date = None
    cancel_date = None
    last_paid = None
    next_due = None

    if plan.plan_type == "trial":
        if expired_trial:
            end_date = today_offset(-random.randint(14, 120))
        else:
            end_date = today_offset(random.randint(-7, 7))
        start = end_date - timedelta(days=interval)
    elif intent == "cancelled":
        cancel_date = start + timedelta(days=random.randint(14, 150))
        if not is_recurring:
            end_date = cancel_date + timedelta(days=random.randint(0, 30))
        last_paid = start + timedelta(days=random.randint(0, interval * 3))
    elif intent == "ended":
        end_date = start + timedelta(days=random.randint(14, 150))
        last_paid = start + timedelta(days=random.randint(0, interval * 3))
    else:
        last_paid = start + timedelta(days=random.randint(0, interval * 3))
        next_due = last_paid + timedelta(days=interval)

    prorate = random.random() >= 0.2

    total_price = price.price
    discount_ids = None

    if is_linked and linked_discounts:
        # Pick the first available linked discount for this plan
        plan_linked = [
            d for d in linked_discounts
            if d.membership_plan_id == plan.plan_id
        ]
        if plan_linked:
            disc = plan_linked[0]
            total_price = max(0, total_price - disc.dollar_off)
            discount_ids = [disc.discount_id]
    elif discounts and random.random() < 0.3:
        disc = random.choice(discounts)
        discount_ids = [disc.discount_id]
        total_price = round(total_price * 0.9)

    stripe_item_id = f"si_{uuid4().hex[:24]}"

    return MemberMembershipCreate(
        item_id=uuid4(),
        crm_user_id=profile.crm_user_id,
        gym_id=profile.gym_id,
        plan_id=plan.plan_id,
        price_id=price.price_id,
        start_date=start,
        end_date=end_date,
        cancel_date=cancel_date,
        last_paid_date=last_paid,
        next_due_date=next_due,
        prorate=prorate,
        total_price=total_price,
        stripe_item_id=stripe_item_id,
        discount_ids=discount_ids,
    )


def _build_cancelled_membership(
    profile: UserGymProfileCreate,
    plan: MembershipPlanCreate,
    price: MembershipPlanPriceCreate,
    discounts: list[GymDiscountCreate],
    linked_discounts: list[GymDiscountCreate],
    is_linked: bool,
    start: date,
    cancel_date: date,
) -> MemberMembershipCreate:
    """Build a membership that is definitively cancelled in the past."""
    is_recurring = plan.plan_type == "recurring"

    if plan.duration_amount is not None and plan.duration_unit is not None:
        interval = UNIT_DAYS.get(plan.duration_unit, 30) * plan.duration_amount
    else:
        interval = 30

    end_date = None if is_recurring else cancel_date + timedelta(days=random.randint(0, 14))
    last_paid = start + timedelta(days=random.randint(0, interval * 2))

    total_price = price.price
    discount_ids = None

    if is_linked and linked_discounts:
        plan_linked = [
            d for d in linked_discounts
            if d.membership_plan_id == plan.plan_id
        ]
        if plan_linked:
            disc = plan_linked[0]
            total_price = max(0, total_price - disc.dollar_off)
            discount_ids = [disc.discount_id]
    elif discounts and random.random() < 0.3:
        disc = random.choice(discounts)
        discount_ids = [disc.discount_id]
        total_price = round(total_price * 0.9)

    return MemberMembershipCreate(
        item_id=uuid4(),
        crm_user_id=profile.crm_user_id,
        gym_id=profile.gym_id,
        plan_id=plan.plan_id,
        price_id=price.price_id,
        start_date=start,
        end_date=end_date,
        cancel_date=cancel_date,
        last_paid_date=last_paid,
        next_due_date=None,
        prorate=random.random() >= 0.2,
        total_price=total_price,
        stripe_item_id=f"si_{uuid4().hex[:24]}",
        discount_ids=discount_ids,
    )


def generate(
    profiles: list[UserGymProfileCreate],
    plans: list[MembershipPlanCreate],
    prices: dict[UUID, MembershipPlanPriceCreate],
    discounts: list[GymDiscountCreate],
    linked_discounts: list[GymDiscountCreate],
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
    # 25% trial → paid, 25% trial only, 20% direct purchase,
    # 15% cancelled → re-signed, 10% trial → cancelled → re-signed, 5% no membership
    trial_plans = [p for p in plans if p.plan_type == "trial"]
    paid_plans = [p for p in plans if p.plan_type in ("recurring", "one_time")]

    for profile in profiles:
        is_linked = profile.crm_user_id in linked_set
        roll = random.random()

        if roll < 0.05:
            # 5%: no membership
            continue

        elif roll < 0.30 and trial_plans:
            # 25%: trial first, then converted to a paid membership
            trial_plan = random.choice(trial_plans)
            trial = _build_membership(
                profile, trial_plan, prices[trial_plan.plan_id],
                discounts, linked_discounts, is_linked,
                expired_trial=True,
            )
            memberships.append(trial)
            if paid_plans:
                paid_plan = random.choice(paid_plans)
                paid = _build_membership(
                    profile, paid_plan, prices[paid_plan.plan_id],
                    discounts, linked_discounts, is_linked,
                    start_after=trial.end_date,
                )
                memberships.append(paid)

        elif roll < 0.55 and trial_plans:
            # 25%: trial only (mix of active and expired, never converted)
            trial_plan = random.choice(trial_plans)
            trial = _build_membership(
                profile, trial_plan, prices[trial_plan.plan_id],
                discounts, linked_discounts, is_linked,
            )
            memberships.append(trial)

        elif roll < 0.75:
            # 20%: direct purchase (or fallback when no trial plan)
            if paid_plans:
                paid_plan = random.choice(paid_plans)
                memberships.append(
                    _build_membership(
                        profile, paid_plan, prices[paid_plan.plan_id],
                        discounts, linked_discounts, is_linked,
                    )
                )

        elif roll < 0.90 and paid_plans:
            # 15%: cancelled membership, then re-signed with a new one
            first_plan = random.choice(paid_plans)
            first_start = date.today() - timedelta(days=random.randint(121, 300))
            cancel_date = first_start + timedelta(days=random.randint(30, 120))
            first = _build_cancelled_membership(
                profile, first_plan, prices[first_plan.plan_id],
                discounts, linked_discounts, is_linked,
                start=first_start, cancel_date=cancel_date,
            )
            memberships.append(first)
            second_plan = random.choice(paid_plans)
            second = _build_membership(
                profile, second_plan, prices[second_plan.plan_id],
                discounts, linked_discounts, is_linked,
                start_after=cancel_date,
            )
            memberships.append(second)

        elif trial_plans and paid_plans:
            # 10%: trial → cancelled paid → re-signed
            trial_plan = random.choice(trial_plans)
            trial = _build_membership(
                profile, trial_plan, prices[trial_plan.plan_id],
                discounts, linked_discounts, is_linked,
                expired_trial=True,
            )
            memberships.append(trial)
            first_plan = random.choice(paid_plans)
            first_start = trial.end_date + timedelta(days=random.randint(0, 7))
            cancel_days = random.randint(30, 120)
            # Ensure cancel_date is in the past so the trigger doesn't
            # consider this membership active when inserting the next one
            if first_start + timedelta(days=cancel_days) >= date.today():
                first_start = date.today() - timedelta(days=cancel_days + random.randint(1, 30))
            cancel_date = first_start + timedelta(days=cancel_days)
            first = _build_cancelled_membership(
                profile, first_plan, prices[first_plan.plan_id],
                discounts, linked_discounts, is_linked,
                start=first_start, cancel_date=cancel_date,
            )
            memberships.append(first)
            second_plan = random.choice(paid_plans)
            second = _build_membership(
                profile, second_plan, prices[second_plan.plan_id],
                discounts, linked_discounts, is_linked,
                start_after=cancel_date,
            )
            memberships.append(second)

    return memberships, link_pairs
