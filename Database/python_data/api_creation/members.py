"""Create members via the backend so every member gets a real Stripe customer.

The backend `POST /api/v1/members/` provisions a Stripe customer for every
member (the gym must have a Stripe Connect account). It accepts the full
identity + contact profile: gym_id / first_name / last_name /
(email, current_rank_id) plus the contact columns (phone, address,
date_of_birth, emergency_contact_*, photo_url) and an optional
`payment_method_id`. There is no `user_id` FK — a member's self-access is a
verified Supabase auth account
whose email matches this row's `email` (compared lowercase), so a member who
gets a real login (the first `AUTH_MEMBERS_PER_GYM`) simply needs an auth
user created with that SAME email; nothing is stamped onto the member row for
it. So per member we:

  1. POST the member (identity + contact, plus `pm_card_visa` for non-children)
     → the backend creates the Stripe customer and, for non-children, attaches
     the default card in the same call. Capture the backend member_id.
  2. service-role UPDATE `members` to set the columns the create endpoint
     won't accept: `points_balance` (rewards-managed, immutable to the API)
     and `current_sub_index` (the member's leaf within its main rank — written
     only by the audited ranks endpoints, so POST /members leaves it NULL).
     The seed persists the ladder's pick here so members spread across
     sub-ranks; a NULL sub-index (a 'none' gym or a subless rank) needs no
     write. This is the same service-role bypass bootstrap/ranks.py uses to
     write gym_ranks / gyms.sub_rank_type.

Linked children POST with a card only when they SELF-PAY (own subscription);
a parent-paid child POSTs cardless (they still get a Stripe customer, but the
parent's card pays). Either way the child is linked under the parent in the
family pipeline.

Member creation has no per-family billing lock, so it runs concurrently across
members (each member is independent). Linking children to parents and account
freezes happen later, inside the family-grouped membership pipeline
(api_creation/memberships.py), since linking re-syncs the parent subscription
and a frozen account can't start a membership.

Idempotent: if a member with the same email already exists for this gym we
skip the POST (where the Stripe customer-create round-trip lives), PUT any
identity/contact columns that drifted, and diff-update points_balance direct.
"""

from __future__ import annotations

import uuid

from api_client import GymApiClient
from api_creation.upsert import diff_update, find_member
from concurrency import run_concurrent
from constants import AUTH_MEMBERS_PER_GYM, SEED_WORKERS
from generators import auth
from generators.members import MemberPlan
from supabase import Client


class CreateAllResult:
    """`had_any_new` tells the caller whether any member was freshly created
    this run. The direct-DB history generators use it to avoid duplicating
    rows (and tripping the membership chronological/overlap triggers) on
    pure re-runs.
    """

    def __init__(self, had_any_new: bool) -> None:
        self.had_any_new = had_any_new


def _contact_fields(member: MemberPlan) -> dict:
    """Contact / profile columns the create + update endpoints accept.

    Every value is JSON-native. ``date_of_birth`` is stringified here rather
    than passed as a `date`: this dict is both the POST body (httpx's `json=`
    cannot encode a `date`) AND the expected-vs-actual side of the re-run
    drift diff, whose actual comes back from PostgREST as an ISO string — so a
    `date` object would look drifted on every single re-run and re-PUT the
    whole roster.
    """
    return {
        "phone": member.phone,
        "address": member.address,
        "date_of_birth": member.date_of_birth.isoformat(),
        "emergency_contact_name": member.emergency_contact_name,
        "emergency_contact_phone": member.emergency_contact_phone,
        "emergency_contact_email": member.emergency_contact_email,
        "photo_url": member.photo_url,
    }


def _api_member_fields(member: MemberPlan) -> dict:
    """Identity + contact columns the create / update endpoints accept.

    Excludes points_balance (rewards-managed, immutable to the API) and the
    Stripe / freeze / linkage columns (their own endpoints / passes).
    """
    return {
        "first_name": member.first_name,
        "last_name": member.last_name,
        "email": member.email,
        **_contact_fields(member),
    }


