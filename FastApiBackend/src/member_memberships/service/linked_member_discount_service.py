"""Service for recalculating and reassigning linked discounts."""

import logging
from collections import defaultdict
from uuid import UUID

from sqlalchemy import text

from src.member_memberships import SQL_DIR
from src.member_memberships.schema.payment_sync_schema import (
    MembershipInfo,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

LINKED_SQL_DIR = SQL_DIR / "linked_discount"


class LinkedMemberDiscountService:
    """Recalculates linked discount assignments for families.

    When a linked account is added or removed, the sequential
    discount numbering may have gaps. This service calculates
    the correct sequential discounts and persists them.

    It does NOT call Stripe — the caller is responsible for
    passing the returned discount IDs to payment sync.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
    ) -> None:
        self._db_pool = db_pool

    async def calculate_linked_discount_ids(
        self,
        parent_id: UUID,
        children_ids: list[UUID],
        gym_id: UUID,
        include_memberships: list[MembershipInfo] | None = None,
        exclude_memberships: list[MembershipInfo] | None = None,
    ) -> tuple[list[UUID], list[UUID]]:
        """Calculate correct sequential linked discount IDs.

        Queries family members with a linked_discount_id and
        their active recurring memberships, then adjusts with
        include/exclude. Only children who have at least one
        active membership (after adjustments) are counted.

        Args:
            parent_id: The paying parent's member_id.
            children_ids: Linked children profile IDs.
            gym_id: The gym.
            include_memberships: Memberships being added (not
                yet persisted). Counted toward discounts and
                plan lookup.
            exclude_memberships: Memberships being removed (not
                yet persisted). Excluded from discount count
                and plan lookup.

        Returns:
            Tuple of:
            - member_ids: Sorted child profile IDs (for persist).
            - assigned_discount_ids: Matching discount IDs per
              member (None if no discount available).
        """
        all_family_ids = [parent_id, *children_ids]

        # ── Step 1: Get all active memberships ──────────────
        # Fetch every active recurring membership for the
        # entire family (parent + children). We need ALL
        # members' plans — even those without a
        # linked_discount_id — because their plans may still
        # define linked discounts that apply to the family.
        active_memberships = await self._get_family_active_memberships(all_family_ids)

        member_plans: dict[UUID, set[UUID]] = defaultdict(set)
        for row in active_memberships:
            member_plans[UUID(str(row["member_id"]))].add(
                UUID(str(row["plan_id"])),
            )

        if exclude_memberships:
            for m in exclude_memberships:
                member_plans[m.member_id].discard(m.plan_id)

        if include_memberships:
            for m in include_memberships:
                member_plans[m.member_id].add(m.plan_id)

        plan_id_set: set[UUID] = set()
        for plans in member_plans.values():
            plan_id_set.update(plans)

        # ── Step 2: Determine who needs a discount ──────────
        # A child qualifies for a linked discount if BOTH:
        #   a) They have linked_discount_id on their profile,
        #      OR they appear in include_memberships (newly
        #      added member who will get a discount)
        #   b) They still have >= 1 active membership after
        #      the exclude/include adjustments above
        # The parent never qualifies — they pay full price.
        members_with_discounts = await self._get_members_with_discounts(all_family_ids)

        # Children who currently have a linked_discount_id
        children_with_discount: set[UUID] = set()
        for row in members_with_discounts:
            child_id = UUID(str(row["member_id"]))
            if child_id != parent_id:
                children_with_discount.add(child_id)

        if include_memberships:
            for m in include_memberships:
                if m.has_linked_discount and m.member_id != parent_id:
                    children_with_discount.add(m.member_id)

        # Only keep children who have at least one remaining
        # active membership after adjustments
        qualifying_children: set[UUID] = set()
        for child_id in children_with_discount:
            if member_plans.get(child_id):
                qualifying_children.add(child_id)

        needed_count = len(qualifying_children)
        plan_ids = list(plan_id_set)
        sorted_members = sorted(qualifying_children)

        # ── Step 3: Get available discounts and assign ──────
        # Query linked discounts for the plans (ordered by
        # linked_discount_num). Take the first N to cover
        # the qualifying children, then pair them up.
        if not plan_ids:
            return sorted_members, [None] * len(sorted_members)

        available = await self._get_plan_linked_discounts(
            gym_id,
            plan_ids,
        )

        if not available:
            return sorted_members, [None] * len(sorted_members)

        memberships_linked_discounts = defaultdict(list)

        for row in available:
            memberships_linked_discounts[row["membership_plan_id"]].append(
                (row["discount_id"], row["dollar_off"])
            )

        assigned_discount_ids = []

        for i in range(needed_count):
            max_id = None
            max_discount = -1

            for _, discounts in memberships_linked_discounts.items():
                if len(discounts) <= i:
                    compare_id = discounts[-1][0]
                    compare_discount = discounts[-1][1]
                else:
                    compare_id = discounts[i][0]
                    compare_discount = discounts[i][1]

                if compare_discount > max_discount:
                    max_discount = compare_discount
                    max_id = compare_id

            assigned_discount_ids.append(max_id)

        return sorted_members, assigned_discount_ids

    async def persist_assignments(
        self,
        member_ids: list[UUID],
        discount_ids: list[UUID | None],
        gym_id: UUID,
    ) -> None:
        """Write new linked_discount_id values to profiles.

        Call this only after Stripe sync succeeds.

        Args:
            member_ids: Child profile IDs to update.
            discount_ids: Matching discount IDs (or None to clear).
            gym_id: The gym.

        Raises:
            ValueError: If member_ids and discount_ids differ
                in length.
        """
        if len(member_ids) != len(discount_ids):
            raise ValueError(
                f"member_ids ({len(member_ids)}) and "
                f"discount_ids ({len(discount_ids)}) "
                f"must be the same length"
            )

        if not member_ids:
            return

        sql = load_sql(
            LINKED_SQL_DIR / "update_linked_discount_ids.sql",
        )
        async with self._db_pool.session() as session:
            for member_id, discount_id in zip(
                member_ids,
                discount_ids,
                strict=True,
            ):
                await session.execute(
                    text(sql),
                    {
                        "member_id": str(member_id),
                        "gym_id": str(gym_id),
                        "linked_discount_id": (str(discount_id) if discount_id else None),
                    },
                )
            await session.commit()

    # ── Private Helpers ─────────────────────────────────────────

    async def _get_members_with_discounts(
        self,
        family_ids: list[UUID],
    ) -> list[dict]:
        """Get family members who have a linked_discount_id."""
        sql = load_sql(
            LINKED_SQL_DIR / "get_members_with_discounts.sql",
        )
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_ids": [str(uid) for uid in family_ids]},
            )
            return [dict(r) for r in result.mappings().fetchall()]

    async def _get_family_active_memberships(
        self,
        family_ids: list[UUID],
    ) -> list[dict]:
        """Get active recurring memberships per family member."""
        sql = load_sql(
            LINKED_SQL_DIR / "get_family_active_memberships.sql",
        )
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_ids": [str(uid) for uid in family_ids]},
            )
            return [dict(r) for r in result.mappings().fetchall()]

    async def _get_plan_linked_discounts(
        self,
        gym_id: UUID,
        plan_ids: list[UUID],
    ) -> list[dict]:
        """Get available linked discounts ordered by num."""
        sql = load_sql(
            LINKED_SQL_DIR / "get_plan_linked_discounts.sql",
        )
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "gym_id": str(gym_id),
                    "plan_ids": [str(pid) for pid in plan_ids],
                },
            )
            return [dict(r) for r in result.mappings().fetchall()]
