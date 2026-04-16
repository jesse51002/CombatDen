import random
import uuid

from schema.membership_plan import MembershipPlanCreate

# base_cost is stored here for the prices generator to consume, not passed to MembershipPlanCreate
PLAN_TEMPLATES = [
    {
        "plan_name": "Basic Monthly",
        "plan_type": "recurring",
        "base_cost": 4999,
        "duration_amount": 1,
        "duration_unit": "month",
    },
    {
        "plan_name": "Premium Monthly",
        "plan_type": "recurring",
        "base_cost": 8999,
        "duration_amount": 1,
        "duration_unit": "month",
    },
    {
        "plan_name": "Family Monthly",
        "plan_type": "recurring",
        "base_cost": 14999,
        "duration_amount": 1,
        "duration_unit": "month",
    },
    {
        "plan_name": "Student Monthly",
        "plan_type": "recurring",
        "base_cost": 3499,
        "duration_amount": 1,
        "duration_unit": "month",
    },
    {
        "plan_name": "Unlimited Monthly",
        "plan_type": "recurring",
        "base_cost": 12999,
        "duration_amount": 1,
        "duration_unit": "month",
    },
    {
        "plan_name": "Drop-In Pass",
        "plan_type": "one_time",
        "base_cost": 2500,
        "class_count": 3,
        "duration_amount": 1,
        "duration_unit": "week",
    },
    {
        "plan_name": "Free Trial",
        "plan_type": "trial",
        "base_cost": 0,
        "class_count": 5,
        "duration_amount": 2,
        "duration_unit": "week",
    },
]


def generate(gym_id: uuid.UUID, count: int) -> tuple[list[MembershipPlanCreate], list[dict]]:
    """Returns (plans, template_dicts) so the prices generator can access base_cost."""
    templates = random.sample(PLAN_TEMPLATES, min(count, len(PLAN_TEMPLATES)))
    plans = []
    used_templates = []
    for t in templates:
        plan_fields = {k: v for k, v in t.items() if k != "base_cost"}
        plan = MembershipPlanCreate(plan_id=uuid.uuid4(), gym_id=gym_id, **plan_fields)
        plans.append(plan)
        used_templates.append({"plan_id": plan.plan_id, "base_cost": t["base_cost"]})
    return plans, used_templates
