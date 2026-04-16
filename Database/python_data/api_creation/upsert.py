"""Idempotency helpers for the API-creation path.

Re-running the seed script used to rebuild everything from scratch. These
helpers let the api_creation modules look up existing rows by stable keys
(email, plan_name, discount_name) and skip the Stripe-backed POST when the
row already exists.

All lookups hit the `*_unfiltered` base tables directly via the service-
role client, bypassing the `stripe_*_id IS NOT NULL` filter on the public
views — we need to be able to find in-flight rows regardless of their
Stripe sync state.
"""

from __future__ import annotations

import uuid
from typing import Any

from api_creation.discounts import DiscountRecord
from api_creation.plans import PlanRecord
from supabase import Client


def find_plan(
    client: Client,
    gym_id: uuid.UUID,
    plan_name: str,
) -> PlanRecord | None:
    """Look up a membership_plan by (gym_id, plan_name)."""
    plan_resp = (
        client.table("membership_plans_unfiltered")
        .select(
            "plan_id,plan_name,plan_type,duration_amount,duration_unit,"
            "class_count,stripe_product_id"
        )
        .eq("gym_id", str(gym_id))
        .eq("plan_name", plan_name)
        .limit(1)
        .execute()
    )
    if not plan_resp.data:
        return None
    plan_row = plan_resp.data[0]

    price_resp = (
        client.table("membership_plan_prices_unfiltered")
        .select("price_id,price,stripe_price_id,is_active")
        .eq("plan_id", plan_row["plan_id"])
        .eq("is_active", True)
        .limit(1)
        .execute()
    )
    if not price_resp.data:
        return None
    price_row = price_resp.data[0]

    return PlanRecord(
        handle="",  # filled in by the caller to match the create_all index
        plan_id=uuid.UUID(plan_row["plan_id"]),
        price_id=uuid.UUID(price_row["price_id"]),
        stripe_product_id=plan_row["stripe_product_id"],
        stripe_price_id=price_row["stripe_price_id"],
        plan_name=plan_row["plan_name"],
        plan_type=plan_row["plan_type"],
        duration_amount=plan_row.get("duration_amount"),
        duration_unit=plan_row.get("duration_unit"),
        class_count=plan_row.get("class_count"),
        base_cost=int(price_row["price"]),
    )


def find_discount(
    client: Client,
    gym_id: uuid.UUID,
    discount_name: str,
) -> DiscountRecord | None:
    """Look up a gym_discount by (gym_id, discount_name)."""
    resp = (
        client.table("gym_discounts_unfiltered")
        .select(
            "discount_id,stripe_coupon_id,discount_name,discount_type,"
            "percentage_off,dollar_off,membership_plan_id,linked_discount_num"
        )
        .eq("gym_id", str(gym_id))
        .eq("discount_name", discount_name)
        .limit(1)
        .execute()
    )
    if not resp.data:
        return None
    row = resp.data[0]
    return DiscountRecord(
        discount_id=uuid.UUID(row["discount_id"]),
        stripe_coupon_id=row.get("stripe_coupon_id"),
        discount_name=row["discount_name"],
        discount_type=row["discount_type"],
        percentage_off=row.get("percentage_off"),
        dollar_off=row.get("dollar_off"),
        membership_plan_id=(
            uuid.UUID(row["membership_plan_id"]) if row.get("membership_plan_id") else None
        ),
        linked_discount_num=row.get("linked_discount_num"),
    )


def find_profile(
    client: Client,
    gym_id: uuid.UUID,
    email: str,
) -> dict | None:
    """Look up a user_gym_profile by (gym_id, email)."""
    resp = (
        client.table("user_gym_profiles_unfiltered")
        .select("*")
        .eq("gym_id", str(gym_id))
        .eq("email", email)
        .limit(1)
        .execute()
    )
    if not resp.data:
        return None
    return resp.data[0]


def find_live_membership(
    client: Client,
    crm_user_id: uuid.UUID,
    gym_id: uuid.UUID,
) -> dict | None:
    """Return the active member_memberships row for this (user, gym), if any.

    "Active" means not cancelled and not ended. At most one such row is
    expected per (user, gym). The caller compares plan_id/discount_ids
    against the desired state to decide skip vs. reconcile.
    """
    resp = (
        client.table("member_memberships_unfiltered")
        .select(
            "item_id,stripe_item_id,plan_id,price_id,total_price,cancel_date,end_date,discount_ids"
        )
        .eq("crm_user_id", str(crm_user_id))
        .eq("gym_id", str(gym_id))
        .is_("cancel_date", "null")
        .order("created_at", desc=True)
        .execute()
    )
    if not resp.data:
        return None
    # Filter out ended (non-recurring) rows whose end_date is in the past.
    from datetime import date

    today = date.today()
    for row in resp.data:
        end = row.get("end_date")
        if end is None or date.fromisoformat(end) > today:
            return row
    return None


def diff_update(
    client: Client,
    table: str,
    pk_col: str,
    pk_val: Any,
    expected: dict,
    actual: dict,
) -> bool:
    """UPDATE `table` with only the keys in `expected` that differ from `actual`.

    Returns True if an UPDATE was issued, False if nothing changed. Values
    in `expected` are compared as-is — callers should stringify UUIDs and
    serialize dates before handing them in.
    """
    delta = {k: v for k, v in expected.items() if actual.get(k) != v}
    if not delta:
        return False
    client.table(table).update(delta).eq(pk_col, pk_val).execute()
    return True
