"""Shared service: resolve a member to the paying parent + gym Stripe account."""

from pathlib import Path
from uuid import UUID

from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.shared.billing_parent import ParentProfile
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService
from src.shared.sql_loader import load_sql

SQL_DIR = Path(__file__).resolve().parent / "sql"


class BillingParentResolver:
    """Resolves a member to their paying parent profile + gym Stripe account.

    The account hierarchy is single-level: a child resolves up one link to the
    paying parent; a parent resolves to itself. This is the one place that
    lookup lives — billing-touching services depend on this resolver rather
    than re-running the parent query.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        gym_stripe_service: GymStripeService,
    ) -> None:
        self._db_pool = db_pool
        self._gym_stripe = gym_stripe_service

    async def resolve_parent(self, member_id: UUID) -> ParentProfile:
        """Resolve a member to their paying parent profile.

        Follows account_linked_to_id once (single-level hierarchy).

        Raises:
            ValueError: If profile not found or parent has no
                stripe_customer_id.
        """
        sql = load_sql(SQL_DIR / "resolve_parent.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_id": str(member_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(
                f"Profile not found for member_id {member_id}",
            )
        if not row["stripe_customer_id"]:
            raise ValueError(
                f"Parent {row['member_id']} has no stripe_customer_id",
            )
        return ParentProfile(**row)

    async def resolve(self, member_id: UUID) -> tuple[ParentProfile, str]:
        """Resolve the paying parent + that gym's Stripe Connect account id."""
        parent = await self.resolve_parent(member_id)
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            parent.gym_id,
        )
        return parent, stripe_account_id
