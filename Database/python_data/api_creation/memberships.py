"""Start each member's current membership via the backend.

POST /api/v1/member_memberships/ creates the row in member_memberships AND a
real Stripe subscription, writing the real stripe_item_id back before
returning. The endpoint requires the member to already have a Stripe customer
+ card on file (created in api_creation/members via PUT /card), so we only
start memberships for members that were carded (i.e. not linked children).

The endpoint returns no row body, so we read the row back from
member_memberships_unfiltered to pick up the server-generated item_id +
stripe_item_id for downstream generators (invoices, pseudo-current rows).

Idempotent: if the member already has a live (not-cancelled, not-ended)
membership, we reuse it (same plan) or cancel + recreate (reconcile path).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from api_client import GymApiClient
from api_creation.upsert import find_live_membership
from generators.members import CurrentMembership, MemberPlan
from supabase import Client


@dataclass
class CurrentMembershipRecord:
    member: MemberPlan
    item_id: uuid.UUID
    stripe_item_id: str | None
    plan_id: uuid.UUID
    price_id: uuid.UUID
    total_price: int


def _record_from_row(member: MemberPlan, row: dict) -> CurrentMembershipRecord:
    return CurrentMembershipRecord(
        member=member,
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
    member: MemberPlan,
    current: CurrentMembership,
) -> CurrentMembershipRecord:
    payload: dict = {
        "member_id": str(member.member_id),
        "gym_id": str(gym_id),
        "plan_id": str(current.plan.plan_id),
        "price_id": str(current.plan.price_id),
        "prorate": current.prorate,
        "idempotency_key": str(uuid.uuid4()),
    }

    api.post("/api/v1/member_memberships/", json=payload)

    # No-body response — read the row back so downstream generators get the
    # real item_id + stripe_item_id.
    resp = (
        client.table("member_memberships_unfiltered")
        .select("item_id,stripe_item_id,plan_id,price_id,total_price")
        .eq("member_id", str(member.member_id))
        .eq("gym_id", str(gym_id))
        .order("created_at", desc=True)
        .limit(1)
        .execute()
    )
    if not resp.data:
        raise RuntimeError(
            f"member_memberships row not found after start for member_id={member.member_id}"
        )
    return _record_from_row(member, resp.data[0])


def create_current(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    members: list[MemberPlan],
) -> list[CurrentMembershipRecord]:
    """Start a live membership for every member that has a `current` plan.

    Skips linked children (no card → can't subscribe; covered by the parent).
    Returns one record per started (or already-existing) membership.
    """
    records: list[CurrentMembershipRecord] = []

    for member in members:
        current = member.current
        if current is None or member.is_linked_child:
            continue
        assert member.member_id is not None, "create_current called before members were created"

        existing = find_live_membership(client, member.member_id, gym_id)
        if existing is not None:
            same_plan = uuid.UUID(existing["plan_id"]) == current.plan.plan_id
            if same_plan:
                records.append(_record_from_row(member, existing))
                continue
            # Mismatch — cancel the old subscription, then create fresh.
            print(
                f"  reconciling membership for {member.member_id}: "
                f"plan_id {existing['plan_id']} -> {current.plan.plan_id}"
            )
            api.delete(
                "/api/v1/member_memberships/",
                params={
                    "item_id": existing["item_id"],
                    "member_id": str(member.member_id),
                    "idempotency_key": str(uuid.uuid4()),
                },
            )

        record = _post_current(api, client, gym_id, member, current)
        records.append(record)

        # A few members cancel right after signup (shows as cancelled in CRM).
        if current.cancel_after_start:
            api.delete(
                "/api/v1/member_memberships/",
                params={
                    "item_id": str(record.item_id),
                    "member_id": str(member.member_id),
                    "idempotency_key": str(uuid.uuid4()),
                },
            )

    return records
