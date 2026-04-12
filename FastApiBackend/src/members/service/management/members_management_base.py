"""Shared dependencies and helpers for member management operations."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import text

from src.members import SQL_DIR
from src.members.schema.members_management_schema import (
    MembersManagementResponse,
)
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerCreateRequest,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.payments.service.payments_stripe_members_service import (
        PaymentsStripeMembersService,
    )

logger = logging.getLogger(__name__)


class MembersManagementBase:
    """Base class for member management sub-services.

    Holds shared dependencies and reusable query/helper
    methods used across create, update, and invoices
    operations.
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
        crm_user_id: UUID,
    ) -> dict:
        """Fetch member's Stripe IDs and gym's stripe_account_id.

        Args:
            crm_user_id: The member's CRM user ID.

        Returns:
            Row dict with stripe_customer_id, stripe_account_id, etc.

        Raises:
            ValueError: If the member does not exist.
        """
        sql = load_sql(SQL_DIR / "management" / "members_management_get_stripe_info.sql")

        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"crm_user_id": str(crm_user_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Member {crm_user_id} not found")
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
            ValueError: If the gym has no Stripe account configured.
        """
        sql = load_sql(SQL_DIR / "management" / "members_management_get_gym_stripe.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"gym_id": str(gym_id)},
            )
            row = result.mappings().fetchone()

        if not row or not row["stripe_account_id"]:
            raise ValueError(f"Gym {gym_id} has no Stripe account configured")
        return row["stripe_account_id"]

    async def _get_member(
        self,
        crm_user_id: UUID,
    ) -> MembersManagementResponse:
        """Fetch a member's current data as a response model.

        Args:
            crm_user_id: The member to fetch.

        Returns:
            MembersManagementResponse with current data.

        Raises:
            ValueError: If the member does not exist.
        """
        sql = load_sql(SQL_DIR / "management" / "members_management_get_member.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"crm_user_id": str(crm_user_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Member {crm_user_id} not found")
        return MembersManagementResponse(**row)

    # ── Static Helpers ─────────────────────────────────────────

    def _build_stripe_create_request(
        self,
        name: str,
        email: str | None,
        phone: str | None,
        payment_method_id: str,
    ) -> PaymentsCustomerCreateRequest:
        """Build a Stripe customer create request from member data."""
        return PaymentsCustomerCreateRequest(
            name=name,
            email=email,
            phone=phone,
            payment_method_id=payment_method_id,
        )
