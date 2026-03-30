import random
from datetime import timedelta

from schema.gym_discount import GymDiscountCreate
from schema.member_membership import MemberMembershipCreate
from schema.membership_plan import MembershipPlanCreate
from schema.user_gym_profile import UserGymProfileCreate
from utils import random_past_date

CYCLE_DAYS = {"monthly": 30, "yearly": 365, "weekly": 7}


def generate(
    profiles: list[UserGymProfileCreate],
    plans: list[MembershipPlanCreate],
    discounts: list[GymDiscountCreate],
) -> list[MemberMembershipCreate]:
    memberships = []
    for profile in profiles:
        plan = random.choice(plans)
        start = random_past_date(180)
        status = random.choices(
            ["active", "frozen", "cancelled"], weights=[70, 15, 15]
        )[0]

        interval = CYCLE_DAYS.get(plan.billing_cycle, 30)
        last_paid = start + timedelta(days=random.randint(0, interval * 3))
        next_due = last_paid + timedelta(days=interval)

        discount_ids = None
        if discounts and random.random() < 0.3:
            discount_ids = [random.choice(discounts).discount_id]

        memberships.append(
            MemberMembershipCreate(
                crm_user_id=profile.crm_user_id,
                gym_id=profile.gym_id,
                plan_id=plan.plan_id,
                start_date=start,
                status=status,
                last_paid_date=last_paid,
                next_due_date=next_due,
                discount_ids=discount_ids,
            )
        )
    return memberships
