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
"""

from __future__ import annotations

import uuid

from supabase import Client

from api_client import GymApiClient
from generators.profiles import ProfilePlan


def create_all(
    api: GymApiClient,
    client: Client,
    gym_id: uuid.UUID,
    profiles: list[ProfilePlan],
) -> None:
    """POST /members/ for every profile. Mutates ProfilePlan in-place to set crm_user_id."""
    for profile in profiles:
        demo = profile.demographics
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

    # Apply demographic/photo/points fields that aren't settable via the API,
    # in a single update per profile. Kept out of the loop above to keep the
    # API call path and direct-DB path clearly separated.
    #
    # Account freezes are NOT applied here — they'd block the subsequent
    # `memberships.create_current` API call ("Cannot start membership:
    # account is frozen"). Freezes are applied via `apply_freezes()` after
    # current memberships have been started.
    for profile in profiles:
        assert profile.crm_user_id is not None
        update: dict = {
            "photo_url": profile.demographics.photo_url,
            "points_balance": profile.demographics.points_balance,
        }
        if profile.demographics.auth_user_id is not None:
            update["user_id"] = str(profile.demographics.auth_user_id)
        client.table("user_gym_profiles").update(update).eq(
            "crm_user_id", str(profile.crm_user_id)
        ).execute()


def apply_freezes(
    client: Client,
    profiles: list[ProfilePlan],
) -> None:
    """Third pass: apply account-level freeze windows.

    Runs after current memberships have been started so the backend doesn't
    reject `POST /member_memberships` with "account is frozen".
    """
    for profile in profiles:
        if profile.account_freeze_start is None:
            continue
        assert profile.crm_user_id is not None
        client.table("user_gym_profiles").update(
            {
                "freeze_start_date": profile.account_freeze_start.isoformat(),
                "freeze_end_date": profile.account_freeze_end.isoformat(),
            }
        ).eq("crm_user_id", str(profile.crm_user_id)).execute()


def apply_links(
    client: Client,
    profiles: list[ProfilePlan],
) -> None:
    """Second pass: set account_linked_to_id + linked_discount_id on children.

    Done after `create_all` because children reference their parent's real
    crm_user_id, which only exists after both rows have been through the API.
    """
    by_handle: dict[str, ProfilePlan] = {p.local_handle: p for p in profiles}
    for profile in profiles:
        if profile.linked_primary_handle is None:
            continue
        parent = by_handle.get(profile.linked_primary_handle)
        if parent is None or parent.crm_user_id is None:
            continue
        update: dict = {"account_linked_to_id": str(parent.crm_user_id)}
        if profile.linked_discount_id is not None:
            update["linked_discount_id"] = str(profile.linked_discount_id)
        client.table("user_gym_profiles").update(update).eq(
            "crm_user_id", str(profile.crm_user_id)
        ).execute()
