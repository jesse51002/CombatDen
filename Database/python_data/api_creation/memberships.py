"""Start each family's current memberships via the backend, grouped by PAYER.

POST /api/v1/member_memberships/ starts a set of memberships under ONE payer:
the body carries the payer plus a list of per-member items ({member_id,
price_id, discount_ids, custom_discounts}), and each membership's discounts land
before the first charge. Each item creates a row in member_memberships AND its
Stripe subscription item (on the payer's customer), writing the real
stripe_item_id back. A family makes one request for the PARENT-PAID group (the
root plus any parent-paid children) and one more PER SELF-PAYING child (payer =
that child) — so a family with self-payers makes several requests. Every payer
must have a Stripe customer + card on file (created in api_creation/members),
and every non-payer item member must already be LINKED to the payer (the start
never links), so we keep the link step and only ever start carded payers.

The endpoint returns a per-membership breakdown ({member_id, plan_id, status,
item_id, error}) but no full row body, so for each created membership we read
the row back from member_memberships_unfiltered to pick up the server-generated
stripe_item_id / price_id / total_price for downstream generators (invoices,
pseudo-current rows).

A failed charge group comes back as ``failed`` RESULTS, not an HTTP error, so we
check every result's status and hard-fail loudly with the full breakdown if any
membership did not come back ``created``.

Concurrency model — grouped by FAMILY:
  The backend serializes billing ops per PAYER via a non-reentrant lock with a
  short acquire timeout, and a membership start can take many seconds. So the
  unit of parallelism is the *family*: each family runs its whole sequence
  sequentially on one worker (link each child, start the parent-paid group, then
  each self-paying child, freeze, cancel any cancel-at-start memberships), and
  ``run_concurrent`` runs several families at once. Every payer in a family is a
  distinct member, so the family's own requests never contend each other, and
  families are disjoint, so different families never contend — no 409s.

Idempotent: if a member already has a live (not-cancelled, not-ended)
membership, we reuse it (same plan) or cancel + recreate (reconcile path) before
building the family's start request.
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
from generators.members import MemberPlan
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


def _resolve_member(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    member: MemberPlan,
) -> tuple[MemberPlan | None, CurrentMembershipRecord | None]:
    """Decide what to do with one member's desired membership before the start.

    Returns ``(to_start, existing_record)`` where exactly one is non-None (or
    both None if the member has no current plan):

    - ``(member, None)`` — needs a fresh start: include it in the family's start
      request.
    - ``(None, record)`` — already live on the same plan: reuse it, no API call.

    On a plan mismatch we cancel the old subscription here (reconcile path), then
    return the member to be started fresh.
    """
    current = member.current
    if current is None or member.member_id is None:
        return None, None

    existing = find_live_membership(client, member.member_id, gym_id)
    if existing is not None:
        same_plan = uuid.UUID(existing["plan_id"]) == current.plan.plan_id
        if same_plan:
            return None, _record_from_row(member, existing)
        # Mismatch — cancel the old subscription, then start fresh below.
        progress.log(
            f"    reconciling membership for {member.member_id}: "
            f"plan_id {existing['plan_id']} -> {current.plan.plan_id}"
        )
        api.delete(
            "/api/v1/member_memberships/",
            json={
                "item_ids": [str(existing["item_id"])],
                "member_id": str(member.member_id),
                "idempotency_key": str(uuid.uuid4()),
            },
        )

    return member, None


def _start_item(member: MemberPlan) -> dict:
    """One ``memberships`` item in the family start request.

    The plan is derived server-side from ``price_id`` (a price belongs to exactly
    one plan), so the item carries no plan_id. ``discount_ids`` are the pre-drawn
    preset / linked discounts chosen in the sequential build phase
    (generators.members._assign_discounts) and applied before the first charge.
    ``custom_discounts`` carries at most one inline DiscountValue dict
    (generators.members._assign_custom_discounts) — the backend mints a one-shot
    ``custom`` discount entry and applies it before the first charge alongside any
    preset discounts. Omitted entirely when None so the wire payload stays clean.
    """
    current = member.current
    assert current is not None and member.member_id is not None
    item: dict = {
        "member_id": str(member.member_id),
        "price_id": str(current.plan.price_id),
        # One_time / trial packs STACK via quantity (1-3 for class packs, 1
        # otherwise); recurring is always 1. The backend bills ONE row of N
        # units, not N rows.
        "quantity": max(1, current.count),
        "discount_ids": [str(d) for d in current.discount_ids],
    }
    if current.custom_discount is not None:
        item["custom_discounts"] = [current.custom_discount]
    return item


def _read_back_record(
    client: Client,
    gym_id: uuid.UUID,
    member: MemberPlan,
    item_id: uuid.UUID,
) -> CurrentMembershipRecord:
    """Read a just-started membership row back to build its downstream record.

    The start breakdown returns item_id + plan_id but not the stripe_item_id /
    price_id / total_price the invoice + pseudo-current generators need, so we
    fetch the row by its server-generated ``item_id``.
    """
    resp = (
        client.table("member_memberships_unfiltered")
        .select("item_id,stripe_item_id,plan_id,price_id,total_price")
        .eq("item_id", str(item_id))
        .eq("gym_id", str(gym_id))
        .limit(1)
        .execute()
    )
    if not resp.data:
        raise RuntimeError(
            "member_memberships row not found after start for "
            f"item_id={item_id} member_id={member.member_id}"
        )
    return _record_from_row(member, resp.data[0])


def _start_family(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    payer: MemberPlan,
    to_start: list[MemberPlan],
) -> list[CurrentMembershipRecord]:
    """Start every ``to_start`` member's membership in ONE request, validate, read back.

    Sends a single POST covering the whole family (payer's own items included),
    hard-fails loudly if any result is not ``created`` (a failed charge group
    surfaces as failed results, not an HTTP error), then reads each created row
    back and applies any cancel-at-start cancellations.
    """
    if not to_start:
        return []

    by_member = {str(m.member_id): m for m in to_start}
    # One-time / trial packs may be STACKED: a member's CurrentMembership.count
    # (1-3 for class packs, 1 otherwise) rides as the item's `quantity`, so the
    # start creates ONE membership billing that many units (not N rows).
    # Recurring stays quantity 1.
    items = [_start_item(m) for m in to_start]
    payload: dict = {
        "payer_member_id": str(payer.member_id),
        "gym_id": str(gym_id),
        "idempotency_key": str(uuid.uuid4()),
        "memberships": items,
    }
    response = api.post("/api/v1/member_memberships/", json=payload)
    results = (response or {}).get("results", [])

    failed = [r for r in results if r.get("status") != "created"]
    if failed:
        raise RuntimeError(
            "membership start returned failed results for "
            f"payer_member_id={payer.member_id} gym_id={gym_id}: {results}"
        )
    if len(results) != len(items):
        raise RuntimeError(
            "membership start result count mismatch for "
            f"payer_member_id={payer.member_id}: sent {len(items)}, "
            f"got {len(results)}: {results}"
        )

    records: list[CurrentMembershipRecord] = []
    for result in results:
        member = by_member[result["member_id"]]
        item_id = uuid.UUID(result["item_id"])
        records.append(_read_back_record(client, gym_id, member, item_id))
        # A few members cancel right after signup (shows as cancelled in CRM).
        if member.current is not None and member.current.cancel_after_start:
            api.delete(
                "/api/v1/member_memberships/",
                json={
                    "item_ids": [str(item_id)],
                    "member_id": str(member.member_id),
                    "idempotency_key": str(uuid.uuid4()),
                },
            )
    return records


def _link_child(
    api: GymApiClient,
    child: MemberPlan,
    parent: MemberPlan,
) -> bool:
    """Authorize the parent as a payer for the child. Runs BEFORE the family's
    start request (the start never authorizes, and a child's membership rides
    the parent's subscription, so the authorization must already exist). The
    link endpoint records the parent's signature on the gym's default
    authorized-payer waiver + the authorization (member_authorized_payers) in
    one transaction; it does NOT require the parent to be billing yet. Returns
    False if unresolved.
    """
    if child.member_id is None or parent.member_id is None:
        return False
    api.put(
        f"/api/v1/members/{child.member_id}/link",
        json={
            "payer_member_id": str(parent.member_id),
            "signer_name": f"{parent.first_name} {parent.last_name}",
            "consent_acknowledged": True,
        },
    )
    return True


def _apply_freeze(client: Client, member: MemberPlan) -> None:
    """Set the account-level freeze window directly (root accounts only).

    Runs after the family's memberships are started (the backend rejects
    starting a membership on a frozen account). This is a direct DB write of the
    freeze window only — it does NOT push pause_collection to Stripe (the
    recurring sync leaves pause_collection to the explicit freeze/unfreeze
    action), so the window only drives the CRM's derived `frozen` status via
    the member_memberships_status view. Children never carry a freeze — they
    inherit the parent's window through the status view.
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
    """Run one family's membership creation sequentially.

    Order matters: link each child to the parent first (the start never links).
    Then start by PAYER — the parent-paid group in one request (the root's own
    membership plus every parent-paid child's, riding the root's subscription),
    then each self-paying child in its own request (own subscription) — each item
    carrying its pre-drawn discounts, applied before the first charge. Then
    freeze the account (root only). Members already live on the same plan are
    reused without an API call; a plan mismatch is reconciled (cancel old) before
    the start. Every payer in the family is a distinct member, so the family's
    requests never contend; ``run_concurrent`` runs several families at once.
    """
    # Children must be linked before the start (the start never links, and the
    # link endpoint requires the payer to be resolvable as their parent).
    linked_children = [
        child for child in family.children if _link_child(api, child, family.root)
    ]

    records: list[CurrentMembershipRecord] = []
    # Memberships split by PAYER: the parent-paid group (root + parent-paid
    # children) bill on the root's subscription in ONE request; each self-paying
    # child bills on their OWN subscription in their own request.
    parent_to_start: list[MemberPlan] = []
    self_pay_to_start: list[MemberPlan] = []
    for member in [family.root, *linked_children]:
        member_to_start, existing = _resolve_member(api, client, gym_id, member)
        if existing is not None:
            records.append(existing)
        if member_to_start is not None:
            if member_to_start.self_pays:
                self_pay_to_start.append(member_to_start)
            else:
                parent_to_start.append(member_to_start)

    # Parent-paid group → payer is the root (covers the root's own membership
    # plus every parent-paid child). Skipped when empty (e.g. all reused).
    records.extend(
        _start_family(api, client, gym_id, family.root, parent_to_start)
    )
    # Each self-paying child → its own request, payer = the child itself
    # (member_id == payer, so the start's self-or-parent check passes trivially);
    # billed on the child's own card + own subscription.
    for child in self_pay_to_start:
        records.extend(_start_family(api, client, gym_id, child, [child]))

    _apply_freeze(client, family.root)

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
