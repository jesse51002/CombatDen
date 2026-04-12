"""List Stripe invoices for a member."""

from __future__ import annotations

import logging
from uuid import UUID

from src.members.service.management.members_management_base import (
    MembersManagementBase,
)
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoiceResponse,
)

logger = logging.getLogger(__name__)


class MembersManagementInvoices(MembersManagementBase):
    """List Stripe invoices for a member."""

    async def list_invoices(
        self,
        crm_user_id: UUID,
        limit: int = 100,
        starting_after: str | None = None,
    ) -> list[PaymentsInvoiceResponse]:
        """List Stripe invoices for a member.

        Args:
            crm_user_id: The member whose invoices to list.
            limit: Max invoices to return (1-100).
            starting_after: Cursor for pagination (invoice ID).

        Returns:
            List of invoice details from Stripe.

        Raises:
            ValueError: If the member has no Stripe customer
                (no card on file).
        """
        info = await self._get_stripe_info(crm_user_id)

        if not info["stripe_customer_id"]:
            raise ValueError(f"Member {crm_user_id} has no Stripe customer")

        if not info["stripe_account_id"]:
            raise ValueError(f"Gym {info['gym_id']} has no Stripe account configured")

        return await self._payments.list_invoices(
            stripe_customer_id=info["stripe_customer_id"],
            stripe_account_id=info["stripe_account_id"],
            limit=limit,
            starting_after=starting_after,
        )
