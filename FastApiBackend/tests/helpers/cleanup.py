"""Database cleanup utilities for integration tests.

Standalone module — no pytest imports, no fixture dependencies.
Every function accepts its dependencies as parameters.
"""

from uuid import UUID

from sqlalchemy import text

from src.shared.database import DirectDatabasePool

# Tables in FK-safe deletion order (children before parents).
# ``member_charges`` cascades from ``member_invoices`` but is listed
# explicitly for defensive cleanup if a charge ever outlives its invoice.
_GYM_TABLES = (
    "stripe_webhook_events",
    "member_charges",
    "member_invoices",
    "member_memberships_unfiltered",
    "membership_plan_prices_unfiltered",
    "gym_discounts_unfiltered",
    "membership_plans_unfiltered",
    "members",
)


async def delete_all_gym_data(db_pool: DirectDatabasePool, gym_id: UUID) -> None:
    """Delete all test data for a gym in correct FK order.

    Does NOT delete the gym row itself — caller handles that.

    Linked discounts are deleted one-at-a-time in descending
    ``linked_discount_num`` order before the bulk table delete,
    because the ``check_linked_discount_delete_order`` trigger
    enforces that only the highest remaining number may be
    removed at any moment. A mass ``DELETE FROM gym_discounts``
    would fire the trigger on an arbitrary row and fail.
    """
    async with db_pool.session() as session:
        # linked_discount_id / account_linked_to_id were unified onto the members
        # table (formerly on member_billing_profile). Clear them first so deleting
        # the linked discounts and the members rows doesn't trip the
        # fk_member_linked_discount FK or the account-link self-FK.
        await session.execute(
            text(
                "UPDATE members SET linked_discount_id = NULL, "
                "account_linked_to_id = NULL WHERE gym_id = :gym_id"
            ),
            {"gym_id": str(gym_id)},
        )
        linked_rows = await session.execute(
            text(
                "SELECT discount_id FROM gym_discounts_unfiltered "
                "WHERE gym_id = :gym_id "
                "AND linked_discount_num IS NOT NULL "
                "ORDER BY linked_discount_num DESC"
            ),
            {"gym_id": str(gym_id)},
        )
        linked_ids = [row[0] for row in linked_rows.fetchall()]
        for linked_id in linked_ids:
            await session.execute(
                text("DELETE FROM gym_discounts_unfiltered WHERE discount_id = :id"),
                {"id": str(linked_id)},
            )

        for table in _GYM_TABLES:
            await session.execute(
                text(f"DELETE FROM {table} WHERE gym_id = :gym_id"),  # noqa: S608
                {"gym_id": str(gym_id)},
            )
        await session.commit()


async def delete_member_data(
    db_pool: DirectDatabasePool,
    member_id: UUID,
) -> None:
    """Delete a single member and their memberships."""
    async with db_pool.session() as session:
        await session.execute(
            text("DELETE FROM member_memberships_unfiltered WHERE member_id = :id"),
            {"id": str(member_id)},
        )
        await session.execute(
            text("DELETE FROM members WHERE member_id = :id"),
            {"id": str(member_id)},
        )
        await session.commit()
