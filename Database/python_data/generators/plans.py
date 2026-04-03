import random
import uuid

from schema.membership_plan import MembershipPlanCreate

PLAN_TEMPLATES = [
    {"plan_name": "Basic Monthly", "plan_type": "recurring", "base_cost": 49.99,
     "additional_member_discount": 10.0, "duration_amount": 1, "duration_unit": "month"},
    {"plan_name": "Premium Monthly", "plan_type": "recurring", "base_cost": 89.99,
     "additional_member_discount": 15.0, "duration_amount": 1, "duration_unit": "month"},
    {"plan_name": "Family Annual", "plan_type": "recurring", "base_cost": 149.99,
     "additional_member_discount": 20.0, "duration_amount": 1, "duration_unit": "year"},
    {"plan_name": "Student Monthly", "plan_type": "recurring", "base_cost": 34.99,
     "duration_amount": 1, "duration_unit": "month"},
    {"plan_name": "Unlimited Yearly", "plan_type": "recurring", "base_cost": 799.99,
     "additional_member_discount": 25.0, "duration_amount": 1, "duration_unit": "year"},
    {"plan_name": "Drop-In Pass", "plan_type": "one_time", "base_cost": 25.00,
     "class_count": 3, "duration_amount": 1, "duration_unit": "week"},
    {"plan_name": "Free Trial", "plan_type": "trial", "base_cost": 0,
     "class_count": 5, "duration_amount": 2, "duration_unit": "week"},
]


def generate(gym_id: uuid.UUID, count: int) -> list[MembershipPlanCreate]:
    templates = random.sample(PLAN_TEMPLATES, min(count, len(PLAN_TEMPLATES)))
    return [
        MembershipPlanCreate(plan_id=uuid.uuid4(), gym_id=gym_id, **t)
        for t in templates
    ]
