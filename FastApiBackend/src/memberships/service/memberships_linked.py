"""Link / unlink a member to a paying parent account.

Linking sets ``members.account_linked_to_id`` (and NULLs the child's
stripe/card/freeze fields, required by the ``linked_account_no_stripe`` DB
check); unlinking clears it. Both REQUIRE the target member to have zero active
recurring memberships (``_assert_no_active_recurring``).

These are **pure DB changes — no Stripe sync.** Because a member with no active
recurring memberships contributes no membership line and no discount snapshot to
the family, and the engine never recomputes discounts family-wide (each
membership's bill is derived from that member's own memberships only — see the
``discounts-guide``), changing the link never changes anyone's bill. The
no-active-recurring guard is exactly what keeps that true: the only case where a
relationship change *would* move billing is a member who still carries a
membership, which is forbidden here.

The two-family ``PayingMemberLock`` is still held across each op so the
check-then-write (no-active-recurring / already-linked) cannot race a concurrent
membership start on the same family.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import text

from src.memberships import SQL_DIR
from src.memberships.memberships_schema import (
    MembersBillingLinkCheckResponse,
)
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.shared.database import DirectDatabasePool
    from src.shared.paying_member_lock import PayingMemberLock

logger = logging.getLogger(__name__)


class MemberMembershipsLinked:
    """Link / unlink a member to a paying parent account.

    Self-contained (does not share ``MemberMembershipsBase``): link / unlink is
    member-keyed and writes the ``members`` table, so the base's item-keyed
    membership-row helpers do not apply.

    Owns its OWN concurrency locking: link / unlink lock TWO families (the
    member's own and the paying parent's), so — unlike the single-family lifecycle
    ops — the facade must NOT wrap these in ``lock([member_id])``.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        paying_lock: PayingMemberLock,
    ) -> None:
        self._db_pool = db_pool
        self._paying_lock = paying_lock

    # ── Link ───────────────────────────────────────────────────

    async def link_account(
        self,
        member_id: UUID,
        parent_member_id: UUID,
    ) -> None:
        """Link a member to a paying parent account.

        Validates the child is not already linked and has no active recurring
        memberships, then sets ``account_linked_to_id`` and NULLs all
        stripe/card/freeze fields (required by the ``linked_account_no_stripe``
        DB check).

        Pure DB change — no Stripe sync: the child has no active recurring
        memberships, so the family's consolidated subscription is unaffected (see
        the module docstring).

        Args:
            member_id: The child profile to link.
            parent_member_id: The paying parent profile.

        Raises:
            ValueError: If the child is not found, is already linked,
                is the same as the parent, or has any active recurring
                memberships.
        """
        if member_id == parent_member_id:
            raise ValueError("A member cannot be linked to themselves")

        # Lock BOTH families — the child's own and the new paying parent's — so
        # the check-then-write can't race a concurrent op on either.
        async with self._paying_lock.lock([member_id, parent_member_id]):
            existing_parent = await self._get_account_link(member_id)
            if existing_parent is not None:
                raise ValueError(
                    f"Member {member_id} is already linked to {existing_parent}"
                )

            await self._assert_no_active_recurring(member_id)
            await self._write_link(member_id, parent_member_id)

    # ── Unlink ─────────────────────────────────────────────────

    async def unlink_account(
        self,
        member_id: UUID,
    ) -> None:
        """Unlink a member from their paying parent account.

        Clears ``account_linked_to_id`` on the child.

        Pure DB change — no Stripe sync: the child has no active recurring
        memberships, so the old parent's consolidated subscription is unaffected
        (see the module docstring).

        Args:
            member_id: The child profile to unlink.

        Raises:
            ValueError: If the child is not found, is not currently linked,
                or has any active recurring memberships.
        """
        old_parent_id = await self._get_account_link(member_id)
        if old_parent_id is None:
            raise ValueError(f"Member {member_id} is not linked to a parent account")

        # Lock the child + its old paying parent so the check-then-write can't
        # race a concurrent op on that family.
        async with self._paying_lock.lock([member_id, old_parent_id]):
            await self._assert_no_active_recurring(member_id)
            await self._write_unlink(member_id)

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

        check_sql = load_sql(SQL_DIR / "member_memberships_link_check.sql")
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

    # ── Private ────────────────────────────────────────────────

    async def _get_account_link(
        self,
        member_id: UUID,
    ) -> UUID | None:
        """Return the member's ``account_linked_to_id`` (None if unlinked).

        Reads the unfiltered ``members`` row. Raises if the member does not
        exist (preserves the not-found → 404 contract for link / unlink).
        """
        sql = load_sql(SQL_DIR / "member_memberships_get_account_link.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_id": str(member_id)},
            )
            row = result.mappings().fetchone()

        if row is None:
            raise ValueError(f"Member {member_id} not found")
        linked_to = row["account_linked_to_id"]
        return UUID(str(linked_to)) if linked_to is not None else None

    async def _write_link(
        self,
        member_id: UUID,
        parent_member_id: UUID,
    ) -> None:
        """Set ``account_linked_to_id`` on the child (also NULLs its stripe/card
        fields, per the ``linked_account_no_stripe`` DB check)."""
        sql = load_sql(SQL_DIR / "member_memberships_link.sql")
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

        NOTE: a child carries no card by design (a link NULLed its stripe/card
        fields), so unlinking only restores the relationship — the member simply
        re-adds a card if needed.
        """
        sql = load_sql(SQL_DIR / "member_memberships_unlink.sql")
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
        sql = load_sql(SQL_DIR / "member_memberships_active_recurring.sql")
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
