"""Phase A of the start op: validate EVERYTHING up-front, write nothing.

One request creates N memberships billed by ONE payer (a single membership =
a one-item list). The payer may be the member themselves (self-pay, including
a linked member paying their own way) or a member's linked parent —
``_check_links`` is the authorization rule: every non-payer member in the
request must be linked to the payer. The real start and the start preview run
this IDENTICAL validation first — it lives in its own class so that stays
structural, not copy-paste. Any failure rejects the whole request with
nothing written and nothing billed.

Order: payer → link/gym state → price/plan rows → intra-request recurring
duplicate check → recurring-quantity check → per-member existing-recurring
check → discounts. The request model rejects duplicate ``(member_id, price_id)``
items (buying N of a pack is ONE item with ``quantity = N``, never N duplicate
items); the recurring "two on the same plan, at different prices, in one
request" rule is enforced here, where plan types are known.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from schema.gym_discount import DiscountType
from schema.membership_plan import PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
from src.memberships.memberships_schema import (
    MemberMembershipsStartRequest,
)
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.shared.payer_profile import PayerProfile
    from src.shared.payer_resolver import PayerResolver
    from src.sync.service.sync_service import (
        PaymentSyncService,
    )

logger = logging.getLogger(__name__)


class MemberMembershipsStartValidation(MemberMembershipsBase):
    """Up-front validation for the start op (shared by start + preview)."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        payer_resolver: PayerResolver,
    ) -> None:
        super().__init__(
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._payer_resolver = payer_resolver

    async def validate(
        self,
        request: MemberMembershipsStartRequest,
    ) -> tuple[PayerProfile, dict[UUID, dict]]:
        """Run every up-front check; return the payer + plan/price rows.

        Returns:
            The resolved payer profile and the validated plan/price row per
            ``price_id`` (a price belongs to exactly one plan, so the row
            carries the derived ``plan_id``) — downstream phases reuse them
            (timezone, price, plan_type, duration) without re-reading.

        Raises:
            ValueError: On the first failed check.
        """
        payer = await self._resolve_payer(request)
        await self._check_links(request)

        price_ids = list({item.price_id for item in request.memberships})
        plan_prices = await self._get_plan_prices(request.gym_id, price_ids)
        for price_id in price_ids:
            if not plan_prices[price_id]["stripe_price_id"]:
                raise ValueError(
                    f"Plan price {price_id} missing stripe_price_id",
                )

        self._check_no_recurring_duplicates(request, plan_prices)
        self._check_recurring_quantity(request, plan_prices)

        plans_by_member: dict[UUID, list[UUID]] = {}
        for item in request.memberships:
            plans_by_member.setdefault(item.member_id, []).append(
                plan_prices[item.price_id]["plan_id"],
            )
        for member_id, plan_ids in plans_by_member.items():
            await self._check_no_existing(
                member_id, request.gym_id, plan_ids,
            )

        await self._check_discounts(request)
        return payer, plan_prices

    def _check_no_recurring_duplicates(
        self,
        request: MemberMembershipsStartRequest,
        plan_prices: dict[UUID, dict],
    ) -> None:
        """Reject two RECURRING items on the same plan in one request.

        Exact duplicate items (same member + same price) are already blocked
        structurally by MemberMembershipsStartItem's request validator. This
        guard adds the case that one can't see: two recurring items on the same
        PLAN at DIFFERENT prices (e.g. monthly + annual of plan A) — same
        (member, plan), different price_id. A member can hold only one active
        recurring membership per plan, and a BEFORE-INSERT row trigger can't be
        relied on to catch two siblings inserted in the SAME multi-row INSERT,
        so this surfaces it early, before any write. (one_time / trial stack via
        quantity, not repeated items, so they have no equivalent restriction.)

        Raises:
            ValueError: On the first duplicate recurring (member, plan).
        """
        seen: set[tuple[UUID, UUID]] = set()
        for item in request.memberships:
            row = plan_prices[item.price_id]
            if row["plan_type"] != PlanType.recurring:
                continue
            key = (item.member_id, row["plan_id"])
            if key in seen:
                raise ValueError(
                    "Duplicate recurring membership in one request: "
                    f"member_id={item.member_id}, "
                    f"plan_id={row['plan_id']}"
                )
            seen.add(key)

    def _check_recurring_quantity(
        self,
        request: MemberMembershipsStartRequest,
        plan_prices: dict[UUID, dict],
    ) -> None:
        """Reject quantity > 1 on a RECURRING item.

        A recurring membership is one subscription item per plan, so it must be
        quantity == 1; only one_time / trial packs may stack via quantity > 1.
        The DB trigger trg_recurring_quantity_must_be_one enforces the same
        invariant — this surfaces it early, before any write, with a clear
        message.

        Raises:
            ValueError: On the first recurring item whose quantity != 1.
        """
        for item in request.memberships:
            row = plan_prices[item.price_id]
            if (
                row["plan_type"] == PlanType.recurring
                and item.quantity != 1
            ):
                raise ValueError(
                    "Recurring membership must have quantity == 1 "
                    f"(member_id={item.member_id}, "
                    f"plan_id={row['plan_id']}, quantity={item.quantity})",
                )

    async def _resolve_payer(
        self,
        request: MemberMembershipsStartRequest,
    ) -> PayerProfile:
        """Validate the payer is an in-gym, unfrozen billing profile.

        The payer's OWN profile is resolved directly — a linked member may be
        the payer (self-pay); ``_check_links`` then enforces that every other
        member in the request is linked to this payer (the authorization
        rule). ``resolve_payer`` already raises if the account has no Stripe
        customer; card presence is not pre-checked (a missing card surfaces as
        the charge's own failure, and ``paid_with_cash`` needs no card).

        Raises:
            ValueError: If the payer is in a different gym or is frozen.
        """
        payer = await self._payer_resolver.resolve_payer(
            request.payer_member_id,
        )
        if payer.gym_id != request.gym_id:
            raise ValueError(
                f"Payer {request.payer_member_id} is not in gym {request.gym_id}",
            )
        if payer.is_frozen:
            raise ValueError(
                "Cannot start memberships: payer account is frozen",
            )
        return payer

    async def _check_links(
        self,
        request: MemberMembershipsStartRequest,
    ) -> None:
        """Every non-payer member exists, is in the gym, and has THIS payer as
        an authorized payer.

        This IS the payer-authorization rule: a payer may bill their own
        memberships and those of members who have authorized them — nothing
        else. The start op never authorizes — a member who has not authorized
        the payer is rejected with an "authorize them first" error. The payer's
        own items need no check (self-pay is always allowed).

        Raises:
            ValueError: If a member is missing, in another gym, or has not
                authorized the payer.
        """
        member_ids = {
            item.member_id
            for item in request.memberships
            if item.member_id != request.payer_member_id
        }
        if not member_ids:
            return

        sql = load_sql(SQL_DIR / "member_authorized_payers_check_batch.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "member_ids": [str(uid) for uid in member_ids],
                    "payer_member_id": str(request.payer_member_id),
                },
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
            if not row["authorized"]:
                raise ValueError(
                    f"Member {member_id} has not authorized payer "
                    f"{request.payer_member_id} — authorize them first, then "
                    f"start (the start op never authorizes payers)",
                )

    async def _check_discounts(
        self,
        request: MemberMembershipsStartRequest,
    ) -> None:
        """Every requested discount_id is live, in-gym, and not ``custom``.

        One read over the request's distinct ids. Customs are creation-only
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

        sql = load_sql(SQL_DIR / "member_memberships_start_discounts_check.sql")
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
