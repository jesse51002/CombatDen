"""Member management operations (facade).

Delegates to focused sub-services while preserving
the public API.
"""

from __future__ import annotations

from typing import TYPE_CHECKING
from uuid import UUID

from src.members.schema.members_management_schema import (
    MembersManagementCreateRequest,
    MembersManagementResponse,
    MembersManagementUpdateCardRequest,
    MembersManagementUpdateRequest,
)
from src.members.service.management.members_management_create import (
    MembersManagementCreate,
)
from src.members.service.management.members_management_invoices import (
    MembersManagementInvoices,
)
from src.members.service.management.members_management_update import (
    MembersManagementUpdate,
)
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoiceResponse,
)
from src.shared.database import DirectDatabasePool

if TYPE_CHECKING:
    from src.payments.service.payments_stripe_members_service import (
        PaymentsStripeMembersService,
    )


class MembersManagementService:
    """Member management operations (facade).

    Delegates to focused sub-services for create, update,
    and invoices operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payments_members_service: PaymentsStripeMembersService,
    ) -> None:
        deps = (db_pool, payments_members_service)
        self._create = MembersManagementCreate(*deps)
        self._update = MembersManagementUpdate(*deps)
        self._invoices = MembersManagementInvoices(*deps)

    # ── Create ─────────────────────────────────────────────────

    async def create_member(
        self,
        request: MembersManagementCreateRequest,
    ) -> MembersManagementResponse:
        """Create a new gym member, optionally with a Stripe customer."""
        return await self._create.create_member(request)

    # ── Update ─────────────────────────────────────────────────

    async def update_member(
        self,
        crm_user_id: UUID,
        request: MembersManagementUpdateRequest,
    ) -> MembersManagementResponse:
        """Update a member's personal information."""
        return await self._update.update_member(crm_user_id, request)

    async def update_card(
        self,
        crm_user_id: UUID,
        request: MembersManagementUpdateCardRequest,
    ) -> MembersManagementResponse:
        """Update a member's payment card in DB and Stripe."""
        return await self._update.update_card(crm_user_id, request)

    async def unlink_payment(
        self,
        crm_user_id: UUID,
    ) -> MembersManagementResponse:
        """Remove a member's payment card."""
        return await self._update.unlink_payment(crm_user_id)

    # ── Invoices ───────────────────────────────────────────────

    async def list_invoices(
        self,
        crm_user_id: UUID,
        limit: int = 100,
        starting_after: str | None = None,
    ) -> list[PaymentsInvoiceResponse]:
        """List Stripe invoices for a member."""
        return await self._invoices.list_invoices(
            crm_user_id,
            limit=limit,
            starting_after=starting_after,
        )
