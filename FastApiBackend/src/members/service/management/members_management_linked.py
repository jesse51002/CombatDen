"""Link and unlink a member to a paying parent account."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import text

from src.members import SQL_DIR
from src.members.schema.members_management_schema import (
    MembersManagementResponse,
)
from src.members.service.management.members_management_base import (
    MembersManagementBase,
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
        )

        return MembersManagementResponse(**row)

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
        )

        return MembersManagementResponse(**row)

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
