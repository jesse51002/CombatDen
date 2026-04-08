"""Shared service for fetching a gym's Stripe Connect account ID."""

from pathlib import Path
from uuid import UUID

from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

SQL_DIR = Path(__file__).resolve().parent / "sql"


class GymStripeService:
    """Look up Stripe Connect account IDs for gyms."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def get_stripe_account_id(self, gym_id: UUID) -> str:
        """Fetch a gym's Stripe Connect account ID.

        Args:
            gym_id: The gym to look up.

        Returns:
            The gym's stripe_account_id.

        Raises:
            ValueError: If the gym has no Stripe account configured.
        """
        sql = load_sql(SQL_DIR / "gym_stripe_account.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"gym_id": str(gym_id)},
            )
            row = result.mappings().fetchone()

        if not row or not row["stripe_account_id"]:
            raise ValueError(
                f"Gym {gym_id} has no Stripe account configured",
            )
        return row["stripe_account_id"]
