"""Start each member's current membership via the backend, grouped by family.

POST /api/v1/member_memberships/ creates the row in member_memberships AND a
real Stripe subscription, writing the real stripe_item_id back before
returning. The endpoint requires the member to already have a Stripe customer
+ card on file (created in api_creation/members via PUT /card), so we only
start memberships for members that were carded (i.e. not linked children).

The endpoint returns no row body, so we read the row back from
member_memberships_unfiltered to pick up the server-generated item_id +
stripe_item_id for downstream generators (invoices, pseudo-current rows).

Concurrency model — grouped by PAYING-PARENT FAMILY:
  The backend serializes billing ops per paying-parent family via a
  non-reentrant lock with a short acquire timeout, and a membership sync can
  take many seconds. So the unit of parallelism is the *family*: each family
  runs its whole sequence sequentially on one worker (start the parent, link +
  start each child, freeze, apply discounts), and ``run_concurrent`` runs
  several families at once. Families have disjoint lock keys, so they never
  contend; siblings within a family stay serial, so the lock never 409s.

Idempotent: if the member already has a live (not-cancelled, not-ended)
membership, we reuse it (same plan) or cancel + recreate (reconcile path).
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from dataclasses import dataclass

import progress
from api_client import GymApiClient
from api_creation.upsert import (
    diff_update,
    find_live_membership,
    find_member_by_id,
)
from concurrency import run_concurrent
from constants import SEED_WORKERS
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


@dataclass
class Family:
    """A paying parent (root) plus its linked children.

    A solo member is a family with no children. Every member belongs to exactly
    one family, so family lock keys are disjoint — the basis for running
    families concurrently while keeping each family's ops sequential.
    """

    root: MemberPlan
    children: list[MemberPlan]


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


def _start_one(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    member: MemberPlan,
) -> CurrentMembershipRecord | None:
    """Start one member's live membership (or reuse / reconcile an existing one).

    Returns the record, or None if the member has no current plan. A child's
    membership rides the parent's subscription, so the parent must already be
    started and the child already linked before this is called for the child.
    """
    current = member.current
    if current is None or member.member_id is None:
        return None

    existing = find_live_membership(client, member.member_id, gym_id)
    if existing is not None:
        same_plan = uuid.UUID(existing["plan_id"]) == current.plan.plan_id
        if same_plan:
            return _record_from_row(member, existing)
        # Mismatch — cancel the old subscription, then create fresh.
        progress.log(
            f"    reconciling membership for {member.member_id}: "
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

    return record


def _link_child(
    api: GymApiClient,
    child: MemberPlan,
    parent: MemberPlan,
) -> bool:
    """Link a child to its paying parent. Runs after the parent membership is
    started (the link endpoint requires the parent to have an active recurring
    subscription) and before the child's own membership is started (so the
    child's item rides the parent's subscription). Returns False if unresolved.
    """
    if child.member_id is None or parent.member_id is None:
        return False
    api.put(
        f"/api/v1/members/{child.member_id}/link",
        json={"parent_member_id": str(parent.member_id)},
    )
    return True


def _apply_freeze(client: Client, member: MemberPlan) -> None:
    """Set the account-level freeze window directly (root accounts only).

    Runs after the family's memberships are started (the backend rejects
    starting a membership on a frozen account) and before discounts are applied
    (so the discount re-sync pushes pause_collection). Children never carry a
    freeze — they inherit the parent's window through the status view.
    """
    if member.account_freeze_start is None or member.member_id is None:
        return
    existing = find_member_by_id(client, member.member_id)
    if existing is None:
        return
    assert member.account_freeze_end is not None
    expected = {
        "freeze_start_date": member.account_freeze_start.isoformat(),
        "freeze_end_date": member.account_freeze_end.isoformat(),
    }
    diff_update(client, "members", "member_id", str(member.member_id), expected, existing)


def _apply_discounts(api: GymApiClient, record: CurrentMembershipRecord) -> None:
    """Apply this membership's pre-drawn discounts (re-syncs Stripe).

    The 0-DISCOUNTS_PER_MEMBERSHIP_MAX distinct discount ids were chosen in the
    sequential build phase (generators.members._assign_discounts) and stashed on
    the CurrentMembership, so the concurrent pipeline only does I/O here. Sent in
    ONE add call so the membership re-syncs once for the whole set.
    """
    current = record.member.current
    if current is None or not current.discount_ids:
        return
    api.post(
        "/api/v1/member_memberships/discounts/add",
        json={
            "item_id": str(record.item_id),
            "member_id": str(record.member.member_id),
            "preset_ids": [str(d) for d in current.discount_ids],
            "idempotency_key": str(uuid.uuid4()),
        },
    )


def build_families(members: list[MemberPlan]) -> list[Family]:
    """Group members into paying-parent families (solos are childless families).

    Children reference their root by ``linked_primary_handle`` (the root's
    ``local_handle``); roots are the non-child members.
    """
    children_by_parent: dict[str, list[MemberPlan]] = defaultdict(list)
    roots: list[MemberPlan] = []
    for member in members:
        if member.is_linked_child:
            children_by_parent[member.linked_primary_handle].append(member)
        else:
            roots.append(member)
    return [
        Family(root=root, children=children_by_parent.get(root.local_handle, []))
        for root in roots
    ]


def process_family(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    family: Family,
) -> list[CurrentMembershipRecord]:
    """Run one family's full membership lifecycle sequentially.

    Order matters and mirrors the pre-concurrency pipeline: start the paying
    parent first (children ride its subscription), then for each child link it
    and start its membership, then freeze the account (root only), then apply
    every membership's discounts. All ops here touch a single family, so the
    per-parent lock never contends; ``run_concurrent`` runs several families at
    once.
    """
    records: list[CurrentMembershipRecord] = []

    root_record = _start_one(api, client, gym_id, family.root)
    if root_record is not None:
        records.append(root_record)

    for child in family.children:
        if not _link_child(api, child, family.root):
            continue
        child_record = _start_one(api, client, gym_id, child)
        if child_record is not None:
            records.append(child_record)

    _apply_freeze(client, family.root)

    for record in records:
        _apply_discounts(api, record)

    return records


def create_memberships(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    members: list[MemberPlan],
    workers: int = SEED_WORKERS,
) -> list[CurrentMembershipRecord]:
    """Start every live membership, concurrent across families.

    Returns one record per started (or already-existing) membership, flattened
    across all families.
    """
    families = build_families(members)
    results = run_concurrent(
        families,
        lambda family: process_family(api, client, gym_id, family),
        label="family",
        workers=workers,
    )
    return [record for family_records in results for record in family_records]
