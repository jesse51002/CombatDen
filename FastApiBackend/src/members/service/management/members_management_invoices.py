"""List Stripe invoices and the upcoming invoice for a member."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import text

from src.members import SQL_DIR
from src.members.service.management.members_management_base import (
    MembersManagementBase,
)
from src.payments.payments_exceptions import (
    PaymentsResourceNotFoundError,
)
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoiceResponse,
    PreviewInvoice,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.payments.service.payments_stripe_members_service import (
        PaymentsStripeMembersService,
    )
    from src.payments.service.subscription import (
        PaymentsStripeSubscriptionService,
    )

logger = logging.getLogger(__name__)

_MANAGEMENT_SQL = SQL_DIR / "management"


class MembersManagementInvoices(MembersManagementBase):
    """List Stripe invoices and fetch the upcoming invoice for a member."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payments_members_service: PaymentsStripeMembersService,
        subscription_service: PaymentsStripeSubscriptionService,
    ) -> None:
        super().__init__(db_pool, payments_members_service)
        self._subscription = subscription_service

    async def list_invoices(
        self,
        member_id: UUID,
        limit: int = 100,
        starting_after: str | None = None,
    ) -> list[PaymentsInvoiceResponse]:
        """List Stripe invoices for a member.

        Args:
            member_id: The member whose invoices to list.
            limit: Max invoices to return (1-100).
            starting_after: Cursor for pagination (invoice ID).

        Returns:
            List of invoice details from Stripe.

        Raises:
            ValueError: If the member has no Stripe customer
                or the gym has no Stripe account.
        """
        info = await self._get_stripe_info(member_id)

        if not info["stripe_customer_id"]:
            raise ValueError(f"Member {member_id} has no Stripe customer")

        if not info["stripe_account_id"]:
            raise ValueError(f"Gym {info['gym_id']} has no Stripe account configured")

        return await self._payments.list_invoices(
            stripe_customer_id=info["stripe_customer_id"],
            stripe_account_id=info["stripe_account_id"],
            limit=limit,
            starting_after=starting_after,
        )

    async def get_upcoming_invoice(
        self,
        member_id: UUID,
    ) -> PreviewInvoice | None:
        """Fetch the upcoming (next) invoice for a member's OWN subscription.

        Under per-payer billing each payer funds their own subscription,
        so ``member_id`` is the PAYER whose invoice is wanted: this reads
        that member's OWN monthly Stripe subscription id (no parent
        resolution) and previews its next invoice. Returns ``None`` when
        the member has no recurring subscription of their own (e.g. their
        memberships are paid by someone else) or Stripe has no upcoming
        invoice for it — an empty state, not an error. To see the invoice
        for a membership a parent pays, pass the parent's id.

        Args:
            member_id: The payer whose next invoice to preview.

        Returns:
            The upcoming invoice preview, or ``None`` when there is none.

        Raises:
            ValueError: If the member does not exist or the gym has no
                Stripe account configured.
        """
        sql = load_sql(_MANAGEMENT_SQL / "members_management_get_upcoming_info.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_id": str(member_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Member {member_id} not found")
        if not row["stripe_account_id"]:
            raise ValueError(
                f"Gym {row['gym_id']} has no Stripe account configured"
            )
        if not row["stripe_sub_id_month"]:
            return None

        try:
            return await self._subscription.fetch_upcoming_invoice(
                row["stripe_sub_id_month"],
                row["stripe_account_id"],
            )
        except PaymentsResourceNotFoundError:
            return None
