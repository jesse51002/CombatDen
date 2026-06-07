"""Member management billing operations (facade).

Delegates to focused sub-services while preserving a clean public API.
"""

from __future__ import annotations

from typing import TYPE_CHECKING
from uuid import UUID

from src.members.schema.members_billing_schema import (
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
from src.members.service.management.members_management_update import (
    MembersManagementUpdate,
)
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoiceResponse,
    PreviewInvoice,
)
from src.shared.database import DirectDatabasePool

if TYPE_CHECKING:
    from src.payments.service.payments_stripe_members_service import (
        PaymentsStripeMembersService,
    )
    from src.payments.service.subscription import (
        PaymentsStripeSubscriptionService,
    )


class MembersManagementService:
    """Member billing/management operations (facade).

    Delegates to focused sub-services for create, update, and invoices
    operations. Member creation always provisions a Stripe customer via
    MembersManagementCreate — the sole create_customer call site in the backend.
    (Link / unlink moved to ``MemberMembershipsService``.)
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payments_members_service: PaymentsStripeMembersService,
        subscription_service: PaymentsStripeSubscriptionService,
    ) -> None:
        deps = (db_pool, payments_members_service)
        self._create = MembersManagementCreate(*deps)
        self._update = MembersManagementUpdate(*deps)
        self._invoices = MembersManagementInvoices(
            db_pool,
            payments_members_service,
            subscription_service,
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

    async def get_upcoming_invoice(
        self,
        member_id: UUID,
    ) -> PreviewInvoice | None:
        """Fetch the upcoming (next) invoice for a member's account."""
        return await self._invoices.get_upcoming_invoice(member_id)
