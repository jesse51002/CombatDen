import random
from datetime import timedelta

from schema.gym_discount import GymDiscountCreate
from schema.member_membership import MemberMembershipCreate
from schema.membership_plan import MembershipPlanCreate
from schema.user_gym_profile import UserGymProfileCreate
from utils import random_past_date

UNIT_DAYS = {"week": 7, "month": 30, "year": 365}
FREEZE_DURATION_DAYS = (7, 60)


def generate(
    profiles: list[UserGymProfileCreate],
    plans: list[MembershipPlanCreate],
    discounts: list[GymDiscountCreate],
) -> list[MemberMembershipCreate]:
    memberships = []
    unlinked = list(profiles)
    random.shuffle(unlinked)

    while unlinked:
        profile = unlinked.pop()
        plan = random.choice(plans)
        start = random_past_date(180)
        status = random.choices(
            ["active", "frozen", "cancelled"], weights=[70, 15, 15]
        )[0]

        interval = UNIT_DAYS.get(plan.duration_unit, 30) * plan.duration_amount
        last_paid = start + timedelta(days=random.randint(0, interval * 3))
        next_due = last_paid + timedelta(days=interval)

        end_date = None
        if plan.plan_type == "trial":
            status = "active"
            interval = UNIT_DAYS.get(plan.duration_unit, 30) * plan.duration_amount
            end_date = start + timedelta(days=interval)
        elif status == "cancelled":
            end_date = start + timedelta(days=random.randint(14, 150))

        freeze_start_date = None
        freeze_end_date = None
        if status == "frozen":
            freeze_start_date = start + timedelta(days=random.randint(7, 90))
            freeze_duration = random.randint(*FREEZE_DURATION_DAYS)
            freeze_end_date = freeze_start_date + timedelta(days=freeze_duration)

        discount_ids = None
        total_price = plan.base_cost
        if discounts and random.random() < 0.3:
            discount_ids = [random.choice(discounts).discount_id]
            total_price = round(total_price * 0.9, 2)

        # Link additional members if the plan supports it
        linked_ids: list = []
        if plan.additional_member_costs and unlinked:
            num_linked = min(
                random.randint(1, len(plan.additional_member_costs)),
                len(unlinked),
            )
            for i in range(num_linked):
                linked_profile = unlinked.pop()
                extra_cost = plan.additional_member_costs[i]
                total_price = round(total_price + extra_cost, 2)
                linked_ids.append(linked_profile)

        memberships.append(
            MemberMembershipCreate(
                crm_user_id=profile.crm_user_id,
                gym_id=profile.gym_id,
                plan_id=plan.plan_id,
                start_date=start,
                status=status,
                end_date=end_date,
                freeze_start_date=freeze_start_date,
                freeze_end_date=freeze_end_date,
                last_paid_date=last_paid,
                next_due_date=next_due,
                total_price=total_price,
                discount_ids=discount_ids,
            )
        )

        # Create memberships for linked members pointing back to primary
        for linked_profile in linked_ids:
            memberships.append(
                MemberMembershipCreate(
                    crm_user_id=linked_profile.crm_user_id,
                    gym_id=linked_profile.gym_id,
                    plan_id=plan.plan_id,
                    start_date=start,
                    status=status,
                    freeze_start_date=freeze_start_date,
                    freeze_end_date=freeze_end_date,
                    last_paid_date=last_paid,
                    next_due_date=next_due,
                    total_price=0,
                    account_linked_to_id=profile.crm_user_id,
                )
            )

    return memberships
