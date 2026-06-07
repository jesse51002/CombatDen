"""Create gym discounts (preset | custom) via the backend.

The seed creates coupon-free discount presets: `POST /api/v1/discounts/` writes
the identity row plus its active value version (coupons are computed at sync and
written onto the applied snapshot, never on the preset). Each carries a lifetime
spec — discount_mode (once | ongoing) plus, for ongoing, an end set by EITHER a
duration span (duration_amount + duration_unit ∈ day/week/month) OR an explicit
end_date — never both; neither = forever. The payload built here matches
DiscountCreateRequest in FastApiBackend (verified against Database/openapi.json).
"""

from __future__ import annotations

import random
import uuid
from dataclasses import dataclass

import progress
from api_client import GymApiClient
from supabase import Client


@dataclass
class DiscountRecord:
    discount_id: uuid.UUID
    discount_name: str
    discount_type: str
    percentage_off: float | None
    dollar_off: int | None
    discount_mode: str
    duration_amount: int | None
    duration_unit: str | None
    end_date: str | None


# The catalog the seed draws from; DISCOUNTS_PER_GYM names are sampled per gym,
# so keep this list at least that long.
DISCOUNT_NAMES = [
    "Military Discount",
    "Student Discount",
    "Early Bird",
    "Senior Discount",
    "Family Bundle",
    "Referral Bonus",
    "Loyalty Reward",
    "New Year Special",
    "Summer Promo",
    "Corporate Rate",
    "Veteran Discount",
    "Off-Peak Discount",
]


def _parse_record(resp: dict) -> DiscountRecord:
    return DiscountRecord(
        discount_id=uuid.UUID(resp["discount_id"]),
        discount_name=resp["discount_name"],
        discount_type=resp["discount_type"],
        percentage_off=resp.get("percentage_off"),
        dollar_off=resp.get("dollar_off"),
        discount_mode=resp["discount_mode"],
        duration_amount=resp.get("duration_amount"),
        duration_unit=resp.get("duration_unit"),
        end_date=resp.get("end_date"),
    )


def create_regular(
    api: GymApiClient, client: Client, gym_id: uuid.UUID, count: int
) -> list[DiscountRecord]:
    """Create standalone discount presets for a gym.

    Idempotent: skips the POST when a discount with the same name already
    exists for this gym. The random.* calls run whether or not we POST so
    downstream seeded random draws stay aligned across re-runs.
    """
    from api_creation.upsert import find_discount

    names = random.sample(DISCOUNT_NAMES, min(count, len(DISCOUNT_NAMES)))
    records: list[DiscountRecord] = []
    total = len(names)
    for n, name in enumerate(names, start=1):
        progress.item(n, total, name)
        use_pct = random.choice([True, False])
        discount_type = random.choices(["preset", "custom"], weights=[75, 25])[0]
        discount_mode = random.choice(["once", "ongoing"])
        pct_off = round(random.uniform(5, 25), 1)
        dollar_off = random.randint(500, 5000)
        # For ongoing discounts, ~half get a duration span, the rest run forever.
        duration_amount = random.randint(1, 12) if discount_mode == "ongoing" else None
        duration_unit = random.choice(["day", "week", "month"]) if discount_mode == "ongoing" else None
        if discount_mode == "ongoing" and random.random() < 0.5:
            duration_amount = None
            duration_unit = None

        existing = find_discount(client, gym_id, name)
        if existing is not None:
            records.append(existing)
            continue

        payload: dict = {
            "gym_id": str(gym_id),
            "discount_name": name,
            "discount_type": discount_type,
            "discount_mode": discount_mode,
        }
        if use_pct:
            payload["percentage_off"] = pct_off
        else:
            payload["dollar_off"] = dollar_off
        if duration_amount is not None:
            payload["duration_amount"] = duration_amount
            payload["duration_unit"] = duration_unit

        resp = api.post("/api/v1/discounts/", json=payload)
        assert resp is not None
        records.append(_parse_record(resp))
    return records
