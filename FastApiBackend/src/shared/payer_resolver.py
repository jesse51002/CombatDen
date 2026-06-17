"""Shared service: resolve a payer's own billing profile."""

from pathlib import Path
from uuid import UUID

from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService
from src.shared.payer_profile import PayerProfile
from src.shared.sql_loader import load_sql

SQL_DIR = Path(__file__).resolve().parent / "sql"


class PayerResolver:
    """Resolves a payer's own billing profile (no parent redirect).

    ``resolve_payer`` / ``resolve_payer_with_account`` look up a specific
    payer's own profile (their own customer / sub / freeze window) — the payer
    is whoever a membership row's ``paid_by_member_id`` names, or an explicit
    request payer. There is NO follow-the-link resolution anywhere in billing:
    ``account_linked_to_id`` is the authorization layer only (who may pay for
    whom — validated by the callers), never a billing key.

    This is the one place the lookup lives — billing-touching services depend
    on this resolver rather than re-running the query.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        gym_stripe_service: GymStripeService,
    ) -> None:
        self._db_pool = db_pool
        self._gym_stripe = gym_stripe_service

    async def resolve_payer(self, payer_member_id: UUID) -> PayerProfile:
        """Resolve a specific payer's OWN billing profile (no link follow).

        The payer is whoever a membership's ``paid_by_member_id`` names — the
        family parent or a self-paying linked member; either way this returns
        that member's own customer / sub / freeze window.

        Raises:
            ValueError: If the profile is not found or the payer has no
                stripe_customer_id.
        """
        sql = load_sql(SQL_DIR / "resolve_payer.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"payer_member_id": str(payer_member_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(
                f"Billing profile not found for payer {payer_member_id}",
            )
        return PayerProfile(**row)

    async def resolve_payer_with_account(
        self,
        payer_member_id: UUID,
    ) -> tuple[PayerProfile, str]:
        """Resolve a payer's profile + that gym's Stripe Connect account id."""
        payer = await self.resolve_payer(payer_member_id)
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            payer.gym_id,
        )
        return payer, stripe_account_id
