"""Batch start: stand up a linked family's memberships in one call.

One request creates N memberships for a paying parent's family with
per-membership discounts applied AT creation, billed in at most two
charges: ONE consolidated one-time invoice (all non-recurring
memberships) + ONE recurring converge. The batch never links accounts —
every non-payer member must already be linked to the payer (linking is a
separate, prior operation), which is what lets the whole batch run under
the payer's single family lock.

Phases (each lands as its own reviewed piece):
- Phase A — validate EVERYTHING up-front; reject with nothing written or
  billed (this file's ``_validate``).
- Phase B — pure DB: pre-sync, mint inline customs, insert pending rows +
  applied-discount rows.
- Phase C + D — the one-time charge, the recurring converge, per-row
  verify, cleanup of failed un-billed rows, the per-membership breakdown.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from schema.gym_discount import DiscountType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
from src.memberships.memberships_schema import (
    MemberMembershipsBatchStartRequest,
    MemberMembershipsBatchStartResponse,
)
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.shared.billing_parent import ParentProfile
    from src.shared.billing_parent_resolver import BillingParentResolver
    from src.sync.service.sync_service import (
        PaymentSyncService,
    )

logger = logging.getLogger(__name__)


class MemberMembershipsBatchStart(MemberMembershipsBase):
    """Create a family's memberships in one call (DB-first, two charges max)."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        parent_resolver: BillingParentResolver,
    ) -> None:
        super().__init__(
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._parent_resolver = parent_resolver

    async def batch_start(
        self,
        request: MemberMembershipsBatchStartRequest,
    ) -> MemberMembershipsBatchStartResponse:
        """Create every membership in the request for the payer's family.

        Validates everything up-front (Phase A) — any validation failure
        rejects the whole batch with nothing written or billed.

        Raises:
            ValueError: If any Phase A validation fails.
        """
        await self._validate(request)
        raise NotImplementedError(
            "batch start phases B-D land next (S12/S13)",
        )

    # ── Phase A — validate everything up-front ─────────────────
    #
    # Order: payer → link/gym state → per-item plan/price + duplicate →
    # discounts. Nothing is written and nothing is billed until every check
    # passes; the request validator already rejected an empty batch and
    # intra-batch (member_id, plan_id) duplicates.

    async def _validate(
        self,
        request: MemberMembershipsBatchStartRequest,
    ) -> dict[tuple[UUID, UUID], dict]:
        """Run every up-front check; return each item's plan/price row.

        Returns:
            The validated plan/price row per ``(member_id, plan_id)`` —
            downstream phases reuse them (price, plan_type, duration)
            without re-reading.

        Raises:
            ValueError: On the first failed check.
        """
        await self._resolve_payer(request)
        await self._check_links(request)

        plan_prices: dict[tuple[UUID, UUID], dict] = {}
        for item in request.memberships:
            plan_price = await self._get_plan_price(
                request.gym_id, item.plan_id, item.price_id,
            )
            if not plan_price["stripe_price_id"]:
                raise ValueError(
                    f"Plan price {item.price_id} missing stripe_price_id",
                )
            await self._check_no_existing(
                item.member_id, request.gym_id, item.plan_id,
            )
            plan_prices[(item.member_id, item.plan_id)] = plan_price

        await self._check_discounts(request)
        return plan_prices

    async def _resolve_payer(
        self,
        request: MemberMembershipsBatchStartRequest,
    ) -> ParentProfile:
        """Validate the payer is a top-level, in-gym, unfrozen paying account.

        ``resolve_parent`` already raises if the resolved account has no
        Stripe customer; card presence is not pre-checked (parity with the
        single start — a missing card surfaces as the charge's own failure,
        and ``paid_with_cash`` needs no card).

        Raises:
            ValueError: If the payer is itself linked to another paying
                account, is in a different gym, or is frozen.
        """
        parent = await self._parent_resolver.resolve_parent(
            request.payer_member_id,
        )
        if parent.member_id != request.payer_member_id:
            raise ValueError(
                f"Payer {request.payer_member_id} is linked to paying account "
                f"{parent.member_id} — the batch payer must be a top-level "
                f"paying account",
            )
        if parent.gym_id != request.gym_id:
            raise ValueError(
                f"Payer {request.payer_member_id} is not in gym {request.gym_id}",
            )
        if parent.is_frozen:
            raise ValueError(
                "Cannot batch start memberships: payer account is frozen",
            )
        return parent

    async def _check_links(
        self,
        request: MemberMembershipsBatchStartRequest,
    ) -> None:
        """Every member exists, is in the gym, and is linked to THIS payer.

        The batch never links — an unlinked or differently-linked member is
        rejected with a "link them first" error. The payer itself (when it
        appears in the items) was already validated as top-level by
        ``_resolve_payer``.

        Raises:
            ValueError: If a member is missing, in another gym, unlinked,
                or linked to a different payer.
        """
        member_ids = {
            item.member_id
            for item in request.memberships
            if item.member_id != request.payer_member_id
        }
        if not member_ids:
            return

        sql = load_sql(SQL_DIR / "member_memberships_batch_account_links.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_ids": [str(uid) for uid in member_ids]},
            )
            rows = {UUID(str(r["member_id"])): r for r in result.mappings()}

        for member_id in member_ids:
            row = rows.get(member_id)
            if row is None:
                raise ValueError(f"Member {member_id} not found")
            if UUID(str(row["gym_id"])) != request.gym_id:
                raise ValueError(
                    f"Member {member_id} is not in gym {request.gym_id}",
                )
            linked_to = row["account_linked_to_id"]
            if linked_to is None:
                raise ValueError(
                    f"Member {member_id} is not linked to payer "
                    f"{request.payer_member_id} — link them first, then batch "
                    f"start (the batch never links accounts)",
                )
            if UUID(str(linked_to)) != request.payer_member_id:
                raise ValueError(
                    f"Member {member_id} is linked to a different paying "
                    f"account ({linked_to}) — unlink them first or use that "
                    f"account as the payer",
                )

    async def _check_discounts(
        self,
        request: MemberMembershipsBatchStartRequest,
    ) -> None:
        """Every requested discount_id is live, in-gym, and not ``custom``.

        One read over the batch's distinct ids. Customs are creation-only
        inline values (``custom_discounts``) — referencing an existing
        ``custom`` discount by id is always rejected. The inline
        ``custom_discounts`` need no check here: ``DiscountValue``
        self-validates.

        Raises:
            ValueError: If a discount is missing/archived/cross-gym or is a
                ``custom`` discount.
        """
        discount_ids = {
            discount_id
            for item in request.memberships
            for discount_id in item.discount_ids
        }
        if not discount_ids:
            return

        sql = load_sql(SQL_DIR / "member_memberships_batch_discounts_check.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "discount_ids": [str(uid) for uid in discount_ids],
                    "gym_id": str(request.gym_id),
                },
            )
            rows = {UUID(str(r["discount_id"])): r for r in result.mappings()}

        for discount_id in discount_ids:
            row = rows.get(discount_id)
            if row is None:
                raise ValueError(
                    f"Discount {discount_id} not found in gym "
                    f"{request.gym_id} (or it is archived / has no active "
                    f"value version)",
                )
            if row["discount_type"] == DiscountType.custom.value:
                raise ValueError(
                    f"Discount {discount_id} is a custom discount — customs "
                    f"are single-use inline values (custom_discounts), never "
                    f"referenced by id",
                )
