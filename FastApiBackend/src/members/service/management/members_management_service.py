"""Member management billing operations (facade).

Delegates to focused sub-services while preserving a clean public API.
"""

from __future__ import annotations

from typing import TYPE_CHECKING
from uuid import UUID

from src.members.schema.members_billing_schema import (
    MembersBillingLinkCheckResponse,
    MembersBillingProfileResponse,
    MembersBillingUpdateCardRequest,
)
from src.members.schema.members_schema import (
    MemberCreateRequest,
    MemberResponse,
    MemberUpdateData,
)
from src.members.service.management.members_management_create import (
    MembersManagementCreate,
)
from src.members.service.management.members_management_invoices import (
    MembersManagementInvoices,
)
from src.members.service.management.members_management_linked import (
    MembersManagementLinked,
)
from src.members.service.management.members_management_update import (
    MembersManagementUpdate,
)
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
    PaymentsInvoiceResponse,
)
from src.shared.database import DirectDatabasePool

if TYPE_CHECKING:
    from src.member_memberships.service.payment_sync.payment_sync_service import (
        PaymentSyncService,
    )
    from src.payments.service.payments_stripe_members_service import (
        PaymentsStripeMembersService,
    )


class MembersManagementService:
    """Member billing/management operations (facade).

    Delegates to focused sub-services for create, update, linked-account,
    and invoices operations. Member creation always provisions a Stripe
    customer via MembersManagementCreate — the sole create_customer call
    site in the backend.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payments_members_service: PaymentsStripeMembersService,
        payment_sync_service: PaymentSyncService,
    ) -> None:
        deps = (db_pool, payments_members_service)
        self._create = MembersManagementCreate(*deps)
        self._update = MembersManagementUpdate(*deps)
        self._invoices = MembersManagementInvoices(*deps)
        self._linked = MembersManagementLinked(
            db_pool,
            payments_members_service,
            payment_sync_service,
        )

    # ── Create / Update member ─────────────────────────────────

    async def create_member(
        self,
        request: MemberCreateRequest,
    ) -> MembersBillingProfileResponse:
        """Create a member and provision its Stripe customer atomically."""
        return await self._create.create_member(request)

    async def update_member(
        self,
        member_id: UUID,
        data: MemberUpdateData,
    ) -> MemberResponse:
        """Update a member's identity / contact fields (no Stripe write)."""
        return await self._update.update_member(member_id, data)

    # ── Card ───────────────────────────────────────────────────

    async def update_card(
        self,
        member_id: UUID,
        request: MembersBillingUpdateCardRequest,
    ) -> MembersBillingProfileResponse:
        """Update a member's payment card in DB and Stripe."""
        return await self._update.update_card(member_id, request)

    async def unlink_payment(
        self,
        member_id: UUID,
    ) -> MembersBillingProfileResponse:
        """Remove a member's payment card."""
        return await self._update.unlink_payment(member_id)

    # ── Linked Account ─────────────────────────────────────────

    async def link_account(
        self,
        member_id: UUID,
        parent_member_id: UUID,
    ) -> MembersBillingProfileResponse:
        """Link an existing member to a paying parent account."""
        return await self._linked.link_account(member_id, parent_member_id)

    async def check_link_account(
        self,
        member_id: UUID,
        parent_member_id: UUID,
    ) -> MembersBillingLinkCheckResponse:
        """Check whether a member can be linked to a parent account."""
        return await self._linked.check_link_account(member_id, parent_member_id)

    async def preview_link_account(
        self,
        member_id: UUID,
        parent_member_id: UUID,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what linking to a parent account would charge."""
        return await self._linked.preview_link_account(member_id, parent_member_id)

    async def unlink_account(
        self,
        member_id: UUID,
    ) -> MembersBillingProfileResponse:
        """Unlink a member from their paying parent account."""
        return await self._linked.unlink_account(member_id)

    async def preview_unlink_account(
        self,
        member_id: UUID,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what unlinking from a parent account would charge."""
        return await self._linked.preview_unlink_account(member_id)

    # ── Invoices ───────────────────────────────────────────────

    async def list_invoices(
        self,
        member_id: UUID,
        limit: int = 100,
        starting_after: str | None = None,
    ) -> list[PaymentsInvoiceResponse]:
        """List Stripe invoices for a member."""
        return await self._invoices.list_invoices(
            member_id,
            limit=limit,
            starting_after=starting_after,
        )