def _create_one(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    idx: int,
    member: MemberPlan,
) -> bool:
    """Create (or reconcile) one member. Returns True iff freshly created.

    Mutates the MemberPlan in-place to set member_id. ``idx`` is the member's
    position so the first AUTH_MEMBERS_PER_GYM get a real Supabase auth login.
    Safe to run concurrently across members — each member is independent (no
    per-family billing lock is taken here).
    """
    # Give the first few members a real auth login (idempotent by email).
    # There is no user_id to backfill — the auth user's email already matches
    # this member's email, which IS the access link.
    if idx < AUTH_MEMBERS_PER_GYM and member.auth_user_id is None:
        user = auth.create_user(client, member.email)
        member.auth_user_id = uuid.UUID(user["id"])

    existing = find_member(client, gym_id, member.email)
    if existing is not None:
        member.member_id = uuid.UUID(existing["member_id"])

        # points_balance is rewards-managed (immutable to the API), and
        # current_sub_index is written only by the audited ranks endpoints
        # (the create/update API refuses it) — both go direct via
        # service-role. diff_update no-ops any field already matching (so a
        # NULL-vs-NULL sub-index on a 'none' gym writes nothing).
        direct: dict = {
            "points_balance": member.points_balance,
            "current_sub_index": member.current_sub_index,
        }
        diff_update(client, "members", "member_id", str(member.member_id), direct, existing)

        # Identity + contact drift goes through the API.
        desired = _api_member_fields(member)
        drifted = {k: v for k, v in desired.items() if existing.get(k) != v}
        if drifted:
            api.put(f"/api/v1/members/{member.member_id}", json={"data": drifted})
        return False

    payload: dict = {
        "gym_id": str(gym_id),
        "first_name": member.first_name,
        "last_name": member.last_name,
        "email": member.email,
        **_contact_fields(member),
    }
    if member.current_rank_id is not None:
        payload["current_rank_id"] = str(member.current_rank_id)
    # Every member is provisioned a Stripe customer at creation. A member also
    # gets a default card when they will be billed directly: a root/solo (not a
    # linked child) OR a SELF-PAYING linked child (own card, own subscription).
    # A parent-paid linked child holds no card — the parent pays.
    if not member.is_linked_child or member.self_pays:
        payload["payment_method_id"] = "pm_card_visa"

    resp = api.post("/api/v1/members/", json=payload)
    assert resp is not None, "POST /members returned no body"
    member.member_id = uuid.UUID(resp["member_id"])

    # Two columns the create endpoint won't accept, set directly via
    # service-role (the same bypass bootstrap/ranks.py uses for gym_ranks /
    # gyms.sub_rank_type):
    #   - points_balance — rewards-managed, immutable to the API.
    #   - current_sub_index — the leaf the gym's ladder picked; written only by
    #     the audited ranks endpoints, so POST /members leaves it NULL. Persist
    #     it so members spread across sub-ranks instead of all collapsing onto
    #     the base leaf. NULL (a 'none' gym / subless rank) needs no write — the
    #     freshly-created row is already NULL.
    direct: dict = {}
    if member.points_balance:
        direct["points_balance"] = member.points_balance
    if member.current_sub_index is not None:
        direct["current_sub_index"] = member.current_sub_index
    if direct:
        client.table("members").update(direct).eq(
            "member_id", str(member.member_id)
        ).execute()

    return True


def create_all(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    members: list[MemberPlan],
    workers: int = SEED_WORKERS,
) -> CreateAllResult:
    """POST /members for every member plan (or reuse an existing row).

    Mutates each MemberPlan in-place to set member_id. Runs concurrently across
    members (no per-family lock is taken at creation). The first
    AUTH_MEMBERS_PER_GYM members get a real Supabase auth login.
    """
    created_flags = run_concurrent(
        list(enumerate(members)),
        lambda pair: _create_one(api, client, gym_id, pair[0], pair[1]),
        label="member",
        workers=workers,
    )
    return CreateAllResult(had_any_new=any(created_flags))
