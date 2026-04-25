"""Link and unlink a member to a paying parent account."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID, uuid4

from sqlalchemy import text

from src.members import SQL_DIR
from src.members.schema.members_management_schema import (
    MembersManagementLinkCheckResponse,
    MembersManagementResponse,
)
from src.members.service.management.members_management_base import (
    MembersManagementBase,
)
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.member_memberships.service.membership_payment_sync_service import (
        MembershipPaymentSyncService,
    )
    from src.payments.service.payments_stripe_members_service import (
        PaymentsStripeMembersService,
    )
    from src.shared.database import DirectDatabasePool

logger = logging.getLogger(__name__)


class MembersManagementLinked(MembersManagementBase):
    """Link and unlink a member to a paying parent account.

    Both operations require the target member to have zero
    active recurring memberships — this keeps the flow safe
    against Stripe billing side effects and respects the
    immutability rules on linked profiles. Callers must cancel
    any active recurring memberships before linking/unlinking.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payments_members_service: PaymentsStripeMembersService,
        payment_sync_service: MembershipPaymentSyncService,
    ) -> None:
        super().__init__(db_pool, payments_members_service)
        self._sync = payment_sync_service

    # ── Link ───────────────────────────────────────────────────

    async def link_account(
        self,
        crm_user_id: UUID,
        parent_crm_user_id: UUID,
    ) -> MembersManagementResponse:
        """Link an existing member to a paying parent account.

        Validates the child is not already linked and has no
        active recurring memberships, then sets
        ``account_linked_to_id`` and NULLs all stripe/card/freeze
        fields (required by the ``linked_account_no_stripe`` DB
        check). Finally, re-syncs the parent's subscription so
        linked-discount assignments are recalculated.

        Sync is called with empty ``add_ids``/``cancel_ids`` — no
        Stripe items are added or cancelled, so no proration or
        mid-cycle charges are issued.

        Args:
            crm_user_id: The child profile to link.
            parent_crm_user_id: The paying parent profile.

        Returns:
            The refreshed child profile.

        Raises:
            ValueError: If the child is not found, is already
                linked, is the same as the parent, or has any
                active recurring memberships.
        """
        if crm_user_id == parent_crm_user_id:
            raise ValueError("A member cannot be linked to themselves")

        child = await self._get_member(crm_user_id)
        if child.account_linked_to_id is not None:
            raise ValueError(
                f"Member {crm_user_id} is already linked to {child.account_linked_to_id}"
            )

        await self._assert_no_active_recurring(crm_user_id)

        link_sql = load_sql(
            SQL_DIR / "management" / "members_management_link.sql",
        )
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(link_sql),
                {
                    "crm_user_id": str(crm_user_id),
                    "parent_crm_user_id": str(parent_crm_user_id),
                },
            )
            row = result.mappings().fetchone()
            if not row:
                raise ValueError(f"Member {crm_user_id} not found")
            await session.commit()

        await self._sync.update_payments_recurring(
            parent_crm_user_id,
            add_ids=[],
            cancel_ids=[],
            idempotency_key=uuid4(),
        )

        return MembersManagementResponse(**row)

    # ── Check ──────────────────────────────────────────────────

    async def check_link_account(
        self,
        crm_user_id: UUID,
        parent_crm_user_id: UUID,
    ) -> MembersManagementLinkCheckResponse:
        """Check whether a member can be linked to a parent account.

        Read-only. Returns a structured result with a
        user-facing ``error`` string when linking is blocked.
        Each error tells the user what to do to fix it.

        Raises:
            ValueError: If the candidate member does not exist.
                Callers translate this to a 404.
        """
        if crm_user_id == parent_crm_user_id:
            return MembersManagementLinkCheckResponse(
                can_link=False,
                error=("You can't link an account to itself. Pick a different payer."),
            )

        check_sql = load_sql(
            SQL_DIR / "management" / "members_management_link_check.sql",
        )
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(check_sql),
                {
                    "crm_user_id": str(crm_user_id),
                    "parent_crm_user_id": str(parent_crm_user_id),
                },
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Member {crm_user_id} not found")

        if row["candidate_linked_to"] is not None:
            return MembersManagementLinkCheckResponse(
                can_link=False,
                error=(
                    "This member is already linked to another "
                    "paying account. Unlink them first, then "
                    "try again."
                ),
            )

        if row["candidate_is_parent"]:
            return MembersManagementLinkCheckResponse(
                can_link=False,
                error=(
                    "This account already has other members "
                    "linked to it as the payer. Unlink those "
                    "members first before linking this account "
                    "to a new payer."
                ),
            )

        if row["parent_crm_user_id"] is None:
            return MembersManagementLinkCheckResponse(
                can_link=False,
                error=("The selected payer account could not be found. Pick a different payer."),
            )

        if row["parent_linked_to"] is not None:
            return MembersManagementLinkCheckResponse(
                can_link=False,
                error=(
                    "The selected payer is already linked to "
                    "another account as a child. Pick a "
                    "top-level paying account instead."
                ),
            )

        try:
            await self._assert_no_active_recurring(crm_user_id)
        except ValueError:
            return MembersManagementLinkCheckResponse(
                can_link=False,
                error=(
                    "This member has an active recurring "
                    "membership. Cancel all recurring "
                    "memberships before linking them to a payer."
                ),
            )

        return MembersManagementLinkCheckResponse(
            can_link=True,
            error=None,
        )

    # ── Unlink ─────────────────────────────────────────────────

    async def unlink_account(
        self,
        crm_user_id: UUID,
    ) -> MembersManagementResponse:
        """Unlink a member from their paying parent account.

        Clears both ``account_linked_to_id`` and
        ``linked_discount_id`` on the child, then re-syncs the
        old parent so linked-discount assignments are
        recalculated for the remaining children.

        Requires the child to have zero active recurring
        memberships. Sync is called with empty
        ``add_ids``/``cancel_ids`` — no Stripe items change, so
        no proration or mid-cycle charges are issued.

        Args:
            crm_user_id: The child profile to unlink.

        Returns:
            The refreshed child profile with
            ``account_linked_to_id`` cleared.

        Raises:
            ValueError: If the child is not found, is not
                currently linked, or has any active recurring
                memberships.
        """
        child = await self._get_member(crm_user_id)
        if child.account_linked_to_id is None:
            raise ValueError(f"Member {crm_user_id} is not linked to a parent account")
        old_parent_id = child.account_linked_to_id

        await self._assert_no_active_recurring(crm_user_id)

        unlink_sql = load_sql(
            SQL_DIR / "management" / "members_management_unlink.sql",
        )
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(unlink_sql),
                {"crm_user_id": str(crm_user_id)},
            )
            row = result.mappings().fetchone()
            if not row:
                raise ValueError(f"Member {crm_user_id} not found")
            await session.commit()

        await self._sync.update_payments_recurring(
            old_parent_id,
            add_ids=[],
            cancel_ids=[],
            idempotency_key=uuid4(),
        )

        return MembersManagementResponse(**row)

    # ── Preview ────────────────────────────────────────────────

    async def preview_link_account(
        self,
        crm_user_id: UUID,
        parent_crm_user_id: UUID,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what linking to a parent account would charge.

        Runs every validation ``link_account`` runs (self-link
        check, already-linked check, no-active-recurring check)
        and then previews the parent's resulting subscription
        invoice. No SQL writes, no Stripe mutations.

        Returns:
            Invoice preview for the parent, or ``None`` if the
            parent has no recurring subscription to preview.

        Raises:
            ValueError: Same conditions as ``link_account``.
        """
        if crm_user_id == parent_crm_user_id:
            raise ValueError("A member cannot be linked to themselves")

        child = await self._get_member(crm_user_id)
        if child.account_linked_to_id is not None:
            raise ValueError(
                f"Member {crm_user_id} is already linked to {child.account_linked_to_id}"
            )

        await self._assert_no_active_recurring(crm_user_id)

        return await self._sync.preview_update_payments_recurring(
            parent_crm_user_id,
            add_ids=[],
            cancel_ids=[],
        )

    async def preview_unlink_account(
        self,
        crm_user_id: UUID,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what unlinking from a parent account would charge.

        Runs every validation ``unlink_account`` runs (not-linked
        check, no-active-recurring check) and then previews the
        old parent's resulting subscription invoice. No SQL
        writes, no Stripe mutations.

        Returns:
            Invoice preview for the old parent, or ``None`` if the
            parent has no recurring subscription to preview.

        Raises:
            ValueError: Same conditions as ``unlink_account``.
        """
        child = await self._get_member(crm_user_id)
        if child.account_linked_to_id is None:
            raise ValueError(f"Member {crm_user_id} is not linked to a parent account")
        old_parent_id = child.account_linked_to_id

        await self._assert_no_active_recurring(crm_user_id)

        return await self._sync.preview_update_payments_recurring(
            old_parent_id,
            add_ids=[],
            cancel_ids=[],
        )

    # ── Private ────────────────────────────────────────────────

    async def _assert_no_active_recurring(
        self,
        crm_user_id: UUID,
    ) -> None:
        """Raise ValueError if the member has active recurring memberships.

        Linked account changes are only allowed when there are
        no active recurring memberships on the target. The
        caller is responsible for cancelling them first.
        """
        sql = load_sql(
            SQL_DIR / "management" / "members_management_active_recurring.sql",
        )
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"crm_user_id": str(crm_user_id)},
            )
            rows = result.mappings().all()

        if rows:
            raise ValueError(
                f"Member {crm_user_id} has {len(rows)} active "
                f"recurring membership(s) — cancel them before "
                f"changing the linked-account relationship"
            )
