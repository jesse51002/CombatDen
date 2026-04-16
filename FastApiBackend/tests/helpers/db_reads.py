"""Tiny read-only query helpers for integration tests.

Keeps the DB-lookup boilerplate out of individual test files when
the same lookup is needed in several places. All helpers here are
read-only — mutating helpers live in ``data_factory.py``.
"""

from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import text

from src.shared.database import DirectDatabasePool


@dataclass(frozen=True)
class ProfileStripeIds:
    """Stripe identifiers pulled from a user's gym profile row."""

    stripe_customer_id: str
    stripe_sub_id_month: str | None


async def get_profile_stripe_ids(
    db_pool: DirectDatabasePool,
    crm_user_id: UUID,
    gym_id: UUID,
) -> ProfileStripeIds:
    """Fetch a member's Stripe customer + recurring subscription id.

    Reads from the filtered ``user_gym_profiles`` view (which already
    requires ``stripe_customer_id IS NOT NULL``), so callers can
    assume the customer id is set. ``stripe_sub_id_month`` is None
    when the member has no active recurring sub.
    """
    sql = (
        "SELECT stripe_customer_id, stripe_sub_id_month "
        "FROM user_gym_profiles "
        "WHERE crm_user_id = :crm_user_id AND gym_id = :gym_id"
    )
    async with db_pool.session() as session:
        result = await session.execute(
            text(sql),
            {"crm_user_id": str(crm_user_id), "gym_id": str(gym_id)},
        )
        row = result.mappings().fetchone()
    if row is None:
        raise AssertionError(
            f"No user_gym_profiles row for crm_user_id={crm_user_id} gym_id={gym_id}"
        )
    return ProfileStripeIds(
        stripe_customer_id=row["stripe_customer_id"],
        stripe_sub_id_month=row["stripe_sub_id_month"],
    )


async def get_active_membership_item_id(
    db_pool: DirectDatabasePool,
    crm_user_id: UUID,
    gym_id: UUID,
) -> UUID:
    """Return the active recurring membership ``item_id`` for a member.

    Reads via the filtered ``member_memberships`` view (synced rows
    only) and scopes to the member/gym pair. Fails loudly if more
    than one active row is found — the caller should reshape their
    test if they need to pick a specific one.
    """
    sql = (
        "SELECT item_id "
        "FROM member_memberships "
        "WHERE crm_user_id = :crm_user_id "
        "  AND gym_id = :gym_id "
        "  AND cancel_date IS NULL "
        "  AND end_date IS NULL"
    )
    async with db_pool.session() as session:
        result = await session.execute(
            text(sql),
            {"crm_user_id": str(crm_user_id), "gym_id": str(gym_id)},
        )
        rows = result.mappings().fetchall()
    if not rows:
        raise AssertionError(
            f"No active membership for crm_user_id={crm_user_id} gym_id={gym_id}"
        )
    if len(rows) > 1:
        raise AssertionError(
            f"Expected 1 active membership for crm_user_id={crm_user_id}, "
            f"got {len(rows)}"
        )
    return rows[0]["item_id"]


async def get_membership_stripe_price_id(
    db_pool: DirectDatabasePool,
    item_id: UUID,
) -> str:
    """Return the current ``stripe_price_id`` for a member membership.

    Reads via the ``member_memberships`` + ``membership_plan_prices``
    filtered views, so both rows must be fully synced.
    """
    sql = (
        "SELECT p.stripe_price_id "
        "FROM member_memberships m "
        "JOIN membership_plan_prices p ON p.price_id = m.price_id "
        "WHERE m.item_id = :item_id"
    )
    async with db_pool.session() as session:
        result = await session.execute(
            text(sql),
            {"item_id": str(item_id)},
        )
        row = result.mappings().fetchone()
    if row is None or row["stripe_price_id"] is None:
        raise AssertionError(f"No stripe_price_id for membership item_id={item_id}")
    return row["stripe_price_id"]
