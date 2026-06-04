"""Idempotency helpers for the API-creation path.

These let the api_creation modules look up existing rows by stable keys
(email, plan_name, discount_name) and skip the Stripe-backed POST when the
row already exists. Backend-assigned Stripe IDs can't carry a seed marker
prefix, so re-run safety comes from deterministic-identity lookups instead.

All lookups hit the `*_unfiltered` base tables (and the merged `members`
table) directly via the service-role client, bypassing the
`stripe_*_id IS NOT NULL` view filter — we need to find in-flight rows
regardless of their Stripe sync state.
"""

from __future__ import annotations

import uuid

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
            "discount_id,discount_name,discount_type,percentage_off,dollar_off,"
            "discount_mode,duration_amount,duration_unit,end_date"
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
        discount_name=row["discount_name"],
        discount_type=row["discount_type"],
        percentage_off=row.get("percentage_off"),
        dollar_off=row.get("dollar_off"),
        discount_mode=row["discount_mode"],
        duration_amount=row.get("duration_amount"),
        duration_unit=row.get("duration_unit"),
        end_date=row.get("end_date"),
    )


def find_member(
    client: Client,
    gym_id: uuid.UUID,
    email: str,
) -> dict | None:
    """Look up a member row by (gym_id, email)."""
    resp = (
        client.table("members")
        .select("*")
        .eq("gym_id", str(gym_id))
        .eq("email", email)
        .limit(1)
        .execute()
    )
    return resp.data[0] if resp.data else None


def find_member_by_id(client: Client, member_id: uuid.UUID) -> dict | None:
    resp = (
        client.table("members")
        .select("*")
        .eq("member_id", str(member_id))
        .limit(1)
        .execute()
    )
    return resp.data[0] if resp.data else None


def find_live_membership(
    client: Client,
    member_id: uuid.UUID,
    gym_id: uuid.UUID,
) -> dict | None:
    """Return the active member_memberships row for this (member, gym), if any.

    "Active" means not cancelled and not ended. The caller compares plan_id
    against the desired state to decide skip vs. reconcile.
    """
    resp = (
        client.table("member_memberships_unfiltered")
        .select(
            "item_id,stripe_item_id,plan_id,price_id,total_price,cancel_date,end_date"
        )
        .eq("member_id", str(member_id))
        .eq("gym_id", str(gym_id))
        .is_("cancel_date", "null")
        .order("created_at", desc=True)
        .execute()
    )
    if not resp.data:
        return None
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
    pk_val: str,
    expected: dict,
    actual: dict,
) -> bool:
    """UPDATE `table` with only the keys in `expected` that differ from `actual`.

    Returns True if an UPDATE was issued, False if nothing changed. Values in
    `expected` should already be stringified (UUIDs, dates) by the caller.
    """
    delta = {k: v for k, v in expected.items() if actual.get(k) != v}
    if not delta:
        return False
    client.table(table).update(delta).eq(pk_col, pk_val).execute()
    return True
