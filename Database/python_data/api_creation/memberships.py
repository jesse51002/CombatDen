"""Start each profile's current membership via the backend.

POST /api/v1/member_memberships/ creates the row in `member_memberships` AND
a real Stripe subscription, writing the real `stripe_item_id` back to the
row before returning 201. The endpoint has no response body, so we query
the DB afterward to pick up the server-generated `item_id` and
`stripe_item_id` for downstream generators (invoices, class logs).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from supabase import Client

from api_client import GymApiClient
from generators.profiles import ProfilePlan


@dataclass
class CurrentMembershipRecord:
    profile: ProfilePlan
    item_id: uuid.UUID
    stripe_item_id: str | None
    plan_id: uuid.UUID
    price_id: uuid.UUID
    total_price: int


def create_current(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    profiles: list[ProfilePlan],
) -> list[CurrentMembershipRecord]:
    """Start a live membership for every profile that has a `current` plan.

    Returns one record per created membership, with the real item_id +
    stripe_item_id pulled from the DB post-create.
    """
    records: list[CurrentMembershipRecord] = []

    for profile in profiles:
        current = profile.current
        if current is None:
            continue
        assert profile.crm_user_id is not None, (
            "create_current called before members were created"
        )

        payload: dict = {
            "crm_user_id": str(profile.crm_user_id),
            "gym_id": str(gym_id),
            "plan_id": str(current.plan.plan_id),
            "price_id": str(current.plan.price_id),
            "prorate": current.prorate,
            "include_linked_discount": current.include_linked_discount,
        }
        if current.discount_ids:
            payload["discount_ids"] = [str(d) for d in current.discount_ids]

        api.post("/api/v1/member_memberships/", json=payload)

        # 201 No-body — read back the row we just created so downstream
        # generators get the real item_id + stripe_item_id. We don't filter
        # on end_date/cancel_date here because one-time and trial plans get
        # an `end_date` set on creation based on their duration. Just take
        # the most recently created row for this user/gym.
        resp = (
            client.table("member_memberships")
            .select("item_id,stripe_item_id,plan_id,price_id,total_price")
            .eq("crm_user_id", str(profile.crm_user_id))
            .eq("gym_id", str(gym_id))
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
        if not resp.data:
            raise RuntimeError(
                f"member_memberships row not found after start_membership for "
                f"crm_user_id={profile.crm_user_id}"
            )
        row = resp.data[0]
        records.append(
            CurrentMembershipRecord(
                profile=profile,
                item_id=uuid.UUID(row["item_id"]),
                stripe_item_id=row.get("stripe_item_id"),
                plan_id=uuid.UUID(row["plan_id"]),
                price_id=uuid.UUID(row["price_id"]),
                total_price=int(row["total_price"]),
            )
        )

        # Post-start modifiers
        if current.freeze_months is not None:
            api.post(
                "/api/v1/member_memberships/freeze",
                json={
                    "crm_user_id": str(profile.crm_user_id),
                    "gym_id": str(gym_id),
                    "freeze_months": current.freeze_months,
                },
            )
        if current.cancel_after_start:
            api.delete(
                "/api/v1/member_memberships/",
                params={
                    "item_id": str(records[-1].item_id),
                    "crm_user_id": str(profile.crm_user_id),
                },
            )

    # Denormalize total monthly recurring spend onto each profile.
    # Approximation: sum total_price for each profile's current membership
    # when the plan is recurring. Not exact (ignores duration_unit/amount),
    # but seed data only needs a plausible value.
    by_user: dict[uuid.UUID, int] = {}
    for rec in records:
        if rec.profile.current is None:
            continue
        if rec.profile.current.plan.plan_type != "recurring":
            continue
        assert rec.profile.crm_user_id is not None
        by_user[rec.profile.crm_user_id] = (
            by_user.get(rec.profile.crm_user_id, 0) + rec.total_price
        )

    for crm_user_id, total in by_user.items():
        client.table("user_gym_profiles").update(
            {"total_monthly_recurring_price": total}
        ).eq("crm_user_id", str(crm_user_id)).execute()

    return records
