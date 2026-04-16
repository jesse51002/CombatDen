"""Start each profile's current membership via the backend.

POST /api/v1/member_memberships/ creates the row in `member_memberships` AND
a real Stripe subscription, writing the real `stripe_item_id` back to the
row before returning 201. The endpoint has no response body, so we query
the DB afterward to pick up the server-generated `item_id` and
`stripe_item_id` for downstream generators (invoices, class logs).

Idempotent: if the profile already has a live (not-cancelled, not-ended)
membership row, we either skip the POST (when plan_id + discounts match)
or cancel + recreate (reconcile path) when they don't.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from api_client import GymApiClient
from api_creation.upsert import find_live_membership
from generators.profiles import CurrentMembership, ProfilePlan
from supabase import Client


@dataclass
class CurrentMembershipRecord:
    profile: ProfilePlan
    item_id: uuid.UUID
    stripe_item_id: str | None
    plan_id: uuid.UUID
    price_id: uuid.UUID
    total_price: int


def _expected_discount_ids(
    current: CurrentMembership,
) -> list[str]:
    """The set of discount_ids we want on the resulting membership row.

    `include_linked_discount` is intentionally NOT included here — the
    backend attaches the linked tier automatically and we compare against
    what the server wrote, so the stored discount_ids column reflects the
    full set regardless of which flag drove it.
    """
    return sorted(str(d) for d in current.discount_ids)


def _existing_discount_ids(row: dict) -> list[str]:
    raw = row.get("discount_ids") or []
    return sorted(str(d) for d in raw)


def _record_from_row(profile: ProfilePlan, row: dict) -> CurrentMembershipRecord:
    return CurrentMembershipRecord(
        profile=profile,
        item_id=uuid.UUID(row["item_id"]),
        stripe_item_id=row.get("stripe_item_id"),
        plan_id=uuid.UUID(row["plan_id"]),
        price_id=uuid.UUID(row["price_id"]),
        total_price=int(row["total_price"]),
    )


def _post_current(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    profile: ProfilePlan,
    current: CurrentMembership,
) -> CurrentMembershipRecord:
    """Run the actual POST + post-query path (no idempotency check)."""
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
    # generators get the real item_id + stripe_item_id.
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
    return _record_from_row(profile, resp.data[0])


def create_current(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    profiles: list[ProfilePlan],
) -> list[CurrentMembershipRecord]:
    """Start a live membership for every profile that has a `current` plan.

    Returns one record per created (or already-existing) membership, with
    the real item_id + stripe_item_id pulled from the DB.
    """
    records: list[CurrentMembershipRecord] = []

    for profile in profiles:
        current = profile.current
        if current is None:
            continue
        assert profile.crm_user_id is not None, "create_current called before members were created"

        existing = find_live_membership(client, profile.crm_user_id, gym_id)
        if existing is not None:
            same_plan = uuid.UUID(existing["plan_id"]) == current.plan.plan_id
            same_discounts = _existing_discount_ids(existing) == _expected_discount_ids(current)
            if same_plan and same_discounts:
                # Match — reuse the existing row as-is. Skips the Stripe
                # subscription create, which is the slow part.
                records.append(_record_from_row(profile, existing))
                continue

            # Mismatch — cancel the old subscription via the backend
            # (so Stripe state stays consistent), then POST the new one.
            print(
                f"  reconciling membership for {profile.crm_user_id}: "
                f"plan_id {existing['plan_id']} -> {current.plan.plan_id}"
            )
            api.delete(
                "/api/v1/member_memberships/",
                params={
                    "item_id": existing["item_id"],
                    "crm_user_id": str(profile.crm_user_id),
                },
            )

        # Either no live row or we just cancelled one — create fresh.
        record = _post_current(api, client, gym_id, profile, current)
        records.append(record)

        # Post-start modifiers — only run when we actually POSTed. A
        # reused matching row keeps whatever freeze / cancel state the
        # previous run left it in.
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

    return records
