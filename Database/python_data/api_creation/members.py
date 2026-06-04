"""Create members via the backend so every member gets a real Stripe customer.

The backend `POST /api/v1/members/` provisions a Stripe customer for every
member (the gym must have a Stripe Connect account). It accepts the full
identity + contact profile: gym_id / first_name / last_name /
(email, user_id, current_rank_id) plus the contact columns (phone, address,
emergency_contact_*, photo_url) and an optional `payment_method_id`. So per
member we:

  1. POST the member (identity + contact, plus `pm_card_visa` for non-children)
     → the backend creates the Stripe customer and, for non-children, attaches
     the default card in the same call. Capture the backend member_id.
  2. service-role UPDATE `members` to set `points_balance` only — it is
     rewards-managed and immutable to the API, so the create endpoint won't
     accept it.

Linked children POST with no card (they can hold none per the
`linked_account_no_stripe` constraint); they still get a cardless Stripe
customer, and the parent pays.

Links and account freezes are applied in later passes (after memberships are
started), since linking re-syncs the parent subscription and a frozen account
can't start a membership.

Idempotent: if a member with the same email already exists for this gym we
skip the POST (where the Stripe customer-create round-trip lives), PUT any
identity/contact columns that drifted, and diff-update points_balance direct.
"""

from __future__ import annotations

import uuid

from api_client import GymApiClient
from api_creation.upsert import diff_update, find_member, find_member_by_id
from constants import AUTH_MEMBERS_PER_GYM
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
    """Contact / profile columns the create + update endpoints accept."""
    return {
        "phone": member.phone,
        "address": member.address,
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


def create_all(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    members: list[MemberPlan],
) -> CreateAllResult:
    """POST /members for every member plan (or reuse an existing row).

    Mutates each MemberPlan in-place to set member_id. The first
    AUTH_MEMBERS_PER_GYM members get a real Supabase auth login.
    """
    had_any_new = False

    for idx, member in enumerate(members):
        # Give the first few members a real auth login (idempotent by email).
        if idx < AUTH_MEMBERS_PER_GYM and member.auth_user_id is None:
            user = auth.create_user(client, member.email)
            member.auth_user_id = uuid.UUID(user["id"])

        existing = find_member(client, gym_id, member.email)
        if existing is not None:
            member.member_id = uuid.UUID(existing["member_id"])

            # points_balance is rewards-managed (immutable to the API) and the
            # user_id backfill is identity — both go direct via service-role.
            direct = {"points_balance": member.points_balance}
            if member.auth_user_id is not None and existing.get("user_id") is None:
                direct["user_id"] = str(member.auth_user_id)
            diff_update(client, "members", "member_id", str(member.member_id), direct, existing)

            # Identity + contact drift goes through the API.
            desired = _api_member_fields(member)
            drifted = {k: v for k, v in desired.items() if existing.get(k) != v}
            if drifted:
                api.put(f"/api/v1/members/{member.member_id}", json={"data": drifted})
            continue

        had_any_new = True
        payload: dict = {
            "gym_id": str(gym_id),
            "first_name": member.first_name,
            "last_name": member.last_name,
            "email": member.email,
            **_contact_fields(member),
        }
        if member.current_rank_id is not None:
            payload["current_rank_id"] = str(member.current_rank_id)
        if member.auth_user_id is not None:
            payload["user_id"] = str(member.auth_user_id)
        # Every member is provisioned a Stripe customer at creation. Non-children
        # also get a default card in the same call; linked children hold no card
        # (the parent pays) and get the linked tier applied when linked below.
        if not member.is_linked_child:
            payload["payment_method_id"] = "pm_card_visa"

        resp = api.post("/api/v1/members/", json=payload)
        assert resp is not None, "POST /members returned no body"
        member.member_id = uuid.UUID(resp["member_id"])

        # points_balance is rewards-managed — the create endpoint won't accept
        # it, so set it directly via service-role.
        if member.points_balance:
            client.table("members").update(
                {"points_balance": member.points_balance}
            ).eq("member_id", str(member.member_id)).execute()

    return CreateAllResult(had_any_new=had_any_new)


def apply_links(api: GymApiClient, members: list[MemberPlan]) -> None:
    """Link each child to its parent via the backend.

    Runs AFTER parent memberships are started: the link endpoint requires the
    parent to have an active subscription and re-syncs it to apply the linked
    discount tier. The endpoint also clears any child card/freeze state.
    """
    by_handle: dict[str, MemberPlan] = {m.local_handle: m for m in members}
    for member in members:
        if not member.is_linked_child:
            continue
        parent = by_handle.get(member.linked_primary_handle)
        if parent is None or parent.member_id is None or member.member_id is None:
            continue
        api.put(
            f"/api/v1/members/{member.member_id}/link",
            json={"parent_member_id": str(parent.member_id)},
        )


def apply_freezes(client: Client, members: list[MemberPlan]) -> None:
    """Set account-level freeze windows on members directly.

    Runs after memberships are started (the backend rejects starting a
    membership on a frozen account). Freeze lives on the account row; the
    member_memberships_status view derives 'frozen' from it. Children never
    carry a freeze (the linked_account_no_stripe constraint forbids it —
    they inherit the parent's window through the status view).
    """
    for member in members:
        if member.is_linked_child or member.account_freeze_start is None:
            continue
        assert member.member_id is not None
        existing = find_member_by_id(client, member.member_id)
        if existing is None:
            continue
        expected = {
            "freeze_start_date": member.account_freeze_start.isoformat(),
            "freeze_end_date": member.account_freeze_end.isoformat(),
        }
        diff_update(client, "members", "member_id", str(member.member_id), expected, existing)
