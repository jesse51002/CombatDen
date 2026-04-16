"""Create members via POST /api/v1/members/.

Every profile goes through the API so every `user_gym_profiles` row ends up
with a real `cus_*` stripe_customer_id. After the backend returns its
generated crm_user_id, we run a small direct-DB UPDATE to apply fields the
create endpoint doesn't accept:
  - user_id (linked Supabase auth account)
  - points_balance, photo_url
  - freeze_start_date / freeze_end_date
  - account_linked_to_id / linked_discount_id

(These are all stable stored columns on `user_gym_profiles`, not Stripe-
managed, so writing them directly via service-role is safe.)

Idempotent: if a profile with the same email already exists for this gym
we skip the POST entirely (this is where the Stripe customer create /
payment-method attach round-trips live) and diff-update any demographic
columns that drifted.
"""

from __future__ import annotations

import uuid

from api_client import GymApiClient
from api_creation.upsert import diff_update, find_profile
from generators.profiles import ProfilePlan
from supabase import Client


class CreateAllResult:
    """Return value of create_all.

    `had_any_new` tells the caller whether any profile was freshly created
    via the API this run. The direct-DB history generators in main.py use
    it to decide whether to run at all — they'd otherwise duplicate rows
    or trip trigger-level constraints on re-runs.
    """

    def __init__(self, had_any_new: bool) -> None:
        self.had_any_new = had_any_new


def _expected_core_columns(profile: ProfilePlan) -> dict:
    """Columns we control on user_gym_profiles_unfiltered.

    Used both for `diff_update` on existing rows and for the post-create
    update pass on newly-POSTed rows. `crm_user_id`, `gym_id`,
    `stripe_customer_id`, and `user_id` are deliberately NOT in here —
    those are either PKs, set at creation time, or governed by triggers.
    """
    demo = profile.demographics
    return {
        "first_name": demo.first_name,
        "last_name": demo.last_name,
        "email": demo.email,
        "phone": demo.phone,
        "address": demo.address,
        "emergency_contact_name": demo.emergency_contact_name,
        "emergency_contact_phone": demo.emergency_contact_phone,
        "emergency_contact_email": demo.emergency_contact_email,
        "photo_url": demo.photo_url,
        "points_balance": demo.points_balance,
    }


def create_all(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    profiles: list[ProfilePlan],
) -> CreateAllResult:
    """POST /members/ for every profile (or reuse an existing row).

    Mutates ProfilePlan in-place to set crm_user_id.
    """
    had_any_new = False

    for profile in profiles:
        demo = profile.demographics
        existing = find_profile(client, gym_id, demo.email)
        if existing is not None:
            profile.crm_user_id = uuid.UUID(existing["crm_user_id"])
            # Diff-update anything that drifted. user_id is governed by an
            # immutability trigger so we only try to set it when the row
            # has no user_id yet.
            expected = _expected_core_columns(profile)
            if demo.auth_user_id is not None and existing.get("user_id") is None:
                expected["user_id"] = str(demo.auth_user_id)
            diff_update(
                client,
                "user_gym_profiles_unfiltered",
                "crm_user_id",
                str(profile.crm_user_id),
                expected,
                existing,
            )
            continue

        # No row for this email yet — run the full create path.
        had_any_new = True
        payload = {
            "gym_id": str(gym_id),
            "first_name": demo.first_name,
            "last_name": demo.last_name,
            "phone": demo.phone,
            "email": demo.email,
            "address": demo.address,
            "emergency_contact_name": demo.emergency_contact_name,
            "emergency_contact_phone": demo.emergency_contact_phone,
            "emergency_contact_email": demo.emergency_contact_email,
        }
        # Linked child accounts can't own card fields (linked_account_no_stripe
        # CHECK constraint). For everyone else, attach Stripe's test-mode
        # magic token so one-time invoice charges (Drop-In Pass, trials)
        # have a default payment method to settle against.
        if profile.linked_primary_handle is None:
            payload["payment_method_id"] = "pm_card_visa"
        resp = api.post("/api/v1/members/", json=payload)
        assert resp is not None, "POST /members returned no body"
        profile.crm_user_id = uuid.UUID(resp["crm_user_id"])

        # Apply demographic/photo/points fields that aren't settable via the
        # API, in a single update per newly-created profile. Account freezes
        # are NOT applied here — they'd block the subsequent
        # `memberships.create_current` API call ("Cannot start membership:
        # account is frozen"). Freezes go through `apply_freezes()` after
        # current memberships have been started.
        update: dict = {
            "photo_url": demo.photo_url,
            "points_balance": demo.points_balance,
        }
        if demo.auth_user_id is not None:
            update["user_id"] = str(demo.auth_user_id)
        client.table("user_gym_profiles").update(update).eq(
            "crm_user_id", str(profile.crm_user_id)
        ).execute()

    return CreateAllResult(had_any_new=had_any_new)


def apply_freezes(
    client: Client,
    profiles: list[ProfilePlan],
) -> None:
    """Third pass: apply account-level freeze windows.

    Runs after current memberships have been started so the backend doesn't
    reject `POST /member_memberships` with "account is frozen". Uses
    diff_update so re-runs with identical freeze windows are no-ops.
    """
    for profile in profiles:
        if profile.account_freeze_start is None:
            continue
        assert profile.crm_user_id is not None
        expected = {
            "freeze_start_date": profile.account_freeze_start.isoformat(),
            "freeze_end_date": profile.account_freeze_end.isoformat(),
        }
        existing = find_profile_by_id(client, profile.crm_user_id)
        if existing is None:
            continue
        diff_update(
            client,
            "user_gym_profiles_unfiltered",
            "crm_user_id",
            str(profile.crm_user_id),
            expected,
            existing,
        )


def apply_links(
    client: Client,
    profiles: list[ProfilePlan],
) -> None:
    """Second pass: set account_linked_to_id + linked_discount_id on children.

    Done after `create_all` because children reference their parent's real
    crm_user_id, which only exists after both rows have been through the API.
    Uses diff_update so re-runs with identical links are no-ops.
    """
    by_handle: dict[str, ProfilePlan] = {p.local_handle: p for p in profiles}
    for profile in profiles:
        if profile.linked_primary_handle is None:
            continue
        parent = by_handle.get(profile.linked_primary_handle)
        if parent is None or parent.crm_user_id is None:
            continue
        expected: dict = {"account_linked_to_id": str(parent.crm_user_id)}
        if profile.linked_discount_id is not None:
            expected["linked_discount_id"] = str(profile.linked_discount_id)
        existing = find_profile_by_id(client, profile.crm_user_id)
        if existing is None:
            continue
        diff_update(
            client,
            "user_gym_profiles_unfiltered",
            "crm_user_id",
            str(profile.crm_user_id),
            expected,
            existing,
        )


def find_profile_by_id(client: Client, crm_user_id: uuid.UUID) -> dict | None:
    resp = (
        client.table("user_gym_profiles_unfiltered")
        .select("*")
        .eq("crm_user_id", str(crm_user_id))
        .limit(1)
        .execute()
    )
    return resp.data[0] if resp.data else None
