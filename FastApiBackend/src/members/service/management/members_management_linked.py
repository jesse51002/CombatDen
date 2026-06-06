"""Link and unlink a member to a paying parent account."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID, uuid4

from sqlalchemy import text

from src.members import SQL_DIR
from src.members.schema.members_billing_schema import (
    MembersBillingLinkCheckResponse,
    MembersBillingProfileResponse,
)
from src.members.service.management.members_management_base import (
    MembersManagementBase,
)
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.shared.db_first_helpers import sync_or_revert
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.member_memberships.service.payment_sync.payment_sync_service import (
        PaymentSyncService,
    )
    from src.payments.service.payments_stripe_members_service import (
        PaymentsStripeMembersService,
    )
    from src.shared.database import DirectDatabasePool

logger = logging.getLogger(__name__)

_MANAGEMENT_SQL = SQL_DIR / "management"


class MembersManagementLinked(MembersManagementBase):
    """Link and unlink a member to a paying parent account.

    Both operations require the target member to have zero active recurring
    memberships — this keeps the flow safe against Stripe billing side
    effects and respects the immutability rules on linked profiles.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payments_members_service: PaymentsStripeMembersService,
        payment_sync_service: PaymentSyncService,
    ) -> None:
        super().__init__(db_pool, payments_members_service)
        self._sync = payment_sync_service

    # ── Link ───────────────────────────────────────────────────

    async def link_account(
        self,
        member_id: UUID,
        parent_member_id: UUID,
    ) -> MembersBillingProfileResponse:
        """Link an existing member to a paying parent account.

        Validates the child is not already linked and has no active recurring
        memberships, then sets ``account_linked_to_id`` and NULLs all
        stripe/card/freeze fields (required by the ``linked_account_no_stripe``
        DB check). Finally, re-syncs the parent's subscription so linked-discount
        tiers are recalculated for the new family size.

        DB-first: the link is written FIRST, then the parent sync converges
        Stripe. If that sync fails the link is reverted (the child is unlinked)
        so the family size in the DB matches Stripe. The child has no recurring
        memberships (asserted), so there is no membership-row status to verify —
        the guarantee here is revert-on-failure.

        Args:
            member_id: The child profile to link.
            parent_member_id: The paying parent profile.

        Returns:
            The refreshed child profile.

        Raises:
            ValueError: If the child is not found, is already linked,
                is the same as the parent, or has any active recurring
                memberships.
        """
        if member_id == parent_member_id:
            raise ValueError("A member cannot be linked to themselves")

        child = await self._get_member(member_id)
        if child.account_linked_to_id is not None:
            raise ValueError(
                f"Member {member_id} is already linked to {child.account_linked_to_id}"
            )

        await self._assert_no_active_recurring(member_id)

        # ── DB-first: write the link, THEN converge the parent's Stripe sub ──
        await self._write_link(member_id, parent_member_id)

        await sync_or_revert(
            sync_fn=lambda: self._sync.update_payments_recurring(
                parent_member_id,
                idempotency_key=uuid4(),
            ),
            revert_fn=lambda: self._write_unlink(member_id),
            entity_name="member_link",
            crm_pk=str(member_id),
        )

        return await self._get_member(member_id)

    # ── Check ──────────────────────────────────────────────────

    async def check_link_account(
        self,
        member_id: UUID,
        parent_member_id: UUID,
    ) -> MembersBillingLinkCheckResponse:
        """Check whether a member can be linked to a parent account.

        Read-only. Returns a structured result with a user-facing
        ``error`` string when linking is blocked.

        Raises:
            ValueError: If the candidate member does not exist (→ 404).
        """
        if member_id == parent_member_id:
            return MembersBillingLinkCheckResponse(
                can_link=False,
                error="You can't link an account to itself. Pick a different payer.",
            )

        check_sql = load_sql(_MANAGEMENT_SQL / "members_management_link_check.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(check_sql),
                {
                    "member_id": str(member_id),
                    "parent_member_id": str(parent_member_id),
                },
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Member {member_id} not found")

        if row["candidate_linked_to"] is not None:
            return MembersBillingLinkCheckResponse(
                can_link=False,
                error=(
                    "This member is already linked to another "
                    "paying account. Unlink them first, then try again."
                ),
            )

        if row["candidate_is_parent"]:
            return MembersBillingLinkCheckResponse(
                can_link=False,
                error=(
                    "This account already has other members linked to it as the "
                    "payer. Unlink those members first before linking this account "
                    "to a new payer."
                ),
            )

        if row["parent_member_id"] is None:
            return MembersBillingLinkCheckResponse(
                can_link=False,
                error="The selected payer account could not be found. Pick a different payer.",
            )

        if row["parent_linked_to"] is not None:
            return MembersBillingLinkCheckResponse(
                can_link=False,
                error=(
                    "The selected payer is already linked to another account as a "
                    "child. Pick a top-level paying account instead."
                ),
            )

        try:
            await self._assert_no_active_recurring(member_id)
        except ValueError:
            return MembersBillingLinkCheckResponse(
                can_link=False,
                error=(
                    "This member has an active recurring membership. Cancel all "
                    "recurring memberships before linking them to a payer."
                ),
            )

        return MembersBillingLinkCheckResponse(can_link=True, error=None)

    # ── Unlink ─────────────────────────────────────────────────

    async def unlink_account(
        self,
        member_id: UUID,
    ) -> MembersBillingProfileResponse:
        """Unlink a member from their paying parent account.

        Clears ``account_linked_to_id`` on the child, then re-syncs the old
        parent so the consolidated subscription reflects the smaller family.

        DB-first: the unlink is written FIRST, then the old parent's sync
        converges Stripe. If that sync fails the unlink is reverted (the child is
        re-linked to the old parent) so the family size in the DB matches Stripe.

        Args:
            member_id: The child profile to unlink.

        Returns:
            The refreshed child profile with ``account_linked_to_id`` cleared.

        Raises:
            ValueError: If the child is not found, is not currently linked,
                or has any active recurring memberships.
        """
        child = await self._get_member(member_id)
        if child.account_linked_to_id is None:
            raise ValueError(f"Member {member_id} is not linked to a parent account")
        old_parent_id = child.account_linked_to_id

        await self._assert_no_active_recurring(member_id)

        # ── DB-first: write the unlink, THEN converge the old parent's sub ──
        await self._write_unlink(member_id)

        await sync_or_revert(
            sync_fn=lambda: self._sync.update_payments_recurring(
                old_parent_id,
                idempotency_key=uuid4(),
            ),
            revert_fn=lambda: self._write_link(member_id, old_parent_id),
            entity_name="member_link",
            crm_pk=str(member_id),
        )

        return await self._get_member(member_id)

    # ── Preview ────────────────────────────────────────────────

    async def preview_link_account(
        self,
        member_id: UUID,
        parent_member_id: UUID,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what linking to a parent account would charge.

        Runs every validation ``link_account`` runs and previews the
        parent's resulting subscription invoice. No SQL writes, no
        Stripe mutations.

        Returns:
            Invoice preview for the parent, or ``None`` if the parent
            has no recurring subscription to preview.

        Raises:
            ValueError: Same conditions as ``link_account``.
        """
        if member_id == parent_member_id:
            raise ValueError("A member cannot be linked to themselves")

        child = await self._get_member(member_id)
        if child.account_linked_to_id is not None:
            raise ValueError(
                f"Member {member_id} is already linked to {child.account_linked_to_id}"
            )

        await self._assert_no_active_recurring(member_id)

        return await self._sync.preview_update_payments_recurring(
            parent_member_id,
        )

    async def preview_unlink_account(
        self,
        member_id: UUID,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what unlinking from a parent account would charge.

        Runs every validation ``unlink_account`` runs and previews the
        old parent's resulting subscription invoice. No SQL writes, no
        Stripe mutations.

        Returns:
            Invoice preview for the old parent, or ``None`` if the
            parent has no recurring subscription to preview.

        Raises:
            ValueError: Same conditions as ``unlink_account``.
        """
        child = await self._get_member(member_id)
        if child.account_linked_to_id is None:
            raise ValueError(f"Member {member_id} is not linked to a parent account")
        old_parent_id = child.account_linked_to_id

        await self._assert_no_active_recurring(member_id)

        return await self._sync.preview_update_payments_recurring(
            old_parent_id,
        )

    # ── Private ────────────────────────────────────────────────

    async def _write_link(
        self,
        member_id: UUID,
        parent_member_id: UUID,
    ) -> None:
        """Set ``account_linked_to_id`` on the child (also NULLs its stripe/card
        fields, per the ``linked_account_no_stripe`` DB check).

        Used both as the forward link write and to REVERT an unlink (re-link to
        the old parent — the child's card fields were already NULL while linked,
        so re-running the NULLing is a no-op there).
        """
        sql = load_sql(_MANAGEMENT_SQL / "members_management_link.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "member_id": str(member_id),
                    "parent_member_id": str(parent_member_id),
                },
            )
            row = result.mappings().fetchone()
            if not row:
                raise ValueError(f"Member {member_id} not found")
            await session.commit()

    async def _write_unlink(
        self,
        member_id: UUID,
    ) -> None:
        """Clear ``account_linked_to_id`` on the child.

        Used both as the forward unlink write and to REVERT a link whose parent
        sync failed. NOTE: a link NULLs the child's stripe/card fields and this
        revert only restores the relationship, not those fields — a linked child
        carries no card by design, so the child simply re-adds one if needed.
        """
        sql = load_sql(_MANAGEMENT_SQL / "members_management_unlink.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_id": str(member_id)},
            )
            row = result.mappings().fetchone()
            if not row:
                raise ValueError(f"Member {member_id} not found")
            await session.commit()

    async def _assert_no_active_recurring(
        self,
        member_id: UUID,
    ) -> None:
        """Raise ValueError if the member has active recurring memberships."""
        sql = load_sql(_MANAGEMENT_SQL / "members_management_active_recurring.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_id": str(member_id)},
            )
            rows = result.mappings().all()

        if rows:
            raise ValueError(
                f"Member {member_id} has {len(rows)} active recurring membership(s) "
                f"— cancel them before changing the linked-account relationship"
            )
