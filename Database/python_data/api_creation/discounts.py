"""Create gym discounts (regular + linked tiers) via the backend."""

from __future__ import annotations

import random
import uuid
from dataclasses import dataclass

from api_client import GymApiClient
from api_creation.plans import PlanRecord


@dataclass
class DiscountRecord:
    discount_id: uuid.UUID
    stripe_coupon_id: str | None
    discount_name: str
    discount_type: str
    percentage_off: float | None
    dollar_off: int | None
    membership_plan_id: uuid.UUID | None
    linked_discount_num: int | None


DISCOUNT_NAMES = [
    "Military Discount",
    "Student Discount",
    "Early Bird",
    "Senior Discount",
    "Family Bundle",
    "Referral Bonus",
]


def _parse_record(resp: dict) -> DiscountRecord:
    return DiscountRecord(
        discount_id=uuid.UUID(resp["discount_id"]),
        stripe_coupon_id=resp.get("stripe_coupon_id"),
        discount_name=resp["discount_name"],
        discount_type=resp["discount_type"],
        percentage_off=resp.get("percentage_off"),
        dollar_off=resp.get("dollar_off"),
        membership_plan_id=(
            uuid.UUID(resp["membership_plan_id"])
            if resp.get("membership_plan_id")
            else None
        ),
        linked_discount_num=resp.get("linked_discount_num"),
    )


def create_regular(
    api: GymApiClient, gym_id: uuid.UUID, count: int
) -> list[DiscountRecord]:
    """Create standalone (non-linked) discounts for a gym."""
    names = random.sample(DISCOUNT_NAMES, min(count, len(DISCOUNT_NAMES)))
    records: list[DiscountRecord] = []
    for name in names:
        use_pct = random.choice([True, False])
        discount_type = random.choices(["preset", "custom"], weights=[75, 25])[0]
        duration = random.choice(["once", "repeating", "forever"])
        payload: dict = {
            "gym_id": str(gym_id),
            "discount_name": name,
            "discount_type": discount_type,
            "duration": duration,
        }
        if use_pct:
            payload["percentage_off"] = round(random.uniform(5, 25), 1)
        else:
            payload["dollar_off"] = random.randint(500, 5000)
        if duration == "repeating":
            payload["duration_in_months"] = random.randint(1, 12)

        resp = api.post("/api/v1/discounts/", json=payload)
        assert resp is not None
        records.append(_parse_record(resp))
    return records


def create_linked(
    api: GymApiClient,
    gym_id: uuid.UUID,
    plans: list[PlanRecord],
) -> list[DiscountRecord]:
    """Generate linked discount tiers for every recurring plan."""
    records: list[DiscountRecord] = []
    recurring_plans = [p for p in plans if p.plan_type == "recurring"]
    for plan in recurring_plans:
        num_tiers = random.randint(1, 3)
        base_dollar_off = random.randint(500, 1500)
        for i in range(1, num_tiers + 1):
            dollar_off = base_dollar_off + (i - 1) * 500
            payload = {
                "gym_id": str(gym_id),
                "discount_name": f"{plan.plan_name} - Linked Member #{i}",
                "discount_type": "linked",
                "dollar_off": dollar_off,
                "membership_plan_id": str(plan.plan_id),
                "linked_discount_num": i,
                "duration": "forever",
            }
            resp = api.post("/api/v1/discounts/", json=payload)
            assert resp is not None
            records.append(_parse_record(resp))
    return records
