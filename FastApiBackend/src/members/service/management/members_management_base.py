"""Shared dependencies and helpers for member management operations."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import text

from src.members import SQL_DIR
from src.members.members_exceptions import (
    MemberGymStripeAccountMissingError,
    MemberNotFoundError,
)
from src.members.schema.members_billing_schema import (
    MembersBillingProfileResponse,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.payments.service.payments_stripe_members_service import (
        PaymentsStripeMembersService,
    )

logger = logging.getLogger(__name__)

_MANAGEMENT_SQL = SQL_DIR / "management"


class MembersManagementBase:
    """Base class for member management sub-services.

    Holds shared dependencies and reusable query/helper
    methods used across update, linked, and invoices operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payments_members_service: PaymentsStripeMembersService,
    ) -> None:
        self._db_pool = db_pool
        self._payments = payments_members_service

    # ── Shared Queries ─────────────────────────────────────────

    async def _get_stripe_info(
        self,
        member_id: UUID,
    ) -> dict:
        """Fetch member's Stripe IDs and gym's stripe_account_id.

        Args:
            member_id: The member's ID.

        Returns:
            Row dict with stripe_customer_id, stripe_account_id, etc.

        Raises:
            MemberNotFoundError: If the member does not exist (-> 404).
        """
        sql = load_sql(_MANAGEMENT_SQL / "members_management_get_stripe_info.sql")

        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_id": str(member_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise MemberNotFoundError(f"Member {member_id} not found")
        return dict(row)

    async def _get_gym_stripe_account_id(
        self,
        gym_id: UUID,
    ) -> str:
        """Look up a gym's Stripe Connect account ID.

        Args:
            gym_id: The gym to look up.

        Returns:
            The gym's stripe_account_id.

        Raises:
            MemberGymStripeAccountMissingError: If the gym has no Stripe
                account configured (-> 400; the gym cannot transact).
        """
        sql = load_sql(
            _MANAGEMENT_SQL / "members_management_get_gym_stripe.sql",
        )
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"gym_id": str(gym_id)},
            )
            row = result.mappings().fetchone()

        if not row or not row["stripe_account_id"]:
            raise MemberGymStripeAccountMissingError(
                f"Gym {gym_id} has no Stripe account configured"
            )
        return row["stripe_account_id"]

    async def _get_member(
        self,
        member_id: UUID,
    ) -> MembersBillingProfileResponse:
        """Fetch a member's current billing profile as a response model.

        Args:
            member_id: The member to fetch.

        Returns:
            MembersBillingProfileResponse with current data.

        Raises:
            MemberNotFoundError: If the member does not exist (-> 404).
        """
        sql = load_sql(_MANAGEMENT_SQL / "members_management_get_member.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_id": str(member_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise MemberNotFoundError(f"Member {member_id} not found")
        return MembersBillingProfileResponse(**row)
