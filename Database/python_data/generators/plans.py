import random
import uuid

from schema.membership_plan import MembershipPlanCreate

PLAN_TEMPLATES = [
    {"plan_name": "Basic Monthly", "plan_type": "Individual", "base_cost": 49.99, "billing_cycle": "monthly"},
    {"plan_name": "Premium Monthly", "plan_type": "Individual", "base_cost": 89.99, "billing_cycle": "monthly"},
    {"plan_name": "Family Annual", "plan_type": "Family", "base_cost": 149.99, "billing_cycle": "yearly",
     "additional_member_costs": [80.0, 60.0, 40.0]},
    {"plan_name": "Student Monthly", "plan_type": "Individual", "base_cost": 34.99, "billing_cycle": "monthly"},
    {"plan_name": "Unlimited Yearly", "plan_type": "Individual", "base_cost": 799.99, "billing_cycle": "yearly"},
    {"plan_name": "Drop-In Pass", "plan_type": "Individual", "base_cost": 25.00, "billing_cycle": "weekly"},
]


def generate(gym_id: uuid.UUID, count: int) -> list[MembershipPlanCreate]:
    templates = random.sample(PLAN_TEMPLATES, min(count, len(PLAN_TEMPLATES)))
    return [
        MembershipPlanCreate(plan_id=uuid.uuid4(), gym_id=gym_id, **t)
        for t in templates
    ]
