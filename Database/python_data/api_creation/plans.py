"""Create membership plans + initial prices via the backend.

POST /api/v1/membership_plans/ creates both a Stripe product and an initial
Stripe price in one call, and the response body embeds `active_price` — so we
make one API call per plan. Returns a lookup keyed by a stable local handle
("plan0", "plan1", ...) so downstream generators that need the real
plan_id/price_id/base_cost can find them.
"""

from __future__ import annotations

import random
import uuid
from dataclasses import dataclass

import progress
from api_client import GymApiClient
from supabase import Client


@dataclass
class PlanRecord:
    handle: str
    plan_id: uuid.UUID
    price_id: uuid.UUID
    stripe_product_id: str
    stripe_price_id: str
    plan_name: str
    plan_type: str
    duration_amount: int | None
    duration_unit: str | None
    class_count: int | None
    base_cost: int


# plan_type / duration_unit values mirror the backend PlanType / DurationUnit
# enums (membership_plan.py): trial | one_time | recurring, week | month | year.
PLAN_TEMPLATES = [
    {"plan_name": "Basic Monthly", "plan_type": "recurring", "price": 4999, "duration_amount": 1, "duration_unit": "month"},
    {"plan_name": "Premium Monthly", "plan_type": "recurring", "price": 8999, "duration_amount": 1, "duration_unit": "month"},
    {"plan_name": "Family Monthly", "plan_type": "recurring", "price": 14999, "duration_amount": 1, "duration_unit": "month"},
    {"plan_name": "Student Monthly", "plan_type": "recurring", "price": 3499, "duration_amount": 1, "duration_unit": "month"},
    {"plan_name": "Unlimited Monthly", "plan_type": "recurring", "price": 12999, "duration_amount": 1, "duration_unit": "month"},
    {"plan_name": "Drop-In Pass", "plan_type": "one_time", "price": 2500, "class_count": 3, "duration_amount": 1, "duration_unit": "week"},
    {"plan_name": "Free Trial", "plan_type": "trial", "price": 0, "class_count": 5, "duration_amount": 2, "duration_unit": "week"},
]


def create_all(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    count: int,
) -> list[PlanRecord]:
    """Create up to `count` plans for one gym via the backend API.

    Returns one PlanRecord per plan, in the order created. Idempotent: if a
    plan with the template's name already exists for this gym we reuse it
    instead of POSTing again (which would call Stripe).
    """
    # Import here to avoid a circular import (upsert imports PlanRecord).
    from api_creation.upsert import find_plan

    selected = random.sample(PLAN_TEMPLATES, min(count, len(PLAN_TEMPLATES)))
    records: list[PlanRecord] = []
    total = len(selected)
    for idx, tmpl in enumerate(selected):
        progress.item(idx + 1, total, tmpl["plan_name"])
        existing = find_plan(client, gym_id, tmpl["plan_name"])
        if existing is not None:
            existing.handle = f"plan{idx}"
            records.append(existing)
            continue

        payload: dict = {
            "gym_id": str(gym_id),
            "plan_name": tmpl["plan_name"],
            "plan_type": tmpl["plan_type"],
            "price": tmpl["price"],
            "is_public": True,
        }
        if "duration_amount" in tmpl:
            payload["duration_amount"] = tmpl["duration_amount"]
            payload["duration_unit"] = tmpl["duration_unit"]
        if "class_count" in tmpl:
            payload["class_count"] = tmpl["class_count"]

        resp = api.post("/api/v1/membership_plans/", json=payload)
        assert resp is not None, "membership_plans create returned no body"
        active_price = resp.get("active_price")
        assert active_price is not None, (
            "membership_plans create response missing active_price — "
            "plan create should always return an initial price"
        )
        records.append(
            PlanRecord(
                handle=f"plan{idx}",
                plan_id=uuid.UUID(resp["plan_id"]),
                price_id=uuid.UUID(active_price["price_id"]),
                stripe_product_id=resp["stripe_product_id"],
                stripe_price_id=active_price["stripe_price_id"],
                plan_name=resp["plan_name"],
                plan_type=resp["plan_type"],
                duration_amount=resp.get("duration_amount"),
                duration_unit=resp.get("duration_unit"),
                class_count=resp.get("class_count"),
                base_cost=tmpl["price"],
            )
        )
    return records
